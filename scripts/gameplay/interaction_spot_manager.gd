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
	_schedule_next_spot(Config.SPOT_INITIAL_SPAWN_DELAY)


func stop() -> void:
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


func suspend() -> void:
	if not _active or _suspended:
		return
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
	_suspended = false
	for spot in _active_spots:
		if is_instance_valid(spot):
			spot.set_suspended(false)
	_spawn_timer.set_paused(false)
	if _spawn_timer.is_stopped():
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
	if not _active or _suspended:
		return
	_spawn_note_type()
	# Keep scheduling: timer fires repeatedly until max active count is reached.
	# If already at max, schedule a check after the minimum delay.
	_schedule_next_spot()


func _schedule_next_spot(override_delay: float = -1.0) -> void:
	if not _active or _suspended:
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


func _spawn_note_type(requested_note_type: int = -1) -> void:
	if not _active or _suspended:
		return
	# Prune any stale references first.
	_active_spots = _active_spots.filter(func(s): return is_instance_valid(s))

	if _active_spots.size() >= _get_max_active_spots():
		return  # already at cap

	if _available_anchor_ids.is_empty():
		push_warning("InteractionSpotManager: no anchor IDs available. Cannot spawn spot.")
		return

	# Pick an anchor not already occupied by a live spot.
	var occupied := _get_occupied_anchor_ids()
	var available_now: Array[String] = []
	for id in _available_anchor_ids:
		if not occupied.has(id):
			available_now.append(id)

	if available_now.is_empty():
		return  # all anchors occupied

	if _anchor_region == null or not _anchor_region.has_method("get_interaction_spot_global_rect"):
		push_warning("InteractionSpotManager: anchor region is unavailable. Cannot spawn spot.")
		return

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
	var placement := _find_clear_placement(note_type, available_now, placement_radius, radius)
	if placement.is_empty():
		print_debug("InteractionSpotManager: no non-overlapping placement available for %s." % _note_type_name(note_type))
		return
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

	spot.interaction_started.connect(_on_spot_scrub_started.bind(spot))
	spot.interaction_ended.connect(_on_spot_scrub_ended.bind(spot))
	spot.visual_motion.connect(_on_spot_visual_motion.bind(spot))
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


func _find_clear_placement(
	note_type: int,
	available_anchor_ids: Array[String],
	placement_radius: float,
	target_radius: float
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
				var checkpoint_count: int = int(_get_config_value(
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
			var checkpoint_count: int = int(_get_config_value("spot_required_checkpoint_count", Config.SPOT_REQUIRED_CHECKPOINT_COUNT))
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
	emit_signal("spot_scrub_started")


func _on_spot_scrub_ended(spot: InteractionNote) -> void:
	if _character_presenter != null and spot is RubNote:
		_character_presenter.end_rub_tremor(spot.get_instance_id())
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
