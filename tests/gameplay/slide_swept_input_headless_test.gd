extends SceneTree

const SLIDE_SCENE := preload("res://scenes/components/SlideNote.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func _motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make_slide(points: PackedVector2Array, radius: float = 20.0) -> SlideNote:
	var slide := SLIDE_SCENE.instantiate() as SlideNote
	slide.setup({"checkpoints": points, "checkpoint_radius": radius, "spot_lifetime": 30.0})
	root.add_child(slide)
	return slide


func _run() -> void:
	var points := PackedVector2Array([
		Vector2(100, 100), Vector2(200, 100), Vector2(300, 100), Vector2(400, 100)
	])
	var slide := _make_slide(points)
	var counts := {"progress": 0, "audio": 0, "completed": 0}
	slide.progressed.connect(func(_delta: float) -> void: counts.progress += 1)
	slide.audio_note_reached.connect(func() -> void: counts.audio += 1)
	slide.completed.connect(func() -> void: counts.completed += 1)
	slide._input(_button(points[0], true))
	slide._input(_motion(Vector2(450, 100)))
	_check(slide._resolved and counts.progress == 3 and counts.audio == 4 and counts.completed == 1,
		"A single low-frequency motion did not register all three ordered swept crossings.")
	slide.queue_free()
	await process_frame

	var reverse := _make_slide(points)
	reverse._input(_button(points[0], true))
	reverse._input(_motion(Vector2(350, 100)))
	_check(reverse.get_next_checkpoint_index() == 3, "Forward drag missed the first two checkpoints.")
	reverse._input(_motion(Vector2(100, 100)))
	_check(reverse.get_next_checkpoint_index() == 3, "Reverse drag incorrectly reached the final checkpoint.")
	reverse._input(_motion(Vector2(450, 100)))
	_check(reverse._resolved, "Forward drag after reversal missed the final checkpoint.")
	reverse.queue_free()
	await process_frame

	var out_of_order := _make_slide(PackedVector2Array([
		Vector2(100, 100), Vector2(300, 100), Vector2(200, 100), Vector2(400, 100)
	]))
	out_of_order._input(_button(Vector2(100, 100), true))
	out_of_order._input(_motion(Vector2(350, 100)))
	_check(out_of_order.get_next_checkpoint_index() == 2,
		"A checkpoint crossed before its predecessor was registered retroactively.")
	out_of_order._input(_motion(Vector2(150, 100)))
	_check(out_of_order.get_next_checkpoint_index() == 3, "Reverse crossing missed the now-current checkpoint.")
	out_of_order.queue_free()
	await process_frame

	var scaled := _make_slide(points)
	scaled.position = Vector2(430, 210)
	scaled.scale = Vector2(1.5, 0.75)
	scaled.rotation = 0.2
	var transform := scaled.get_global_transform_with_canvas()
	scaled._input(_button(transform * points[0], true))
	scaled._input(_motion(transform * Vector2(450, 100)))
	_check(scaled._resolved, "Transformed Control visual checkpoints did not match hit regions.")
	scaled.queue_free()
	await process_frame

	# A fast corner can pass through a checkpoint while the frame's endpoint chord misses it.
	var original_accumulation := Input.use_accumulated_input
	Input.use_accumulated_input = true
	var curved := _make_slide(PackedVector2Array([
		Vector2(100, 100), Vector2(200, 100), Vector2(300, 100)
	]))
	var concurrent := _make_slide(points)
	_check(not Input.use_accumulated_input, "Slide did not preserve raw mouse motion events.")
	curved._input(_button(Vector2(100, 100), true))
	curved._input(_motion(Vector2(200, 100)))
	curved._input(_motion(Vector2(100, 200)))
	_check(curved.get_next_checkpoint_index() == 2,
		"A checkpoint on a fast curved path was missed despite raw motion samples.")
	curved.queue_free()
	await process_frame
	_check(not Input.use_accumulated_input, "Removing one Slide restored accumulation while another remained.")
	concurrent.queue_free()
	await process_frame
	_check(Input.use_accumulated_input, "Removing the final Slide did not restore input accumulation.")
	Input.use_accumulated_input = original_accumulation

	if _failures.is_empty():
		print("Slide swept input tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
