class_name RubNote
extends InteractionNote

var required_scrub_distance: float = 600.0
var valid_motion_threshold: float = 3.0
var max_delta_per_event: float = 24.0
var target_center: Vector2 = Vector2(212.0, 212.0)
var target_radius: float = 104.0
var accumulated_scrub_distance: float = 0.0

var _mouse_held: bool = false
var _active_touch_index: int = -1
var _has_pointer_sample: bool = false
var _last_pointer_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	super._ready()


func setup(config: Dictionary) -> void:
	super.setup(config)
	required_scrub_distance = float(config.get("required_scrub_distance", 600.0))
	valid_motion_threshold = float(config.get("valid_motion_threshold", 3.0))
	max_delta_per_event = float(config.get("max_delta_per_event", 24.0))
	target_center = config.get("target_center", Vector2(212.0, 212.0)) as Vector2
	target_radius = float(config.get("target_radius", 104.0))


func get_progress_ratio() -> float:
	return clampf(accumulated_scrub_distance / maxf(required_scrub_distance, 0.001), 0.0, 1.0)


func is_rubbing() -> bool:
	return _mouse_held or _active_touch_index >= 0


func _gui_input(event: InputEvent) -> void:
	if _resolved or _suspended or not visible:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			if _active_touch_index < 0 and _is_inside_target(mouse_button.position):
				_mouse_held = true
				_set_pointer_sample(mouse_button.position)
				_begin_interaction()
				accept_event()
		elif _mouse_held:
			_stop_rubbing()
			accept_event()
		return
	if event is InputEventMouseMotion and _mouse_held:
		var mouse_motion := event as InputEventMouseMotion
		_process_pointer_move(mouse_motion.position)
		accept_event()
		return
	if event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		if screen_touch.pressed:
			if not _mouse_held and _active_touch_index < 0 and _is_inside_target(screen_touch.position):
				_active_touch_index = screen_touch.index
				_set_pointer_sample(screen_touch.position)
				_begin_interaction()
				accept_event()
		elif screen_touch.index == _active_touch_index:
			_stop_rubbing()
			accept_event()
		return
	if event is InputEventScreenDrag:
		var screen_drag := event as InputEventScreenDrag
		if screen_drag.index == _active_touch_index:
			_process_pointer_move(screen_drag.position)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _mouse_held:
		_clear_pointer_sample()


func _draw() -> void:
	var progress := get_progress_ratio()
	var target_scale := lerpf(1.0, 0.72, progress)
	var draw_radius := target_radius * target_scale
	var target_color := Color(
		lerpf(1.0, 0.9, progress),
		lerpf(0.85, 0.25, progress),
		lerpf(0.1, 0.05, progress),
		lerpf(1.0, 0.75, progress)
	)
	draw_circle(
		target_center,
		draw_radius,
		Color(target_color.r, target_color.g, target_color.b, target_color.a * 0.55)
	)
	draw_arc(target_center, draw_radius, 0.0, TAU, 48, target_color, 3.0, true)
	_draw_approach_circle()


func _process_pointer_move(new_pos: Vector2) -> void:
	if _resolved or _suspended or not is_rubbing():
		return
	if not _is_inside_target(new_pos):
		_clear_pointer_sample()
		return
	if not _has_pointer_sample:
		_set_pointer_sample(new_pos)
		return
	if not _is_inside_target(_last_pointer_pos):
		_set_pointer_sample(new_pos)
		return

	var raw_distance := new_pos.distance_to(_last_pointer_pos)
	_last_pointer_pos = new_pos
	if raw_distance < valid_motion_threshold:
		return
	var remaining_distance := maxf(required_scrub_distance - accumulated_scrub_distance, 0.0)
	var credited_distance := minf(minf(raw_distance, max_delta_per_event), remaining_distance)
	if credited_distance <= 0.0:
		return
	accumulated_scrub_distance += credited_distance
	progressed.emit(credited_distance / maxf(required_scrub_distance, 0.001))
	queue_redraw()
	if fmod(accumulated_scrub_distance, 60.0) < credited_distance:
		_spawn_heart_particle()
	if accumulated_scrub_distance >= required_scrub_distance:
		_resolve_completed()


func _is_inside_target(position_to_test: Vector2) -> bool:
	return position_to_test.distance_squared_to(target_center) <= target_radius * target_radius


func _set_pointer_sample(position: Vector2) -> void:
	_has_pointer_sample = true
	_last_pointer_pos = position


func _clear_pointer_sample() -> void:
	_has_pointer_sample = false
	_last_pointer_pos = Vector2.ZERO


func _stop_rubbing() -> void:
	_mouse_held = false
	_active_touch_index = -1
	_clear_pointer_sample()
	_end_interaction()


func _spawn_heart_particle() -> void:
	var heart := Label.new()
	heart.text = "♥"
	heart.add_theme_font_size_override("font_size", 22)
	heart.add_theme_color_override("font_color", Color(1.0, 0.32, 0.48, 1.0))
	heart.add_theme_color_override("font_outline_color", Color(1.0, 0.82, 0.88, 0.9))
	heart.add_theme_constant_override("outline_size", 3)
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heart.position = target_center + Vector2(
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


func _set_note_input_enabled(enabled: bool) -> void:
	if not enabled:
		_stop_rubbing()
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _on_suspended() -> void:
	_stop_rubbing()


func _on_resumed() -> void:
	_stop_rubbing()
