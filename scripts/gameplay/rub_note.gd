class_name RubNote
extends InteractionNote

const CursorHitAreaClass := preload("res://scripts/gameplay/cursor_hit_area.gd")
const HEART_TEXTURE := preload("res://assets/art/ui/gameplay/img_heart.png")
const HINT_ORBIT_RADIUS: float = 12.0
const HINT_ORBIT_PERIOD: float = 1.6

var required_scrub_distance: float = 600.0
var valid_motion_threshold: float = 3.0
var max_delta_per_event: float = 24.0
var target_center: Vector2 = Vector2(212.0, 212.0)
var target_radius: float = 104.0
var mouse_hit_radius: float = CursorHitAreaClass.NOTE_HIT_MARGIN
var accumulated_scrub_distance: float = 0.0

var _mouse_held: bool = false
var _active_touch_index: int = -1
var _has_pointer_sample: bool = false
var _last_pointer_pos: Vector2 = Vector2.ZERO
var _pending_motion_distance: float = 0.0
var _hint_orbit_angle: float = -PI * 0.5
var _last_feedback_frame: int = -1

@onready var friction_hint: TextureRect = $FrictionHint


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	super._ready()
	friction_hint.size = Vector2.ONE * target_radius * 0.95
	friction_hint.rotation = 0.0
	_update_friction_hint_position()


func setup(config: Dictionary) -> void:
	super.setup(config)
	required_scrub_distance = float(config.get("required_scrub_distance", 600.0))
	valid_motion_threshold = float(config.get("valid_motion_threshold", 3.0))
	max_delta_per_event = float(config.get("max_delta_per_event", 24.0))
	target_center = config.get("target_center", Vector2(212.0, 212.0)) as Vector2
	target_radius = float(config.get("target_radius", 104.0))
	mouse_hit_radius = float(config.get("mouse_hit_radius", CursorHitAreaClass.NOTE_HIT_MARGIN))
	if is_node_ready():
		friction_hint.size = Vector2.ONE * target_radius * 0.95
		_update_friction_hint_position()


func _process(delta: float) -> void:
	super._process(delta)
	_hint_orbit_angle = wrapf(_hint_orbit_angle - TAU * delta / HINT_ORBIT_PERIOD, 0.0, TAU)
	_update_friction_hint_position()


func _update_friction_hint_position() -> void:
	friction_hint.position = target_center - friction_hint.size * 0.5 \
		+ Vector2.from_angle(_hint_orbit_angle) * HINT_ORBIT_RADIUS


func get_progress_ratio() -> float:
	return clampf(accumulated_scrub_distance / maxf(required_scrub_distance, 0.001), 0.0, 1.0)


func is_rubbing() -> bool:
	return _mouse_held or _active_touch_index >= 0


func _input(event: InputEvent) -> void:
	# GUI focus can belong to a sibling Control on the first visible frame.
	# Match SlideNote's viewport route, then validate against the Rub circle.
	_handle_input(event, true)


func _gui_input(event: InputEvent) -> void:
	# Keep the local-coordinate entry point for existing direct input tests.
	if _handle_input(event, false):
		accept_event()


func _handle_input(event: InputEvent, global_coordinates: bool) -> bool:
	if _resolved or _suspended or not visible:
		return false
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return false
		var pointer_position := _to_local_pointer_position(mouse_button.position) if global_coordinates else mouse_button.position
		if mouse_button.pressed:
			# A new press proves an earlier release was lost (for example after
			# leaving the window). Do not leave the old drag blocking this one.
			if _mouse_held:
				_stop_rubbing()
			if _active_touch_index < 0 and _is_inside_target(pointer_position, mouse_hit_radius):
				_mouse_held = true
				_last_feedback_frame = -1
				_set_pointer_sample(pointer_position)
				_begin_interaction()
				queue_redraw()
				return true
		elif _mouse_held:
			_process_pointer_move(pointer_position)
			_stop_rubbing()
			return true
		return false
	if event is InputEventMouseMotion and _mouse_held:
		var mouse_motion := event as InputEventMouseMotion
		_process_pointer_move(_to_local_pointer_position(mouse_motion.position) if global_coordinates else mouse_motion.position)
		return true
	if event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		var pointer_position := _to_local_pointer_position(screen_touch.position) if global_coordinates else screen_touch.position
		if screen_touch.pressed:
			if not _mouse_held and _active_touch_index < 0 and _is_inside_target(pointer_position):
				_active_touch_index = screen_touch.index
				_last_feedback_frame = -1
				_set_pointer_sample(pointer_position)
				_begin_interaction()
				queue_redraw()
				return true
		elif screen_touch.index == _active_touch_index:
			_process_pointer_move(pointer_position)
			_stop_rubbing()
			return true
		return false
	if event is InputEventScreenDrag:
		var screen_drag := event as InputEventScreenDrag
		if screen_drag.index == _active_touch_index:
			_process_pointer_move(_to_local_pointer_position(screen_drag.position) if global_coordinates else screen_drag.position)
			return true
	return false


func _draw() -> void:
	_draw_approach_circle()
	_draw_note_circle(
		target_center,
		target_radius,
		Color(1.0, 0.87, 0.40, 1.0) if is_rubbing() else Color(1.0, 0.73, 0.22, 0.94)
	)


func _process_pointer_move(new_pos: Vector2) -> void:
	if _resolved or _suspended or not is_rubbing():
		return
	var hit_margin := mouse_hit_radius if _mouse_held else 0.0
	if not _has_pointer_sample:
		_set_pointer_sample(new_pos)
		return
	var previous_pos := _last_pointer_pos
	var movement := new_pos - previous_pos
	_last_pointer_pos = new_pos
	_pending_motion_distance += _distance_inside_target(previous_pos, new_pos, target_radius + hit_margin)
	if _pending_motion_distance < valid_motion_threshold:
		return
	var remaining_distance := maxf(required_scrub_distance - accumulated_scrub_distance, 0.0)
	# Both samples are inside a convex circle, so their entire connecting
	# segment is valid. A per-event cap discards movement on low frame rates.
	var credited_distance := minf(_pending_motion_distance, remaining_distance)
	_pending_motion_distance = 0.0
	if credited_distance <= 0.0:
		return
	accumulated_scrub_distance += credited_distance
	audio_motion_valid.emit()
	var frame := Engine.get_process_frames()
	if frame != _last_feedback_frame:
		_last_feedback_frame = frame
		visual_motion.emit(movement.normalized(), credited_distance / maxf(max_delta_per_event, 0.001))
	progressed.emit(credited_distance / maxf(required_scrub_distance, 0.001))
	queue_redraw()
	if fmod(accumulated_scrub_distance, 60.0) < credited_distance:
		_spawn_heart_particle()
	if accumulated_scrub_distance >= required_scrub_distance:
		_resolve_completed()


func _distance_inside_target(start: Vector2, end: Vector2, radius: float) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return 0.0
	var offset := start - target_center
	var projection := -offset.dot(segment) / length_squared
	var closest_distance_squared := (offset + segment * projection).length_squared()
	var radius_squared := radius * radius
	if closest_distance_squared >= radius_squared:
		return 0.0
	var half_span := sqrt((radius_squared - closest_distance_squared) / length_squared)
	var entry := maxf(0.0, projection - half_span)
	var exit := minf(1.0, projection + half_span)
	return maxf(exit - entry, 0.0) * sqrt(length_squared)


func _is_inside_target(position_to_test: Vector2, hit_margin: float = 0.0) -> bool:
	var hit_radius := target_radius + hit_margin
	return position_to_test.distance_squared_to(target_center) <= hit_radius * hit_radius


func _set_pointer_sample(position: Vector2) -> void:
	_has_pointer_sample = true
	_last_pointer_pos = position
	_pending_motion_distance = 0.0


func _clear_pointer_sample() -> void:
	_has_pointer_sample = false
	_last_pointer_pos = Vector2.ZERO
	_pending_motion_distance = 0.0


func _stop_rubbing() -> void:
	_mouse_held = false
	_active_touch_index = -1
	_clear_pointer_sample()
	_end_interaction()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_rubbing():
		_stop_rubbing()


func _spawn_heart_particle() -> void:
	var heart := TextureRect.new()
	heart.texture = HEART_TEXTURE
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.size = Vector2(54.0, 54.0)
	heart.pivot_offset = heart.size * 0.5
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heart.position = target_center - (heart.size * 0.5) + Vector2(
		randf_range(-target_radius * 0.5, target_radius * 0.5),
		-target_radius * 0.4
	)
	add_child(heart)
	var tween := heart.create_tween().set_parallel(true)
	tween.tween_property(heart, "position:y", heart.position.y - 40.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(heart, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(heart.queue_free)


func _get_approach_center() -> Vector2:
	return target_center


func _get_approach_target_radius() -> float:
	return target_radius


func _get_approach_color() -> Color:
	return Color(1.0, 0.72, 0.24, 0.98)


func _set_note_input_enabled(enabled: bool) -> void:
	if not enabled:
		_stop_rubbing()
	set_process_input(enabled)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _to_local_pointer_position(global_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_position


func _on_suspended() -> void:
	_stop_rubbing()


func _on_resumed() -> void:
	_stop_rubbing()
