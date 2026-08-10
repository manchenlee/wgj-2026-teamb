class_name InteractionSpotManager
extends RefCounted

# ---------------------------------------------------------------------------
# InteractionSpotManager
#
# Spawns one ordered checkpoint sequence at a time. Arousal changes are
# applied here from normalized progress emitted by the interaction node.
# ---------------------------------------------------------------------------

const InteractionSpotScene := preload("res://scenes/components/InteractionSpot.tscn")

const Config := preload("res://scripts/gameplay/GameConfig.gd")

const PATH_GENERATION_ATTEMPTS: int = 12
const PATH_TURN_ANGLE: float = deg_to_rad(72.0)

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
var _last_anchor_id: String = ""
# All currently live spots
var _active_spots: Array[InteractionSpot] = []
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
	_schedule_next_spot(0.5)  # brief initial delay before first spawn


func stop() -> void:
	_active = false
	_suspended = false
	_spawn_timer.set_paused(false)
	_spawn_timer.stop()
	for spot in _active_spots:
		if is_instance_valid(spot):
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
	_spawn_spot()


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
	_spawn_spot()
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


func _spawn_spot() -> void:
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

	var anchor_id := _pick_anchor_id_from(available_now)
	if _anchor_region == null or not _anchor_region.has_method("get_interaction_spot_global_rect"):
		push_warning("InteractionSpotManager: anchor region is unavailable. Cannot spawn spot.")
		return

	var fallback_global_center := _get_fallback_global_center()
	var global_rect: Rect2 = _anchor_region.call(
		"get_interaction_spot_global_rect",
		StringName(anchor_id),
		fallback_global_center
	)

	var radius: float = _get_config_value("spot_checkpoint_radius", Config.SPOT_CHECKPOINT_RADIUS)
	var global_center: Vector2 = _pick_global_center_in_rect(global_rect, radius)
	# Convert to PromptLayer local coordinates.
	var local_center: Vector2 = _prompt_layer.get_global_transform_with_canvas().affine_inverse() * global_center
	local_center = _clamp_center_to_bounds(local_center, radius)
	var checkpoint_count: int = int(_get_config_value("spot_required_checkpoint_count", Config.SPOT_REQUIRED_CHECKPOINT_COUNT))
	var spacing: float = _get_config_value("spot_checkpoint_spacing", Config.SPOT_CHECKPOINT_SPACING)
	var sequence_points := _generate_sequence_points(local_center, checkpoint_count, spacing, radius)
	var path_rect := _get_path_rect(sequence_points, radius + 10.0)
	var local_points := PackedVector2Array()
	for point in sequence_points:
		local_points.append(point - path_rect.position)

	var spot := InteractionSpotScene.instantiate() as InteractionSpot
	spot.setup(_build_spot_config(local_points))
	spot.custom_minimum_size = path_rect.size
	spot.size = path_rect.size
	spot.pivot_offset = path_rect.size * 0.5
	spot.position = path_rect.position
	# Tag the spot with its anchor so we can avoid re-using it while live.
	spot.set_meta("anchor_id", anchor_id)

	spot.scrub_started.connect(_on_spot_scrub_started)
	spot.scrub_ended.connect(_on_spot_scrub_ended)
	spot.progressed.connect(_on_spot_progressed.bind(spot))
	spot.completed.connect(_on_spot_completed.bind(spot))
	spot.expired.connect(_on_spot_expired.bind(spot))

	_prompt_layer.add_child(spot)
	_active_spots.append(spot)
	_last_anchor_id = anchor_id

	print_debug(
		"InteractionSpotManager: spawned sequence anchor='%s' start=%s bounds=%s checkpoint_radius=%.0f active=%d" % [
			anchor_id,
			str(local_center),
			str(_bounds_rect),
			radius,
			_active_spots.size()
		]
	)


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


func _pick_anchor_id_from(candidates: Array[String]) -> String:
	if candidates.size() == 1:
		return candidates[0]
	var pick := candidates[_rng.randi_range(0, candidates.size() - 1)]
	# Avoid repeating last anchor if possible.
	if pick == _last_anchor_id and candidates.size() > 1:
		pick = candidates[_rng.randi_range(0, candidates.size() - 1)]
	return pick


# ---------------------------------------------------------------------------
# Signal handlers — all arousal changes happen here, never inside InteractionSpot
# ---------------------------------------------------------------------------

func _on_spot_scrub_started() -> void:
	emit_signal("spot_scrub_started")


func _on_spot_scrub_ended() -> void:
	emit_signal("spot_scrub_ended")


func _on_spot_progressed(progress_delta: float, _spot: InteractionSpot) -> void:
	if _arousal_model == null:
		return
	var total_gain: float = _get_config_value("spot_progress_gain_total", Config.SPOT_PROGRESS_GAIN_TOTAL)
	var gain := progress_delta * total_gain
	_arousal_model.apply_physical(gain)
	_arousal_model.refresh_physical_activity()
	_telemetry_incremental_gain += gain
	_emit_telemetry()


func _on_spot_completed(spot: InteractionSpot) -> void:
	_active_spots = _active_spots.filter(func(s): return is_instance_valid(s) and s != spot)
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


func _on_spot_expired(progress_ratio: float, spot: InteractionSpot, is_timeout_failure: bool = true) -> void:
	_active_spots = _active_spots.filter(func(s): return is_instance_valid(s) and s != spot)
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


func _disconnect_spot(spot: InteractionSpot) -> void:
	if spot.scrub_started.is_connected(_on_spot_scrub_started):
		spot.scrub_started.disconnect(_on_spot_scrub_started)
	if spot.scrub_ended.is_connected(_on_spot_scrub_ended):
		spot.scrub_ended.disconnect(_on_spot_scrub_ended)


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
		"active_spots": _active_spots.size()
	}


func get_debug_spot_state() -> String:
	_active_spots = _active_spots.filter(func(s): return is_instance_valid(s))
	if _active_spots.is_empty():
		return "none"
	return "active=%d" % _active_spots.size()


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

func _build_spot_config(checkpoint_points: PackedVector2Array) -> Dictionary:
	return {
		"spot_lifetime": _get_config_value("spot_lifetime", Config.SPOT_LIFETIME),
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
