extends SceneTree

const SLIDE_SCENE := preload("res://scenes/components/SlideNote.tscn")
const RUB_SCENE := preload("res://scenes/components/RubNote.tscn")
const SPOT_MANAGER_SCRIPT := preload("res://scripts/gameplay/interaction_spot_manager.gd")

var _failures: Array[String] = []


class FakeAnchorRegion:
	extends Control

	func get_interaction_spot_global_rect(_anchor_id: StringName, _fallback_center: Vector2) -> Rect2:
		return Rect2(Vector2(150.0, 150.0), Vector2(650.0, 650.0))


func _initialize() -> void:
	call_deferred("_run")


func _button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event


func _motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	# Route events through the Viewport in the same frame as add_child().
	var slide := SLIDE_SCENE.instantiate() as SlideNote
	slide.setup({
		"checkpoints": PackedVector2Array([Vector2(100.0, 100.0), Vector2(200.0, 100.0)]),
		"checkpoint_radius": 40.0,
	})
	slide.size = Vector2(300.0, 200.0)
	slide.position = Vector2(400.0, 100.0)
	root.add_child(slide)
	var slide_audio := {"count": 0}
	slide.audio_note_reached.connect(func() -> void: slide_audio.count += 1)
	root.push_input(_button(Vector2(500.0, 200.0), true), true)
	_assert(slide.is_dragging() and slide.is_armed(), "Slide missed its first-frame mouse press.")
	root.push_input(_motion(Vector2(600.0, 200.0)), true)
	_assert(slide._resolved and slide.get_next_checkpoint_index() == 2, "Rapid first-frame Slide drag missed its checkpoint.")
	_assert(slide_audio.count == 2, "Rapid first-frame Slide drag changed checkpoint audio events.")
	root.push_input(_button(Vector2(600.0, 200.0), false), true)
	slide.queue_free()
	await process_frame

	# A held press from a preceding Click must not activate a newly spawned Slide.
	root.push_input(_button(Vector2(500.0, 200.0), true), true)
	var late_slide := SLIDE_SCENE.instantiate() as SlideNote
	late_slide.setup({
		"checkpoints": PackedVector2Array([
			Vector2(100.0, 100.0), Vector2(200.0, 100.0), Vector2(300.0, 100.0)
		]),
		"checkpoint_radius": 40.0,
	})
	late_slide.position = Vector2(400.0, 100.0)
	root.add_child(late_slide)
	var recovered_audio := {"count": 0}
	late_slide.audio_note_reached.connect(func() -> void: recovered_audio.count += 1)
	var held_motion := _motion(Vector2(750.0, 200.0))
	held_motion.relative = Vector2(250.0, 0.0)
	root.push_input(held_motion, true)
	_assert(not late_slide.is_armed() and recovered_audio.count == 0,
		"A pre-spawn Click press also activated the following Slide.")
	root.push_input(_button(Vector2(750.0, 200.0), false), true)
	root.push_input(_button(Vector2(500.0, 200.0), true), true)
	root.push_input(held_motion, true)
	_assert(late_slide._resolved and recovered_audio.count == 3,
		"Slide did not respond to a new press after it appeared.")
	root.push_input(_button(Vector2(750.0, 200.0), false), true)
	late_slide.queue_free()
	await process_frame

	var outside_slide := SLIDE_SCENE.instantiate() as SlideNote
	outside_slide.setup({
		"checkpoints": PackedVector2Array([Vector2(100.0, 100.0), Vector2(200.0, 100.0)]),
		"checkpoint_radius": 40.0,
	})
	outside_slide.position = Vector2(400.0, 100.0)
	root.add_child(outside_slide)
	root.push_input(_button(Vector2(420.0, 200.0), true), true)
	var outside_motion := _motion(Vector2(620.0, 200.0))
	outside_motion.relative = Vector2(200.0, 0.0)
	root.push_input(outside_motion, true)
	_assert(not outside_slide.is_armed(), "A visible press outside the start incorrectly armed Slide.")
	root.push_input(_button(Vector2(620.0, 200.0), false), true)
	outside_slide.queue_free()
	await process_frame

	# The cursor is already over the location where the Rub note appears.
	root.push_input(_motion(Vector2(508.0, 208.0)), true)
	var rub := RUB_SCENE.instantiate() as RubNote
	rub.setup({"target_center": Vector2(108.0, 108.0), "target_radius": 52.0})
	rub.custom_minimum_size = Vector2(216.0, 216.0)
	rub.size = Vector2(216.0, 216.0)
	rub.position = Vector2(400.0, 100.0)
	root.add_child(rub)
	var rub_audio := {"count": 0}
	rub.audio_motion_valid.connect(func() -> void: rub_audio.count += 1)
	root.push_input(_button(Vector2(508.0, 208.0), true), true)
	_assert(rub.is_rubbing() and rub._has_pointer_sample, "Rub missed a first-frame press under a stationary cursor.")
	root.push_input(_motion(Vector2(520.0, 208.0)), true)
	_assert(is_equal_approx(rub.accumulated_scrub_distance, 12.0), "Rapid first-frame Rub drag missed valid motion.")
	_assert(rub_audio.count == 1, "Rapid first-frame Rub drag changed audio motion events.")
	root.push_input(_button(Vector2(520.0, 208.0), false), true)
	_assert(not rub.is_rubbing(), "Rub remained active after mouse release.")
	rub.queue_free()
	await process_frame

	# A later Control claims GUI events while the note remains visible.
	var covered_rub := RUB_SCENE.instantiate() as RubNote
	covered_rub.setup({"target_center": Vector2(108.0, 108.0), "target_radius": 52.0})
	covered_rub.custom_minimum_size = Vector2(216.0, 216.0)
	covered_rub.size = Vector2(216.0, 216.0)
	covered_rub.position = Vector2(400.0, 100.0)
	root.add_child(covered_rub)
	var overlay := Control.new()
	overlay.position = Vector2(400.0, 100.0)
	overlay.size = Vector2(216.0, 216.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	root.push_input(_button(Vector2(508.0, 208.0), true), true)
	_assert(covered_rub.is_rubbing(), "Rub input was blocked by a later Control on its first frame.")
	root.push_input(_button(Vector2(508.0, 208.0), false), true)
	covered_rub.queue_free()
	overlay.queue_free()
	await process_frame

	# Verify that the manager's configured position and hit area are ready
	# synchronously when it attaches a production Rub note.
	var prompt_layer := Control.new()
	prompt_layer.size = Vector2(900.0, 900.0)
	var anchor_region := FakeAnchorRegion.new()
	var spawn_timer := Timer.new()
	root.add_child(prompt_layer)
	root.add_child(anchor_region)
	root.add_child(spawn_timer)
	var manager := SPOT_MANAGER_SCRIPT.new()
	manager._prompt_layer = prompt_layer
	manager._anchor_region = anchor_region
	manager._spawn_timer = spawn_timer
	manager._active = true
	manager.set_available_anchor_ids(["first_frame_anchor"])
	manager.set_bounds_rect(Rect2(Vector2.ZERO, prompt_layer.size))
	manager.force_spawn_rub_note()
	_assert(manager._active_spots.size() == 1, "Manager did not spawn the Rub note.")
	if manager._active_spots.size() == 1:
		var spawned_rub := manager._active_spots[0] as RubNote
		var center := spawned_rub.get_global_transform_with_canvas() * spawned_rub.target_center
		root.push_input(_button(center, true), true)
		_assert(spawned_rub.is_rubbing(), "Manager-spawned Rub missed the immediate press.")
		root.push_input(_motion(center + Vector2(12.0, 0.0)), true)
		_assert(spawned_rub.accumulated_scrub_distance > 0.0, "Manager-spawned Rub missed immediate drag motion.")
		root.push_input(_button(center + Vector2(12.0, 0.0), false), true)
	manager.stop()
	prompt_layer.queue_free()
	anchor_region.queue_free()
	spawn_timer.queue_free()

	if _failures.is_empty():
		print("First-frame Slide and Rub input tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
