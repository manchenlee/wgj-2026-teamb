class_name SlideNote
extends InteractionNote

const CursorHitAreaClass := preload("res://scripts/gameplay/cursor_hit_area.gd")
const HEART_TEXTURE := preload("res://assets/art/ui/gameplay/img_heart.png")
const NOTE_LABEL_FONT := preload("res://assets/fonts/ShipporiMincho-Bold.ttf")
const SLIDE_COLOR := Color("#85CCFFE0")
const SLIDE_COMPLETED_COLOR := Color("#85CCFFF5")

static var _precision_input_users: int = 0
static var _previous_accumulated_input: bool = true

var checkpoint_radius: float = 40.0
var checkpoints: PackedVector2Array = PackedVector2Array()
var mouse_hit_radius: float = CursorHitAreaClass.NOTE_HIT_MARGIN

var _next_checkpoint_index: int = 0
var _armed: bool = false
var _has_pointer_sample: bool = false
var _last_pointer_pos: Vector2 = Vector2.ZERO
var _pointer_was_inside_target: bool = false
var _mouse_held: bool = false
var _active_touch_index: int = -1


func _ready() -> void:
	if _precision_input_users == 0:
		_previous_accumulated_input = Input.use_accumulated_input
		Input.use_accumulated_input = false
	_precision_input_users += 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	super._ready()


func _exit_tree() -> void:
	_precision_input_users -= 1
	if _precision_input_users == 0:
		Input.use_accumulated_input = _previous_accumulated_input


func setup(config: Dictionary) -> void:
	super.setup(config)
	checkpoint_radius = float(config.get("checkpoint_radius", 40.0))
	mouse_hit_radius = float(config.get("mouse_hit_radius", CursorHitAreaClass.NOTE_HIT_MARGIN))
	var configured_checkpoints: Variant = config.get("checkpoints", PackedVector2Array())
	if configured_checkpoints is PackedVector2Array:
		checkpoints = configured_checkpoints
	elif configured_checkpoints is Array:
		checkpoints = PackedVector2Array(configured_checkpoints)
	queue_redraw()


func get_progress_ratio() -> float:
	var required_count := maxi(checkpoints.size() - 1, 1)
	var completed_count := maxi(_next_checkpoint_index - 1, 0) if _armed else 0
	return clampf(float(completed_count) / float(required_count), 0.0, 1.0)


func get_next_checkpoint_index() -> int:
	return _next_checkpoint_index


func is_armed() -> bool:
	return _armed


func is_dragging() -> bool:
	return _mouse_held or _active_touch_index >= 0


func _input(event: InputEvent) -> void:
	if _resolved or _suspended or not visible:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		var local_position := _to_local_pointer_position(mouse_button.position)
		if mouse_button.pressed:
			if _active_touch_index < 0:
				_start_drag(local_position, -1)
		else:
			if _mouse_held:
				_stop_dragging()
		return
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		var local_position := _to_local_pointer_position(mouse_motion.position)
		if _mouse_held:
			_process_pointer_move(local_position)
		return
	if event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		var local_position := _to_local_pointer_position(screen_touch.position)
		if screen_touch.pressed:
			if not _mouse_held and _active_touch_index < 0:
				_start_drag(local_position, screen_touch.index)
		elif screen_touch.index == _active_touch_index:
			_stop_dragging()
		return
	if event is InputEventScreenDrag:
		var screen_drag := event as InputEventScreenDrag
		if screen_drag.index == _active_touch_index:
			_process_pointer_move(_to_local_pointer_position(screen_drag.position))


func _draw() -> void:
	if checkpoints.is_empty():
		return

	_draw_approach_circle()

	for index in range(checkpoints.size() - 1):
		var segment_completed := _armed and index < _next_checkpoint_index - 1
		var line_color := SLIDE_COMPLETED_COLOR if segment_completed else Color("#85CCFFB8")
		draw_line(checkpoints[index], checkpoints[index + 1], line_color, checkpoint_radius * 2.0, true)

	var target_index := _get_target_index()
	for index in range(checkpoints.size()):
		var is_completed := _armed if index == 0 else _armed and index < _next_checkpoint_index
		var is_current := index == target_index
		var fill_color := SLIDE_COMPLETED_COLOR if is_completed else SLIDE_COLOR
		if is_current:
			fill_color = SLIDE_COMPLETED_COLOR
		_draw_note_circle(checkpoints[index], checkpoint_radius, fill_color)
		var font_size := maxi(16, int(round(checkpoint_radius * 0.58)))
		var label_size := NOTE_LABEL_FONT.get_string_size(
			"slide", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
		)
		draw_string(
			NOTE_LABEL_FONT,
			checkpoints[index] + Vector2(-label_size.x * 0.5, label_size.y * 0.34),
			"slide",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			Color.WHITE
		)

func _process_pointer_move(new_pos: Vector2) -> void:
	if _resolved or _suspended or not is_dragging() or checkpoints.size() < 2:
		return
	var hit_margin := mouse_hit_radius if _mouse_held else 0.0
	if not _has_pointer_sample:
		_has_pointer_sample = true
		_last_pointer_pos = new_pos
		_pointer_was_inside_target = _is_inside_target(new_pos, hit_margin)
		return

	var previous_pos := _last_pointer_pos
	_last_pointer_pos = new_pos
	# A newly selected checkpoint can already contain the pointer when hit
	# areas overlap. Count that checkpoint on the next drag sample instead of
	# waiting for the pointer to leave and enter it again.
	if _pointer_was_inside_target:
		_activate_current_target()
		_pointer_was_inside_target = false
	var last_crossing_fraction := -1.0
	while not _resolved:
		var target_index := _get_target_index()
		if target_index < 0 or target_index >= checkpoints.size():
			break
		var crossing_fraction := _segment_circle_entry_fraction(
			previous_pos, new_pos, checkpoints[target_index], checkpoint_radius + hit_margin
		)
		if _pointer_was_inside_target or crossing_fraction < 0.0 \
				or crossing_fraction < last_crossing_fraction:
			break
		last_crossing_fraction = crossing_fraction
		_activate_current_target()
		# The next target must be entered after this one on the same motion segment.
		_pointer_was_inside_target = false
	_pointer_was_inside_target = _is_inside_target(new_pos, hit_margin)


func _activate_current_target() -> void:
	_begin_interaction()
	if not _armed:
		_armed = true
		_next_checkpoint_index = 1
		audio_note_reached.emit()
		_restart_lifetime()
		queue_redraw()
		return

	if _next_checkpoint_index <= 0 or _next_checkpoint_index >= checkpoints.size():
		return
	_next_checkpoint_index += 1
	audio_note_reached.emit()
	var segment_direction := (checkpoints[_next_checkpoint_index - 1] - checkpoints[_next_checkpoint_index - 2]).normalized()
	visual_motion.emit(segment_direction, 1.0)
	var required_count := checkpoints.size() - 1
	progressed.emit(1.0 / float(required_count))
	_spawn_heart_particle(checkpoints[_next_checkpoint_index - 1])
	queue_redraw()
	if _next_checkpoint_index >= checkpoints.size():
		_resolve_completed()
	else:
		_restart_lifetime()


func _get_target_index() -> int:
	if not _armed:
		return 0
	return _next_checkpoint_index


func _get_approach_center() -> Vector2:
	var target_index := _get_target_index()
	if target_index < 0 or target_index >= checkpoints.size():
		return Vector2.ZERO
	return checkpoints[target_index]


func _get_approach_target_radius() -> float:
	return checkpoint_radius


func _get_approach_color() -> Color:
	return SLIDE_COMPLETED_COLOR


func _is_inside_target(position_to_test: Vector2, hit_margin: float = 0.0) -> bool:
	var target_index := _get_target_index()
	if target_index < 0 or target_index >= checkpoints.size():
		return false
	var hit_radius := checkpoint_radius + hit_margin
	return position_to_test.distance_squared_to(checkpoints[target_index]) <= hit_radius * hit_radius


func _segment_circle_entry_fraction(
	segment_start: Vector2,
	segment_end: Vector2,
	circle_center: Vector2,
	circle_radius: float
) -> float:
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	var offset := segment_start - circle_center
	if offset.length_squared() <= circle_radius * circle_radius:
		return 0.0
	if segment_length_squared <= 0.0001:
		return -1.0
	var projection := -offset.dot(segment) / segment_length_squared
	var closest_distance_squared := (offset + segment * projection).length_squared()
	var radius_squared := circle_radius * circle_radius
	if closest_distance_squared > radius_squared:
		return -1.0
	var half_span := sqrt((radius_squared - closest_distance_squared) / segment_length_squared)
	var entry_fraction := projection - half_span
	return entry_fraction if entry_fraction >= 0.0 and entry_fraction <= 1.0 else -1.0


func _set_note_input_enabled(enabled: bool) -> void:
	if not enabled:
		_stop_dragging()
	set_process_input(enabled)


func _on_suspended() -> void:
	_stop_dragging()


func _on_resumed() -> void:
	_stop_dragging()


func _start_drag(local_position: Vector2, touch_index: int) -> void:
	var hit_margin := mouse_hit_radius if touch_index < 0 else 0.0
	if is_dragging() or checkpoints.is_empty() or not _is_inside_drag_start(local_position, hit_margin):
		return
	_mouse_held = touch_index < 0
	_active_touch_index = touch_index
	_has_pointer_sample = true
	_last_pointer_pos = local_position
	_pointer_was_inside_target = _is_inside_target(local_position, hit_margin)
	_begin_interaction()
	if not _armed:
		_activate_current_target()
		_pointer_was_inside_target = _is_inside_target(local_position, hit_margin)
	elif _pointer_was_inside_target:
		# Pressing the next unvisited checkpoint resumes at that checkpoint.
		_activate_current_target()
		_pointer_was_inside_target = _is_inside_target(local_position, hit_margin)


func _stop_dragging() -> void:
	_mouse_held = false
	_active_touch_index = -1
	_clear_pointer_sample()
	_end_interaction()


func _is_inside_drag_start(position_to_test: Vector2, hit_margin: float = 0.0) -> bool:
	var hit_radius := checkpoint_radius + hit_margin
	if not _armed:
		return position_to_test.distance_squared_to(checkpoints[0]) <= hit_radius * hit_radius
	if _next_checkpoint_index <= 0 or _next_checkpoint_index >= checkpoints.size():
		return false
	# A released drag can resume anywhere on the unfinished segment.
	var segment_start := checkpoints[_next_checkpoint_index - 1]
	var segment_end := checkpoints[_next_checkpoint_index]
	var segment := segment_end - segment_start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0001:
		return position_to_test.distance_squared_to(segment_start) <= hit_radius * hit_radius
	var projection := clampf((position_to_test - segment_start).dot(segment) / segment_length_squared, 0.0, 1.0)
	var closest_point := segment_start + segment * projection
	return position_to_test.distance_squared_to(closest_point) <= hit_radius * hit_radius


func _to_local_pointer_position(global_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * global_position


func _clear_pointer_sample() -> void:
	_has_pointer_sample = false
	_last_pointer_pos = Vector2.ZERO
	_pointer_was_inside_target = false


func _spawn_heart_particle(origin: Vector2) -> void:
	var heart := TextureRect.new()
	heart.texture = HEART_TEXTURE
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.size = Vector2(48.0, 48.0)
	heart.pivot_offset = heart.size * 0.5
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heart.position = origin - (heart.size * 0.5) + Vector2(randf_range(-12.0, 12.0), -checkpoint_radius * 0.5)
	add_child(heart)

	var tween := heart.create_tween().set_parallel(true)
	tween.tween_property(heart, "position:y", heart.position.y - 40.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(heart, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(heart.queue_free)
