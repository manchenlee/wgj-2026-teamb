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

const PATH_GENERATION_ATTEMPTS: int = 12
const PATH_TURN_ANGLE: float = deg_to_rad(72.0)
const PLACEMENT_ATTEMPTS_PER_ANCHOR: int = 12
const NOTE_SEPARATION: float = 8.0

signal spot_scrub_started()
signal spot_scrub_ended()
signal spot_telemetry_updated(telemetry: Dictionary)
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


func start() -> void:
	_active = true
	_suspended = false
	_spawn_timer.set_paused(false)
	_telemetry_reset()
	_telemetry_physical_at_session_start = _arousal_model.physical if _arousal_model != null else 0.0
	_schedule_next_spot(Config.SPOT_INITIAL_SPAWN_DELAY)


func stop() -> void:
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

	spot.interaction_started.connect(_on_spot_scrub_started)
	spot.interaction_ended.connect(_on_spot_scrub_ended)
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
			var candidate_rect: Rect2
			var points := PackedVector2Array()
			if note_type == NoteType.SLIDE:
				var checkpoint_count: int = int(_get_config_value(
					"spot_required_checkpoint_count",
					Config.SPOT_REQUIRED_CHECKPOINT_COUNT
				))
				var spacing: float = _get_config_value("spot_checkpoint_spacing", Config.SPOT_CHECKPOINT_SPACING)
				points = _generate_sequence_points(local_center, checkpoint_count, spacing, target_radius)
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
	var valid_rect := _bounds_rect.grow(-(radius + Config.ARROW_PROMPT_EDGE_MARGIN))
	if valid_rect.size.x <= spacing or valid_rect.size.y <= spacing:
		return _build_safe_fallback(total_point_count, spacing, radius)

	for _attempt in range(PATH_GENERATION_ATTEMPTS):
		var points := PackedVector2Array([start_center])
		var direction := Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
		var turn_sign := -1.0 if _rng.randi_range(0, 1) == 0 else 1.0
		for point_index in range(1, total_point_count):
			if point_index > 1:
				direction = direction.rotated(PATH_TURN_ANGLE * turn_sign)
				turn_sign *= -1.0
			points.append(points[point_index - 1] + direction * spacing)
		if _sequence_fits(points, valid_rect, radius):
			return points

	return _build_safe_fallback(total_point_count, spacing, radius)


func _sequence_fits(points: PackedVector2Array, valid_rect: Rect2, radius: float) -> bool:
	for point in points:
		if not valid_rect.has_point(point):
			return false
	for first_index in range(points.size()):
		for second_index in range(first_index + 1, points.size()):
			if points[first_index].distance_to(points[second_index]) < radius * 2.1:
				return false
	return true


func _build_safe_fallback(point_count: int, requested_spacing: float, radius: float) -> PackedVector2Array:
	var valid_rect := _bounds_rect.grow(-(radius + Config.ARROW_PROMPT_EDGE_MARGIN))
	if valid_rect.size.length_squared() <= 0.0:
		valid_rect = Rect2(_bounds_rect.get_center() - Vector2(180.0, 180.0), Vector2(360.0, 360.0))
	var center := valid_rect.get_center()
	var spacing := minf(requested_spacing, minf(valid_rect.size.x / 3.2, valid_rect.size.y / 2.4))
	spacing = maxf(spacing, radius * 2.2)
	var template := [
		Vector2(-1.2, 0.0),
		Vector2(-0.4, -0.7),
		Vector2(0.4, 0.7),
		Vector2(1.2, 0.0),
	]
	var points := PackedVector2Array()
	for index in range(point_count):
		var template_point: Vector2 = template[index % template.size()]
		points.append((center + template_point * spacing).clamp(valid_rect.position, valid_rect.end))
	return points


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

func _on_spot_scrub_started() -> void:
	emit_signal("spot_scrub_started")


func _on_spot_scrub_ended() -> void:
	emit_signal("spot_scrub_ended")


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
		_character_presenter.show_spot_reaction("strong")
	print_debug(
		"InteractionSpotManager telemetry [completed]: incremental=+%.2f bonus=+%.2f penalty=-%.2f net=%.2f active=%d" % [
			_telemetry_incremental_gain, _telemetry_completion_bonus,
			_telemetry_penalty,
			_telemetry_incremental_gain + _telemetry_completion_bonus - _telemetry_penalty,
			_active_spots.size()
		]
	)
	_emit_telemetry()


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
	if spot.interaction_started.is_connected(_on_spot_scrub_started):
		spot.interaction_started.disconnect(_on_spot_scrub_started)
	if spot.interaction_ended.is_connected(_on_spot_scrub_ended):
		spot.interaction_ended.disconnect(_on_spot_scrub_ended)
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
