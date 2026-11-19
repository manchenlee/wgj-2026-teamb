class_name InteractionSpotManager
extends RefCounted

# ---------------------------------------------------------------------------
# InteractionSpotManager
#
# Spawns a weighted, non-overlapping set of physiological notes. Arousal changes are
# applied here from normalized progress emitted through the common InteractionNote boundary.
# ---------------------------------------------------------------------------

enum NoteType {
	CLICK,
	SLIDE,
	RUB,
}

const SlideNoteScene := preload("res://scenes/components/SlideNote.tscn")
const ClickNoteScene := preload("res://scenes/components/ClickNote.tscn")
const RubNoteScene := preload("res://scenes/components/RubNote.tscn")

const Config := preload("res://scripts/gameplay/GameConfig.gd")

const PATH_GENERATION_ATTEMPTS: int = 24
const PATH_STEP_ATTEMPTS: int = 32
const PLACEMENT_ATTEMPTS_PER_ANCHOR: int = 12
const NOTE_SEPARATION: float = 8.0

signal spot_scrub_started()
signal spot_scrub_ended()
signal spot_telemetry_updated(telemetry: Dictionary)
signal physiological_spot_completed()
signal physiological_spot_failed(progress_ratio: float, penalty: float)
signal click_audio_requested(pitch: int)
signal slide_audio_requested(pitch: int)
signal rub_audio_motion(source_id: int, pitch: int)
signal rub_audio_ended(source_id: int)
signal audio_cancel_requested()
signal chart_event_skipped(event_id: String, reason: String)

# Set by GameSessionController before activation.
var _arousal_model = null
var _character_presenter = null
var _prompt_layer: Control = null
var _anchor_region: Control = null
var _spawn_timer: Timer = null
var _phase_config = null
var _rng := RandomNumberGenerator.new()
var _bounds_rect := Rect2()
var _interaction_mask: Image = null
var _interaction_mask_layer: Control = null

var _available_anchor_ids: Array[String] = []
# All currently live spots
var _active_spots: Array[InteractionNote] = []
var _active: bool = false
var _suspended: bool = false
var bgm_position_provider: Callable
var _chart_enabled: bool = false
var _chart_events: Array[Dictionary] = []
var _chart_loop_duration: float = 0.0
var _chart_next_index: int = 0
var _chart_loop_index: int = 0
var _chart_last_position: float = -1.0
var _chart_skip_counts: Dictionary = {}
var _chart_last_skip: String = ""
var _chart_mode: String = "Production"
var _chart_run_seed: int = 2026
var _chart_variants: Array[Dictionary] = []
var _chart_variant_index: int = -1
var _chart_loop_stats: Dictionary = {}

const CHART_SPAWN_GRACE_SECONDS: float = 0.25

# Per-session rolling telemetry (accumulated across spots)
var _telemetry_incremental_gain: float = 0.0
var _telemetry_completion_bonus: float = 0.0
var _telemetry_physical_at_session_start: float = 0.0
var _telemetry_penalty: float = 0.0


func _init() -> void:
	_rng.randomize()


func setup(
	arousal_model,
	character_presenter,
	prompt_layer: Control,
	anchor_region: Control,
	spawn_timer: Timer
) -> void:
	_arousal_model = arousal_model
	_character_presenter = character_presenter
	_prompt_layer = prompt_layer
	_anchor_region = anchor_region
	_spawn_timer = spawn_timer
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)


func load_chart_file(path: String, mode: String = "Production") -> bool:
	_chart_enabled = true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Interaction chart could not be opened: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not set_chart_data(parsed):
		push_error("Interaction chart is invalid: %s" % path)
		return false
	_chart_mode = mode
	_begin_chart_loop_stats()
	return true


func set_chart_data(data: Dictionary) -> bool:
	_chart_enabled = true
	_chart_variants.clear()
	_chart_variant_index = -1
	_chart_mode = "Production"
	_chart_events.clear()
	_chart_loop_duration = float(data.get("loop_duration_seconds", 0.0))
	var raw_events: Variant = data.get("events", [])
	if int(data.get("schema_version", -1)) != 1 or _chart_loop_duration <= 0.0 or not raw_events is Array:
		return false
	var previous_spawn := -1.0
	var ids: Dictionary = {}
	for entry: Variant in raw_events:
		if not entry is Dictionary:
			return false
		var event: Dictionary = entry
		var event_id := String(event.get("id", ""))
		var kind := String(event.get("type", ""))
		var spawn := float(event.get("spawn_time", -1.0))
		var pitch := int(event.get("pitch", -1))
		var checkpoints: Variant = event.get("checkpoints", [])
		if event_id.is_empty() or ids.has(event_id) or not kind in ["click", "slide", "rub"] \
				or spawn <= previous_spawn or spawn < 0.0 or spawn >= _chart_loop_duration \
				or pitch < 0 or pitch > 127 or not checkpoints is Array:
			return false
		if kind == "slide":
			if checkpoints.size() < 3 or checkpoints.size() > 6:
				return false
			for checkpoint: Variant in checkpoints:
				if not checkpoint is Dictionary or int(checkpoint.get("pitch", -1)) < 0 \
						or int(checkpoint.get("pitch", -1)) > 127:
					return false
		ids[event_id] = true
		previous_spawn = spawn
		_chart_events.append(event)
	_chart_next_index = 0
	_chart_loop_index = 0
	_chart_last_position = -1.0
	_chart_skip_counts.clear()
	_chart_last_skip = ""
	_chart_loop_stats.clear()
	_begin_chart_loop_stats()
	return true


func load_chart_variant_bank(path: String, mode: String, run_seed: int) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int(parsed.get("schema_version", -1)) != 1 \
			or String(parsed.get("strategy", "")) != mode.to_lower() \
			or String(parsed.get("source_sha256", "")).is_empty():
		return false
	var variants: Variant = parsed.get("variants", [])
	if not variants is Array or variants.is_empty() or int(parsed.get("variant_count", -1)) != variants.size():
		return false
	var validated: Array[Dictionary] = []
	for entry: Variant in variants:
		if not entry is Dictionary:
			return false
		var chart: Dictionary = entry
		var config: Variant = chart.get("generation_config", {})
		if not config is Dictionary:
			return false
		var checker := InteractionSpotManager.new()
		if String(chart.get("source_sha256", "")) != String(parsed.get("source_sha256", "")) \
				or String(config.get("strategy", "")) != mode.to_lower() \
				or not checker.set_chart_data(chart) or (not validated.is_empty() \
				and not is_equal_approx(float(chart["loop_duration_seconds"]), float(validated[0]["loop_duration_seconds"]))):
			return false
		validated.append(chart)
	_chart_variants = validated
	_chart_enabled = true
	_chart_mode = mode
	_chart_run_seed = run_seed
	_chart_loop_index = 0
	_chart_last_position = -1.0
	_chart_skip_counts.clear()
	_chart_last_skip = ""
	_chart_loop_stats.clear()
	_select_chart_variant(0)
	return true


func _select_chart_variant(loop_index: int) -> void:
	if _chart_variants.is_empty():
		return
	_chart_variant_index = posmod(_chart_run_seed - 2026 + loop_index, _chart_variants.size())
	var chart: Dictionary = _chart_variants[_chart_variant_index]
	_chart_events.clear()
	for event: Dictionary in chart["events"]:
		_chart_events.append(event)
	_chart_loop_duration = float(chart["loop_duration_seconds"])
	_chart_next_index = 0
	_begin_chart_loop_stats()


func restart_chart_run(run_seed: int) -> void:
	if not _chart_enabled:
		return
	_chart_run_seed = run_seed
	_chart_loop_index = 0
	_chart_next_index = 0
	_chart_last_position = -1.0
	_chart_skip_counts.clear()
	_chart_last_skip = ""
	_chart_loop_stats.clear()
	if _chart_variants.is_empty():
		_begin_chart_loop_stats()
	else:
		_select_chart_variant(0)


func _begin_chart_loop_stats() -> void:
	if not _chart_enabled:
		return
	var intended := 0
	var gap_fill_clicks := 0
	for event: Dictionary in _chart_events:
		intended += (event["checkpoints"] as Array).size() if String(event["type"]) == "slide" else 1
		if String(event.get("origin", "")) == "gap_fill" and String(event["type"]) == "click":
			gap_fill_clicks += 1
	_chart_loop_stats[_chart_loop_index] = {
		"mode": _chart_mode, "run_seed": _chart_run_seed, "loop_index": _chart_loop_index,
		"variant_index": _chart_variant_index, "scheduled": _chart_events.size(),
		"intended_pitch_opportunities": intended, "spawned": 0, "skipped": 0,
		"completed": 0, "expired": 0, "skip_reasons": {},
		"spawned_types": {"click": 0, "slide": 0, "rub": 0},
		"scheduled_gap_fill_clicks": gap_fill_clicks, "spawned_gap_fill_clicks": 0,
		"skipped_gap_fill_clicks": 0, "gap_fill_skip_reasons": {},
		"spawned_pitch_opportunities": 0, "triggered_pitches": 0,
		"slide_sizes": {3: 0, 4: 0, 5: 0, 6: 0},
	}


func get_chart_loop_stats(loop_index: int = -1) -> Dictionary:
	var requested := _chart_loop_index if loop_index < 0 else loop_index
	return (_chart_loop_stats.get(requested, {}) as Dictionary).duplicate(true)


func advance_chart(playback_position: float = -1.0) -> void:
	if not _chart_enabled or not _active or _chart_loop_duration <= 0.0:
		return
	var position := playback_position
	if position < 0.0:
		if not bgm_position_provider.is_valid():
			return
		position = float(bgm_position_provider.call())
	if position < 0.0:
		return
	position = fposmod(position, _chart_loop_duration)
	if _chart_last_position < 0.0:
		# A new scene or run attaches to an already playing BGM at its current point.
		_skip_chart_before(position, "late_attach")
	elif position + CHART_SPAWN_GRACE_SECONDS < _chart_last_position:
		_skip_chart_remaining("psychological_mode" if _suspended else "loop_wrap_missed")
		_print_chart_loop_stats(_chart_loop_index)
		_chart_loop_index += 1
		if _chart_variants.is_empty():
			_chart_next_index = 0
			_begin_chart_loop_stats()
		else:
			_select_chart_variant(_chart_loop_index)
	_chart_last_position = position
	while _chart_next_index < _chart_events.size():
		var event: Dictionary = _chart_events[_chart_next_index]
		var spawn := float(event["spawn_time"])
		if spawn > position:
			break
		_chart_next_index += 1
		if _suspended:
			_record_chart_skip(event, "psychological_mode")
		elif position - spawn > CHART_SPAWN_GRACE_SECONDS:
			_record_chart_skip(event, "missed_time")
		else:
			if not _chart_variants.is_empty():
				_rng.seed = ("%d:%d:%s" % [_chart_run_seed, _chart_loop_index, String(event["id"])]).hash()
			var reason := _spawn_note_type(_chart_note_type(String(event["type"])), event)
			if reason != "spawned":
				_record_chart_skip(event, reason)
			else:
				_record_chart_spawn(event)


func _skip_chart_before(position: float, reason: String) -> void:
	while _chart_next_index < _chart_events.size() \
			and float(_chart_events[_chart_next_index]["spawn_time"]) <= position:
		_record_chart_skip(_chart_events[_chart_next_index], reason)
		_chart_next_index += 1


func _skip_chart_remaining(reason: String) -> void:
	while _chart_next_index < _chart_events.size():
		_record_chart_skip(_chart_events[_chart_next_index], reason)
		_chart_next_index += 1


func _record_chart_skip(event: Dictionary, reason: String) -> void:
	_chart_skip_counts[reason] = int(_chart_skip_counts.get(reason, 0)) + 1
	var is_gap_fill := String(event.get("origin", "")) == "gap_fill"
	var stats: Dictionary = _chart_loop_stats.get(_chart_loop_index, {})
	if not stats.is_empty():
		stats["skipped"] = int(stats["skipped"]) + 1
		var reasons: Dictionary = stats["skip_reasons"]
		reasons[reason] = int(reasons.get(reason, 0)) + 1
		if is_gap_fill:
			stats["skipped_gap_fill_clicks"] = int(stats["skipped_gap_fill_clicks"]) + 1
			var gap_reasons: Dictionary = stats["gap_fill_skip_reasons"]
			gap_reasons[reason] = int(gap_reasons.get(reason, 0)) + 1
	_chart_last_skip = "%d:%s:%s" % [_chart_loop_index, String(event["id"]), reason]
	chart_event_skipped.emit(String(event["id"]), reason)
	print_debug("InteractionSpotManager: skipped %s %s (%s)" % [
		"Gap Fill Click" if is_gap_fill else "chart event", String(event["id"]), reason])


func _record_chart_spawn(event: Dictionary) -> void:
	var stats: Dictionary = _chart_loop_stats[_chart_loop_index]
	var kind := String(event["type"])
	stats["spawned"] = int(stats["spawned"]) + 1
	if String(event.get("origin", "")) == "gap_fill":
		stats["spawned_gap_fill_clicks"] = int(stats["spawned_gap_fill_clicks"]) + 1
		print_debug("InteractionSpotManager: spawned Gap Fill Click %s" % String(event["id"]))
	var types: Dictionary = stats["spawned_types"]
	# A Rub represents one pitch opportunity, even when its source phrase is longer.
	var pitch_count := (event["checkpoints"] as Array).size() if kind == "slide" else 1
	stats["spawned_pitch_opportunities"] = int(stats["spawned_pitch_opportunities"]) + pitch_count
	if kind == "slide":
		var sizes: Dictionary = stats["slide_sizes"]
		sizes[pitch_count] = int(sizes.get(pitch_count, 0)) + 1
	types[kind] = int(types.get(kind, 0)) + 1


func _print_chart_loop_stats(loop_index: int) -> void:
	if OS.is_debug_build():
		print("MIDI chart loop stats: ", JSON.stringify(get_chart_loop_stats(loop_index)))


func _chart_note_type(kind: String) -> int:
	match kind:
		"click": return NoteType.CLICK
		"rub": return NoteType.RUB
		_: return NoteType.SLIDE


func get_chart_debug_state() -> Dictionary:
	return {
		"mode": _chart_mode,
		"run_seed": _chart_run_seed,
		"variant_index": _chart_variant_index,
		"loop": _chart_loop_index,
		"next_index": _chart_next_index,
		"skip_counts": _chart_skip_counts.duplicate(),
		"last_skip": _chart_last_skip,
	}


func set_phase_config(phase_config) -> void:
	_phase_config = phase_config


func set_available_anchor_ids(ids: Array[String]) -> void:
	_available_anchor_ids = ids.duplicate()


func set_bounds_rect(bounds_rect: Rect2) -> void:
	_bounds_rect = bounds_rect

func set_interaction_mask(mask_texture: Texture2D, display_layer: Control) -> void:
	_interaction_mask = mask_texture.get_image() if mask_texture != null else null
	_interaction_mask_layer = display_layer

func _is_inside_interaction_mask(local_point: Vector2) -> bool:
	if _interaction_mask == null or _interaction_mask_layer == null:
		return true
	var layer_size := _interaction_mask_layer.size
	var image_size := Vector2(_interaction_mask.get_size())
	if layer_size.x <= 0.0 or layer_size.y <= 0.0:
		return false
	var global_point := _prompt_layer.get_global_transform_with_canvas() * local_point
	var layer_point := _interaction_mask_layer.get_global_transform_with_canvas().affine_inverse() * global_point
	var scale_factor: float = maxf(layer_size.x / image_size.x, layer_size.y / image_size.y)
	var image_point := (layer_point - (layer_size - image_size * scale_factor) * 0.5) / scale_factor
	var pixel := Vector2i(image_point)
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= _interaction_mask.get_width() or pixel.y >= _interaction_mask.get_height():
		return false
	return _interaction_mask.get_pixelv(pixel).a >= 0.5


func _is_valid_note_center(center: Vector2) -> bool:
	return _bounds_rect.has_point(center) and _is_inside_interaction_mask(center)


func capture_active_note_global_positions() -> Dictionary:
	var positions: Dictionary = {}
	for spot in _active_spots:
		if is_instance_valid(spot):
			positions[spot] = spot.global_position
	return positions


func restore_active_note_global_positions(positions: Dictionary) -> void:
	for spot_variant in positions.keys():
		var spot := spot_variant as InteractionNote
		if is_instance_valid(spot):
			spot.global_position = positions[spot_variant]


func remove_notes_outside_interaction_mask() -> void:
	for index in range(_active_spots.size() - 1, -1, -1):
		var spot := _active_spots[index]
		if not is_instance_valid(spot):
			_active_spots.remove_at(index)
			continue
		if _note_fits_interaction_mask(spot):
			continue
		spot.set_suspended(true)
		_disconnect_spot(spot)
		_active_spots.remove_at(index)
		spot.queue_free()


func _note_fits_interaction_mask(spot: InteractionNote) -> bool:
	if spot is SlideNote:
		var slide := spot as SlideNote
		for point: Vector2 in slide.checkpoints:
			if not _is_valid_note_center(slide.position + point):
				return false
		return true
	if spot is ClickNote:
		var click := spot as ClickNote
		return _is_valid_note_center(click.position + click.target_center)
	if spot is RubNote:
		var rub := spot as RubNote
		return _is_valid_note_center(rub.position + rub.target_center)
	return true


func start() -> void:
	if _character_presenter != null:
		_character_presenter.clear_body_motion()
	_active = true
	_suspended = false
	_spawn_timer.set_paused(false)
	_telemetry_reset()
	_telemetry_physical_at_session_start = _arousal_model.physical if _arousal_model != null else 0.0
	if _chart_enabled:
		# A restart does not replay chart entries already passed in this BGM loop.
		if _chart_last_position >= 0.0 and bgm_position_provider.is_valid():
			var position := float(bgm_position_provider.call())
			if position >= 0.0:
				if position + CHART_SPAWN_GRACE_SECONDS < _chart_last_position:
					_skip_chart_remaining("loop_wrap_missed")
					_print_chart_loop_stats(_chart_loop_index)
					_chart_loop_index += 1
					if _chart_variants.is_empty():
						_chart_next_index = 0
						_begin_chart_loop_stats()
					else:
						_select_chart_variant(_chart_loop_index)
				_skip_chart_before(fposmod(position, _chart_loop_duration), "restart_elapsed")
				_chart_last_position = fposmod(position, _chart_loop_duration)
	else:
		_schedule_next_spot(Config.SPOT_INITIAL_SPAWN_DELAY)


func stop(cancel_audio: bool = true) -> void:
	if _chart_enabled and _active:
		_print_chart_loop_stats(_chart_loop_index)
	if cancel_audio:
		audio_cancel_requested.emit()
	if _character_presenter != null:
		_character_presenter.clear_body_motion()
	_active = false
	_suspended = false
	_spawn_timer.set_paused(false)
	_spawn_timer.stop()
	for spot in _active_spots:
		if is_instance_valid(spot):
			# End held input and pause the authoritative lifetime before queue_free.
			# The node remains alive until the end of the frame, so disconnect every
			# outcome signal to make phase/reset cleanup non-scoring and non-failing.
			spot.set_suspended(true)
			_disconnect_spot(spot)
			spot.queue_free()
	_active_spots.clear()


func suspend(cancel_audio: bool = true) -> void:
	if not _active or _suspended:
		return
	if cancel_audio:
		audio_cancel_requested.emit()
	_suspended = true
	if _character_presenter != null:
		_character_presenter.clear_body_motion()
	_spawn_timer.set_paused(true)
	_active_spots = _active_spots.filter(func(spot): return is_instance_valid(spot))
	for spot in _active_spots:
		spot.set_suspended(true)


func resume() -> void:
	if not _active or not _suspended:
		return
	if _chart_enabled:
		# Consume events crossed while hidden before accepting new chart spawns.
		advance_chart()
	_suspended = false
	_active_spots = _active_spots.filter(func(spot): return is_instance_valid(spot))
	for spot in _active_spots:
		spot.set_suspended(false)
	_spawn_timer.set_paused(false)
	if _chart_enabled:
		return
	if _active_spots.is_empty():
		_spawn_note_type()
		_schedule_next_spot()
	elif _spawn_timer.is_stopped():
		_schedule_next_spot()


func force_spawn_spot() -> void:
	_spawn_note_type(NoteType.SLIDE)


func force_spawn_click_note() -> void:
	_spawn_note_type(NoteType.CLICK)


func force_spawn_rub_note() -> void:
	_spawn_note_type(NoteType.RUB)


func force_complete_spot() -> void:
	if _active_spots.is_empty():
		return
	# Force-complete the most recently spawned live spot.
	for i in range(_active_spots.size() - 1, -1, -1):
		if is_instance_valid(_active_spots[i]):
			_active_spots[i].force_complete()
			return


func force_expire_spot() -> void:
	if _active_spots.is_empty():
		return
	for i in range(_active_spots.size() - 1, -1, -1):
		if is_instance_valid(_active_spots[i]):
			_active_spots[i].force_expire()
			return


# ---------------------------------------------------------------------------
# Spawn scheduling
# ---------------------------------------------------------------------------

func _on_spawn_timer_timeout() -> void:
	if not _active or _suspended or _chart_enabled:
		return
	_spawn_note_type()
	# Keep scheduling: timer fires repeatedly until max active count is reached.
	# If already at max, schedule a check after the minimum delay.
	_schedule_next_spot()


func _schedule_next_spot(override_delay: float = -1.0) -> void:
	if not _active or _suspended or _chart_enabled:
		return
	var delay: float
	if override_delay >= 0.0:
		delay = override_delay
	else:
		var min_d: float = _get_config_value("spot_spawn_delay_min", Config.SPOT_SPAWN_DELAY_MIN)
		var max_d: float = _get_config_value("spot_spawn_delay_max", Config.SPOT_SPAWN_DELAY_MAX)
		delay = _rng.randf_range(min_d, max_d)
	_spawn_timer.start(delay)


func _get_max_active_spots() -> int:
	return int(_get_config_value("spot_max_active_count", Config.SPOT_MAX_ACTIVE_COUNT))


func _get_occupied_anchor_ids() -> Array[String]:
	var occupied: Array[String] = []
	for spot in _active_spots:
		if is_instance_valid(spot) and spot.has_meta("anchor_id"):
			occupied.append(str(spot.get_meta("anchor_id")))
	return occupied


func _spawn_note_type(requested_note_type: int = -1, chart_event: Dictionary = {}) -> String:
	if not _active or _suspended:
		return "inactive"
	# Prune any stale references first.
	_active_spots = _active_spots.filter(func(s): return is_instance_valid(s))

	if _active_spots.size() >= _get_max_active_spots():
		return "active_cap"

	if _available_anchor_ids.is_empty():
		push_warning("InteractionSpotManager: no anchor IDs available. Cannot spawn spot.")
		return "no_anchors"

	# Pick an anchor not already occupied by a live spot.
	var occupied := _get_occupied_anchor_ids()
	var available_now: Array[String] = []
	for id in _available_anchor_ids:
		if not occupied.has(id):
			available_now.append(id)

	if available_now.is_empty():
		return "anchors_occupied"

	if _anchor_region == null or not _anchor_region.has_method("get_interaction_spot_global_rect"):
		push_warning("InteractionSpotManager: anchor region is unavailable. Cannot spawn spot.")
		return "anchor_region_missing"

	var note_type: int = requested_note_type
	if note_type < 0:
		note_type = _select_weighted_note_type()

	var is_circular_note := note_type == NoteType.CLICK or note_type == NoteType.RUB
	var radius: float = (
		Config.RUB_TARGET_RADIUS
		if note_type == NoteType.RUB
		else _get_config_value("spot_checkpoint_radius", Config.SPOT_CHECKPOINT_RADIUS)
	)
	var placement_radius := radius * 2.0 + 4.0 if is_circular_note else radius
	var slide_point_count := (chart_event.get("checkpoints", []) as Array).size() if note_type == NoteType.SLIDE and not chart_event.is_empty() else -1
	var placement := _find_clear_placement(note_type, available_now, placement_radius, radius, slide_point_count)
	if placement.is_empty():
		print_debug("InteractionSpotManager: no non-overlapping placement available for %s." % _note_type_name(note_type))
		return "unsafe_placement"
	var anchor_id: String = placement.anchor_id
	var local_center: Vector2 = placement.center
	var placement_rect: Rect2 = placement.rect
	var spot: InteractionNote
	if note_type == NoteType.CLICK:
		var click_extent := placement_radius
		var click_size := Vector2.ONE * click_extent * 2.0
		spot = ClickNoteScene.instantiate() as InteractionNote
		spot.setup({
			"spot_lifetime": _get_config_value("click_note_lifetime", Config.CLICK_NOTE_LIFETIME),
			"target_center": click_size * 0.5,
			"target_radius": radius,
		})
		spot.custom_minimum_size = click_size
		spot.size = click_size
		spot.pivot_offset = click_size * 0.5
		spot.position = local_center - click_size * 0.5
	elif note_type == NoteType.RUB:
		var rub_extent := placement_radius
		var rub_size := Vector2.ONE * rub_extent * 2.0
		spot = RubNoteScene.instantiate() as InteractionNote
		spot.setup({
			"spot_lifetime": _get_config_value("rub_note_lifetime", Config.RUB_NOTE_LIFETIME),
			"required_scrub_distance": Config.RUB_REQUIRED_SCRUB_DISTANCE,
			"valid_motion_threshold": Config.RUB_VALID_MOTION_THRESHOLD,
			"max_delta_per_event": Config.RUB_MAX_DELTA_PER_EVENT,
			"target_center": rub_size * 0.5,
			"target_radius": radius,
		})
		spot.custom_minimum_size = rub_size
		spot.size = rub_size
		spot.pivot_offset = rub_size * 0.5
		spot.position = local_center - rub_size * 0.5
	else:
		var sequence_points: PackedVector2Array = placement.points
		var path_rect: Rect2 = placement_rect
		var local_points := PackedVector2Array()
		for point in sequence_points:
			local_points.append(point - path_rect.position)
		spot = SlideNoteScene.instantiate() as InteractionNote
		spot.setup(_build_spot_config(local_points))
		spot.custom_minimum_size = path_rect.size
		spot.size = path_rect.size
		spot.pivot_offset = path_rect.size * 0.5
		spot.position = path_rect.position
	# Tag the spot with its anchor so we can avoid re-using it while live.
	spot.set_meta("anchor_id", anchor_id)
	spot.set_meta("note_type", note_type)
	spot.set_meta("placement_rect", placement_rect)
	if not chart_event.is_empty():
		spot.set_meta("chart_id", String(chart_event["id"]))
		spot.set_meta("chart_loop_index", _chart_loop_index)
		spot.set_meta("bound_pitch", int(chart_event["pitch"]))
		if note_type == NoteType.SLIDE:
			var pitches := PackedInt32Array()
			for checkpoint: Dictionary in chart_event["checkpoints"]:
				pitches.append(int(checkpoint["pitch"]))
			spot.set_meta("checkpoint_pitches", pitches)

	spot.interaction_started.connect(_on_spot_scrub_started.bind(spot))
	spot.interaction_ended.connect(_on_spot_scrub_ended.bind(spot))
	spot.visual_motion.connect(_on_spot_visual_motion.bind(spot))
	spot.audio_note_reached.connect(_on_spot_audio_note_reached.bind(spot))
	spot.audio_motion_valid.connect(_on_spot_audio_motion_valid.bind(spot))
	spot.progressed.connect(_on_spot_progressed.bind(spot))
	spot.completed.connect(_on_spot_completed.bind(spot))
	spot.expired.connect(_on_spot_expired.bind(spot))

	_prompt_layer.add_child(spot)
	_active_spots.append(spot)

	print_debug(
		"InteractionSpotManager: spawned %s anchor='%s' start=%s bounds=%s radius=%.0f active=%d" % [
			_note_type_name(note_type),
			anchor_id,
			str(local_center),
			str(_bounds_rect),
			radius,
			_active_spots.size()
		]
	)
	return "spawned"


func _find_clear_placement(
	note_type: int,
	available_anchor_ids: Array[String],
	placement_radius: float,
	target_radius: float,
	slide_point_count: int = -1
) -> Dictionary:
	var anchor_ids := available_anchor_ids.duplicate()
	_shuffle_strings(anchor_ids)
	var fallback_global_center := _get_fallback_global_center()
	var inverse_prompt_transform := _prompt_layer.get_global_transform_with_canvas().affine_inverse()
	for anchor_id in anchor_ids:
		var global_rect: Rect2 = _anchor_region.call(
			"get_interaction_spot_global_rect",
			StringName(anchor_id),
			fallback_global_center
		)
		for _attempt in range(PLACEMENT_ATTEMPTS_PER_ANCHOR):
			var global_center := _pick_global_center_in_rect(global_rect, placement_radius)
			var local_center: Vector2 = inverse_prompt_transform * global_center
			local_center = _clamp_center_to_bounds(local_center, placement_radius)
			if not _is_valid_note_center(local_center):
				continue
			var candidate_rect: Rect2
			var points := PackedVector2Array()
			if note_type == NoteType.SLIDE:
				var checkpoint_count: int = slide_point_count - 1 if slide_point_count >= 2 else int(_get_config_value(
					"spot_required_checkpoint_count",
					Config.SPOT_REQUIRED_CHECKPOINT_COUNT
				))
				var spacing: float = _get_config_value("spot_checkpoint_spacing", Config.SPOT_CHECKPOINT_SPACING)
				points = _generate_sequence_points(local_center, checkpoint_count, spacing, target_radius)
				if points.is_empty():
					continue
				# Include every checkpoint's fully expanded approach circle.
				candidate_rect = _get_path_rect(points, target_radius * 2.0 + 4.0)
			else:
				candidate_rect = Rect2(
					local_center - Vector2.ONE * placement_radius,
					Vector2.ONE * placement_radius * 2.0
				)
			if _is_placement_clear(candidate_rect):
				return {
					"anchor_id": anchor_id,
					"center": local_center,
					"rect": candidate_rect,
					"points": points,
				}
	# Existing anatomical anchors may not cover a new pose's usable white area.
	# Search the bounded mask before giving up on an otherwise valid note.
	for _attempt in range(100):
		var local_center := Vector2(
			_rng.randf_range(_bounds_rect.position.x, _bounds_rect.end.x),
			_rng.randf_range(_bounds_rect.position.y, _bounds_rect.end.y)
		)
		local_center = _clamp_center_to_bounds(local_center, placement_radius)
		if not _is_valid_note_center(local_center):
			continue
		var points := PackedVector2Array()
		var candidate_rect: Rect2
		if note_type == NoteType.SLIDE:
			var checkpoint_count: int = slide_point_count - 1 if slide_point_count >= 2 else int(_get_config_value("spot_required_checkpoint_count", Config.SPOT_REQUIRED_CHECKPOINT_COUNT))
			var spacing: float = _get_config_value("spot_checkpoint_spacing", Config.SPOT_CHECKPOINT_SPACING)
			points = _generate_sequence_points(local_center, checkpoint_count, spacing, target_radius)
			if points.is_empty():
				continue
			candidate_rect = _get_path_rect(points, target_radius * 2.0 + 4.0)
		else:
			candidate_rect = Rect2(local_center - Vector2.ONE * placement_radius, Vector2.ONE * placement_radius * 2.0)
		if _is_placement_clear(candidate_rect):
			return {"anchor_id": available_anchor_ids[0], "center": local_center, "rect": candidate_rect, "points": points}
	return {}


func _is_placement_clear(candidate_rect: Rect2) -> bool:
	for active_spot in _active_spots:
		if not is_instance_valid(active_spot):
			continue
		var active_rect := Rect2(active_spot.position, active_spot.size)
		if active_spot.has_meta("placement_rect"):
			active_rect = active_spot.get_meta("placement_rect") as Rect2
		if candidate_rect.grow(NOTE_SEPARATION).intersects(active_rect, true):
			return false
	return true


func _shuffle_strings(values: Array[String]) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var previous := values[index]
		values[index] = values[swap_index]
		values[swap_index] = previous


func _select_weighted_note_type() -> int:
	var click_weight: float = maxf(0.0, float(_get_config_value("click_note_weight", Config.CLICK_NOTE_WEIGHT)))
	var slide_weight: float = maxf(0.0, float(_get_config_value("slide_note_weight", Config.SLIDE_NOTE_WEIGHT)))
	var rub_weight: float = maxf(0.0, float(_get_config_value("rub_note_weight", Config.RUB_NOTE_WEIGHT)))
	var total_weight := click_weight + slide_weight + rub_weight
	if total_weight <= 0.0:
		push_warning("InteractionSpotManager: all note weights are zero; falling back to ClickNote.")
		return NoteType.CLICK
	return _select_note_type_for_roll(_rng.randf() * total_weight, click_weight, slide_weight, rub_weight)


func _select_note_type_for_roll(
	roll: float,
	click_weight: float,
	slide_weight: float,
	rub_weight: float
) -> int:
	var safe_click_weight := maxf(0.0, click_weight)
	var safe_slide_weight := maxf(0.0, slide_weight)
	var safe_rub_weight := maxf(0.0, rub_weight)
	var total_weight := safe_click_weight + safe_slide_weight + safe_rub_weight
	if total_weight <= 0.0:
		push_warning("InteractionSpotManager: all note weights are zero; falling back to ClickNote.")
		return NoteType.CLICK
	var safe_roll := maxf(0.0, roll)
	if safe_roll >= total_weight:
		safe_roll = total_weight * 0.9999999
	if safe_roll < safe_click_weight:
		return NoteType.CLICK
	if safe_roll < safe_click_weight + safe_slide_weight:
		return NoteType.SLIDE
	return NoteType.RUB


func _note_type_name(note_type: int) -> StringName:
	match note_type:
		NoteType.CLICK:
			return &"click"
		NoteType.RUB:
			return &"rub"
		_:
			return &"slide"


func _generate_sequence_points(
	start_center: Vector2,
	required_checkpoint_count: int,
	spacing: float,
	radius: float
) -> PackedVector2Array:
	var total_point_count := maxi(required_checkpoint_count + 1, 2)
	if not _is_valid_note_center(start_center):
		return PackedVector2Array()
	for _attempt in range(PATH_GENERATION_ATTEMPTS):
		var points := PackedVector2Array([start_center])
		for point_index in range(1, total_point_count):
			var found_next := false
			for _step_attempt in range(PATH_STEP_ATTEMPTS):
				var direction := Vector2.from_angle(_rng.randf_range(0.0, TAU))
				var step_length := spacing * _rng.randf_range(0.95, 1.25)
				var next_point: Vector2 = points[-1] + direction * step_length
				if not _is_valid_note_center(next_point):
					continue
				var separated := true
				for previous_point: Vector2 in points:
					if next_point.distance_to(previous_point) < radius * 2.1:
						separated = false
						break
				if not separated:
					continue
				points.append(next_point)
				found_next = true
				break
			if not found_next:
				break
		if points.size() == total_point_count:
			return points
	return PackedVector2Array()


func _get_path_rect(points: PackedVector2Array, padding: float) -> Rect2:
	if points.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ONE * padding * 2.0)
	var path_rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		path_rect = path_rect.expand(point)
	return path_rect.grow(padding)


func _pick_global_center_in_rect(global_rect: Rect2, radius: float) -> Vector2:
	if global_rect.size.length_squared() <= 0.0:
		return global_rect.position
	var inset := radius
	var min_x := global_rect.position.x + inset
	var max_x := global_rect.end.x - inset
	var min_y := global_rect.position.y + inset
	var max_y := global_rect.end.y - inset
	if min_x > max_x or min_y > max_y:
		return global_rect.get_center()
	return Vector2(
		_rng.randf_range(min_x, max_x),
		_rng.randf_range(min_y, max_y)
	)


func _get_fallback_global_center() -> Vector2:
	if _anchor_region != null:
		return _anchor_region.get_global_rect().get_center()
	if _prompt_layer != null:
		return _prompt_layer.get_global_rect().get_center()
	return Vector2.ZERO


func _clamp_center_to_bounds(center: Vector2, radius: float) -> Vector2:
	if _bounds_rect.size.length_squared() <= 0.0:
		return center
	var inset := radius + Config.ARROW_PROMPT_EDGE_MARGIN
	var min_x := _bounds_rect.position.x + inset
	var max_x := _bounds_rect.end.x - inset
	var min_y := _bounds_rect.position.y + inset
	var max_y := _bounds_rect.end.y - inset
	if min_x > max_x or min_y > max_y:
		return _bounds_rect.get_center()
	return Vector2(
		clampf(center.x, min_x, max_x),
		clampf(center.y, min_y, max_y)
	)


# ---------------------------------------------------------------------------
# Signal handlers — all arousal changes happen here, never inside InteractionNote
# ---------------------------------------------------------------------------

func _on_spot_scrub_started(spot: InteractionNote) -> void:
	spot.set_meta("was_interacted", true)
	if spot is RubNote:
		spot.set_meta("rub_pitch_triggered", false)
	emit_signal("spot_scrub_started")


func _on_spot_scrub_ended(spot: InteractionNote) -> void:
	if _character_presenter != null and spot is RubNote:
		_character_presenter.end_rub_tremor(spot.get_instance_id())
	if spot is RubNote:
		rub_audio_ended.emit(spot.get_instance_id())
	emit_signal("spot_scrub_ended")


func _on_spot_visual_motion(direction: Vector2, intensity: float, spot: InteractionNote) -> void:
	if _character_presenter == null:
		return
	if spot is ClickNote:
		_character_presenter.show_click_jolt(direction)
	elif spot is SlideNote:
		spot.set_meta("last_visual_direction", direction)
		_character_presenter.show_slide_sway(direction)
	elif spot is RubNote:
		_character_presenter.update_rub_tremor(spot.get_instance_id(), intensity)


func _on_spot_audio_note_reached(spot: InteractionNote) -> void:
	if not _active or _suspended:
		return
	if spot is ClickNote:
		_count_chart_pitch_trigger(spot)
		click_audio_requested.emit(int(spot.get_meta("bound_pitch", -1)))
	elif spot is SlideNote:
		var pitches: PackedInt32Array = spot.get_meta("checkpoint_pitches", PackedInt32Array())
		var reached_index := (spot as SlideNote).get_next_checkpoint_index() - 1
		var pitch := pitches[reached_index] if reached_index >= 0 and reached_index < pitches.size() else -1
		_count_chart_pitch_trigger(spot)
		slide_audio_requested.emit(pitch)


func _on_spot_audio_motion_valid(spot: InteractionNote) -> void:
	if _active and not _suspended and spot is RubNote:
		if not bool(spot.get_meta("rub_pitch_triggered", false)):
			_count_chart_pitch_trigger(spot)
			spot.set_meta("rub_pitch_triggered", true)
		rub_audio_motion.emit(spot.get_instance_id(), int(spot.get_meta("bound_pitch", -1)))


func _count_chart_pitch_trigger(spot: InteractionNote) -> void:
	if not spot.has_meta("chart_loop_index"):
		return
	var stats: Dictionary = _chart_loop_stats.get(int(spot.get_meta("chart_loop_index")), {})
	if not stats.is_empty():
		stats["triggered_pitches"] = int(stats["triggered_pitches"]) + 1


func _on_spot_progressed(progress_delta: float, _spot: InteractionNote) -> void:
	if _arousal_model == null:
		return
	var total_gain: float = _get_config_value("spot_progress_gain_total", Config.SPOT_PROGRESS_GAIN_TOTAL)
	var gain := progress_delta * total_gain
	_arousal_model.apply_physical(gain)
	_arousal_model.refresh_physical_activity()
	_telemetry_incremental_gain += gain
	_emit_telemetry()


func _on_spot_completed(spot: InteractionNote) -> void:
	_record_chart_outcome(spot, "completed")
	if spot is RubNote:
		rub_audio_ended.emit(spot.get_instance_id())
	_active_spots = _active_spots.filter(func(s): return is_instance_valid(s) and s != spot)
	_disconnect_spot(spot)
	var bonus: float = _get_config_value("spot_completion_bonus", Config.SPOT_COMPLETION_BONUS)
	if _arousal_model != null:
		_arousal_model.apply_physical(bonus)
		_arousal_model.refresh_physical_activity()
	_telemetry_completion_bonus += bonus
	if _character_presenter != null:
		_character_presenter.show_body_outcome(
			_note_type_name(int(spot.get_meta("note_type", -1))),
			true,
			spot.get_meta("last_visual_direction", Vector2.RIGHT),
			spot.get_instance_id()
		)
		_character_presenter.show_spot_reaction("strong")
		_character_presenter.show_success_heart_burst(spot.position + (spot.size * 0.5))
	print_debug(
		"InteractionSpotManager telemetry [completed]: incremental=+%.2f bonus=+%.2f penalty=-%.2f net=%.2f active=%d" % [
			_telemetry_incremental_gain, _telemetry_completion_bonus,
			_telemetry_penalty,
			_telemetry_incremental_gain + _telemetry_completion_bonus - _telemetry_penalty,
			_active_spots.size()
		]
	)
	_emit_telemetry()
	physiological_spot_completed.emit()


func _on_spot_expired(progress_ratio: float, spot: InteractionNote, is_timeout_failure: bool = true) -> void:
	_record_chart_outcome(spot, "expired")
	if spot is RubNote:
		rub_audio_ended.emit(spot.get_instance_id())
	_active_spots = _active_spots.filter(func(s): return is_instance_valid(s) and s != spot)
	_disconnect_spot(spot)
	var penalty := 0.0
	if progress_ratio < 0.1:
		penalty = _get_config_value("spot_expiry_penalty_ignored", Config.SPOT_EXPIRY_PENALTY_IGNORED)
	elif progress_ratio < 0.5:
		penalty = _get_config_value("spot_expiry_penalty_partial", Config.SPOT_EXPIRY_PENALTY_PARTIAL)
	if penalty > 0.0 and _arousal_model != null:
		_arousal_model.apply_physical(-penalty)
	_telemetry_penalty += penalty
	if _character_presenter != null:
		_character_presenter.show_spot_reaction("mild")
		if spot is SlideNote and (spot as SlideNote).is_armed():
			_character_presenter.show_body_outcome(&"slide", false, -spot.get_meta("last_visual_direction", Vector2.RIGHT))
		elif spot is RubNote and progress_ratio > 0.0:
			_character_presenter.show_body_outcome(&"rub", false, Vector2(-1.0, 0.6), spot.get_instance_id())
	if is_timeout_failure:
		physiological_spot_failed.emit(progress_ratio, penalty)
	print_debug(
		"InteractionSpotManager telemetry [expired_%.2f]: incremental=+%.2f penalty=-%.2f net=%.2f active=%d" % [
			progress_ratio, _telemetry_incremental_gain,
			_telemetry_penalty,
			_telemetry_incremental_gain + _telemetry_completion_bonus - _telemetry_penalty,
			_active_spots.size()
		]
	)
	_emit_telemetry()


func _record_chart_outcome(spot: InteractionNote, outcome: String) -> void:
	if not spot.has_meta("chart_loop_index"):
		return
	var owner_loop := int(spot.get_meta("chart_loop_index"))
	var stats: Dictionary = _chart_loop_stats.get(owner_loop, {})
	if not stats.is_empty():
		stats[outcome] = int(stats[outcome]) + 1
		if owner_loop < _chart_loop_index:
			_print_chart_loop_stats(owner_loop)


func _disconnect_spot(spot: InteractionNote) -> void:
	var started_callback := _on_spot_scrub_started.bind(spot)
	if spot.interaction_started.is_connected(started_callback):
		spot.interaction_started.disconnect(started_callback)
	var ended_callback := _on_spot_scrub_ended.bind(spot)
	if spot.interaction_ended.is_connected(ended_callback):
		spot.interaction_ended.disconnect(ended_callback)
	var motion_callback := _on_spot_visual_motion.bind(spot)
	if spot.visual_motion.is_connected(motion_callback):
		spot.visual_motion.disconnect(motion_callback)
	var audio_callback := _on_spot_audio_note_reached.bind(spot)
	if spot.audio_note_reached.is_connected(audio_callback):
		spot.audio_note_reached.disconnect(audio_callback)
	var rub_audio_callback := _on_spot_audio_motion_valid.bind(spot)
	if spot.audio_motion_valid.is_connected(rub_audio_callback):
		spot.audio_motion_valid.disconnect(rub_audio_callback)
	var progressed_callback := _on_spot_progressed.bind(spot)
	if spot.progressed.is_connected(progressed_callback):
		spot.progressed.disconnect(progressed_callback)
	var completed_callback := _on_spot_completed.bind(spot)
	if spot.completed.is_connected(completed_callback):
		spot.completed.disconnect(completed_callback)
	var expired_callback := _on_spot_expired.bind(spot)
	if spot.expired.is_connected(expired_callback):
		spot.expired.disconnect(expired_callback)


# ---------------------------------------------------------------------------
# Telemetry
# ---------------------------------------------------------------------------

func _telemetry_reset() -> void:
	_telemetry_incremental_gain = 0.0
	_telemetry_completion_bonus = 0.0
	_telemetry_physical_at_session_start = 0.0
	_telemetry_penalty = 0.0


func _emit_telemetry() -> void:
	emit_signal("spot_telemetry_updated", _build_telemetry_dict("active"))


func _build_telemetry_dict(outcome: String) -> Dictionary:
	var physical_now: float = _arousal_model.physical if _arousal_model != null else 0.0
	return {
		"outcome": outcome,
		"incremental_gain": _telemetry_incremental_gain,
		"completion_bonus": _telemetry_completion_bonus,
		"penalty": _telemetry_penalty,
		"physical_now": physical_now,
		"net_physical_change": _telemetry_incremental_gain + _telemetry_completion_bonus - _telemetry_penalty,
		"active_spots": _active_spots.size(),
		"active_note_type": _get_active_note_type_name(),
		"active_note_types": _get_active_note_type_names(),
	}


func get_debug_spot_state() -> String:
	_active_spots = _active_spots.filter(func(s): return is_instance_valid(s))
	if _active_spots.is_empty():
		return "none"
	return "active=%d types=%s" % [_active_spots.size(), ",".join(_get_active_note_type_names())]


func _get_active_note_type_name() -> StringName:
	for spot in _active_spots:
		if is_instance_valid(spot) and spot.has_meta("note_type"):
			return _note_type_name(int(spot.get_meta("note_type")))
	return &"none"


func _get_active_note_type_names() -> PackedStringArray:
	var note_types := PackedStringArray()
	for spot in _active_spots:
		if is_instance_valid(spot) and spot.has_meta("note_type"):
			note_types.append(String(_note_type_name(int(spot.get_meta("note_type")))))
	return note_types


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

func _build_spot_config(checkpoint_points: PackedVector2Array) -> Dictionary:
	return {
		"spot_lifetime": _get_config_value("slide_checkpoint_time_limit", Config.SLIDE_CHECKPOINT_TIME_LIMIT),
		"checkpoint_radius": _get_config_value("spot_checkpoint_radius", Config.SPOT_CHECKPOINT_RADIUS),
		"checkpoints": checkpoint_points,
	}


func _get_config_value(key: String, fallback: Variant) -> Variant:
	if _phase_config == null:
		return fallback
	# PhaseConfig is a plain RefCounted class. GDScript Object.get() works for
	# declared 'var' properties on RefCounted subclasses.
	var value = _phase_config.get(key)
	if value == null:
		return fallback
	return value
