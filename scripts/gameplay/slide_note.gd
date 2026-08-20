class_name SlideNote
extends InteractionNote

var checkpoint_radius: float = 40.0
var checkpoints: PackedVector2Array = PackedVector2Array()

var _next_checkpoint_index: int = 0
var _armed: bool = false
var _has_pointer_sample: bool = false
var _last_pointer_pos: Vector2 = Vector2.ZERO
var _pointer_was_inside_target: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	super._ready()


func setup(config: Dictionary) -> void:
	super.setup(config)
	checkpoint_radius = float(config.get("checkpoint_radius", 40.0))
	var configured_checkpoints: Variant = config.get("checkpoints", PackedVector2Array())
	if configured_checkpoints is PackedVector2Array:
		checkpoints = configured_checkpoints
	elif configured_checkpoints is Array:
		checkpoints = PackedVector2Array(configured_checkpoints)


func get_progress_ratio() -> float:
	var required_count := maxi(checkpoints.size() - 1, 1)
	var completed_count := maxi(_next_checkpoint_index - 1, 0) if _armed else 0
	return clampf(float(completed_count) / float(required_count), 0.0, 1.0)


func get_next_checkpoint_index() -> int:
	return _next_checkpoint_index


func is_armed() -> bool:
	return _armed


func _input(event: InputEvent) -> void:
	if _resolved or _suspended or not visible:
		return
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * mouse_motion.position
		_process_pointer_move(local_position)


func _draw() -> void:
	if checkpoints.is_empty():
		return

	for index in range(checkpoints.size() - 1):
		var segment_completed := _armed and index < _next_checkpoint_index - 1
		var line_color := Color(1.0, 0.55, 0.18, 0.95) if segment_completed else Color(1.0, 0.88, 0.42, 0.42)
		draw_line(checkpoints[index], checkpoints[index + 1], line_color, 6.0, true)

	var target_index := _get_target_index()
	for index in range(checkpoints.size()):
		var is_start := index == 0
		var is_completed := _armed if is_start else _armed and index < _next_checkpoint_index
		var is_current := index == target_index
		var fill_color := Color(0.28, 0.82, 0.46, 0.68) if is_completed else Color(1.0, 0.82, 0.16, 0.30)
		var outline_color := Color(0.55, 1.0, 0.7, 1.0) if is_completed else Color(1.0, 0.9, 0.4, 0.72)
		if is_current:
			fill_color = Color(1.0, 0.48, 0.1, 0.68)
			outline_color = Color(1.0, 1.0, 1.0, 1.0)
		draw_circle(checkpoints[index], checkpoint_radius, fill_color)
		draw_arc(checkpoints[index], checkpoint_radius, 0.0, TAU, 40, outline_color, 4.0, true)
		if is_start:
			draw_circle(checkpoints[index], checkpoint_radius * 0.28, outline_color)

	if target_index >= 0 and target_index < checkpoints.size() and lifetime_timer != null and not lifetime_timer.is_stopped():
		var lifetime_ratio := clampf(lifetime_timer.time_left / maxf(spot_lifetime, 0.001), 0.0, 1.0)
		draw_arc(
			checkpoints[target_index],
			checkpoint_radius + 8.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * lifetime_ratio,
			40,
			Color(1.0, 1.0, 1.0, 0.9),
			4.0,
			true
		)


func _process_pointer_move(new_pos: Vector2) -> void:
	if _resolved or _suspended or checkpoints.size() < 2:
		return
	if not _has_pointer_sample:
		_has_pointer_sample = true
		_last_pointer_pos = new_pos
		_pointer_was_inside_target = _is_inside_target(new_pos)
		return

	var previous_pos := _last_pointer_pos
	_last_pointer_pos = new_pos
	var target_index := _get_target_index()
	if target_index < 0 or target_index >= checkpoints.size():
		return

	var target := checkpoints[target_index]
	var intersects_target := _segment_intersects_circle(previous_pos, new_pos, target, checkpoint_radius)
	var valid_crossing := not _pointer_was_inside_target and intersects_target
	if valid_crossing:
		_activate_current_target()
		# The same motion event may never activate the newly selected target.
		_pointer_was_inside_target = _is_inside_target(new_pos)
		return

	_pointer_was_inside_target = new_pos.distance_squared_to(target) <= checkpoint_radius * checkpoint_radius


func _activate_current_target() -> void:
	_begin_interaction()
	if not _armed:
		_armed = true
		_next_checkpoint_index = 1
		queue_redraw()
		return

	if _next_checkpoint_index <= 0 or _next_checkpoint_index >= checkpoints.size():
		return
	_next_checkpoint_index += 1
	var required_count := checkpoints.size() - 1
	progressed.emit(1.0 / float(required_count))
	_spawn_note_particle(checkpoints[_next_checkpoint_index - 1])
	queue_redraw()
	if _next_checkpoint_index >= checkpoints.size():
		_resolve_completed()


func _get_target_index() -> int:
	if not _armed:
		return 0
	return _next_checkpoint_index


func _is_inside_target(position_to_test: Vector2) -> bool:
	var target_index := _get_target_index()
	if target_index < 0 or target_index >= checkpoints.size():
		return false
	return position_to_test.distance_squared_to(checkpoints[target_index]) <= checkpoint_radius * checkpoint_radius


func _segment_intersects_circle(
	segment_start: Vector2,
	segment_end: Vector2,
	circle_center: Vector2,
	circle_radius: float
) -> bool:
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0001:
		return segment_start.distance_squared_to(circle_center) <= circle_radius * circle_radius
	var projection := clampf((circle_center - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
	var closest_point := segment_start + segment * projection
	return closest_point.distance_squared_to(circle_center) <= circle_radius * circle_radius


func _set_note_input_enabled(enabled: bool) -> void:
	set_process_input(enabled)


func _on_suspended() -> void:
	_clear_pointer_sample()


func _on_resumed() -> void:
	_clear_pointer_sample()


func _clear_pointer_sample() -> void:
	_has_pointer_sample = false
	_last_pointer_pos = Vector2.ZERO
	_pointer_was_inside_target = false


func _spawn_note_particle(origin: Vector2) -> void:
	var note := Label.new()
	note.text = "♪"
	note.add_theme_font_size_override("font_size", 22)
	note.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4, 1.0))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.position = origin + Vector2(randf_range(-12.0, 12.0), -checkpoint_radius * 0.5)
	add_child(note)

	var tween := note.create_tween().set_parallel(true)
	tween.tween_property(note, "position:y", note.position.y - 40.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(note.queue_free)
