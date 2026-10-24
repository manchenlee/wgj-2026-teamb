extends SceneTree

const GAME_SCREEN := preload("res://scenes/screens/GameScreen.tscn")
const CLICK_NOTE := preload("res://scenes/components/ClickNote.tscn")
const SLIDE_NOTE := preload("res://scenes/components/SlideNote.tscn")
const RUB_NOTE := preload("res://scenes/components/RubNote.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = GAME_SCREEN.instantiate()
	root.add_child(game)
	await process_frame
	var presenter: CharacterPresenter = game.character_area
	var art: Control = game.background_anchor
	var mask: Control = game.interaction_mask_anchor
	var prompt: Control = presenter.prompt_layer
	var manager: InteractionSpotManager = game.spot_manager
	var anchor := Control.new()
	anchor.position = Vector2(300.0, 240.0)
	prompt.add_child(anchor)
	var rest := art.position
	var mask_position := mask.global_position
	var prompt_position := prompt.global_position
	var anchor_position := anchor.global_position
	var alignment_position: Vector2 = game.character_alignment_root.position

	var click := CLICK_NOTE.instantiate() as ClickNote
	click.setup({"spot_lifetime": 30.0, "target_center": Vector2(84, 84), "target_radius": 40.0})
	prompt.add_child(click)
	click.visual_motion.connect(manager._on_spot_visual_motion.bind(click))
	click._gui_input(_mouse_button(Vector2(104, 84), true))
	presenter._process(0.025)
	_check(art.position.x > rest.x + 0.2, "Click did not jolt in the press direction.")
	await create_timer(0.18).timeout
	_check(art.position.distance_to(rest) < 0.05, "Click did not settle.")
	var centered_click := CLICK_NOTE.instantiate() as ClickNote
	centered_click.setup({"spot_lifetime": 30.0, "target_center": Vector2(84, 84), "target_radius": 40.0})
	prompt.add_child(centered_click)
	centered_click.visual_motion.connect(manager._on_spot_visual_motion.bind(centered_click))
	centered_click._gui_input(_mouse_button(Vector2(84, 84), true))
	_check(presenter._motion_direction.is_equal_approx(Vector2.RIGHT), "Centered Click lacked a deterministic direction.")
	presenter.clear_body_motion()

	var slide := SLIDE_NOTE.instantiate() as SlideNote
	slide.setup({"spot_lifetime": 30.0, "checkpoint_radius": 40.0,
		"checkpoints": PackedVector2Array([Vector2(100, 100), Vector2(220, 100), Vector2(220, 220), Vector2(100, 220)])})
	prompt.add_child(slide)
	slide.visual_motion.connect(manager._on_spot_visual_motion.bind(slide))
	slide._start_drag(Vector2(100, 100), -1)
	slide._process_pointer_move(Vector2(160, 100))
	slide._process_pointer_move(Vector2(220, 100))
	await create_timer(0.08).timeout
	_check(art.position.x > rest.x, "Slide did not sway along its first segment.")
	var offset_before: Vector2 = presenter._motion_offset
	slide._process_pointer_move(Vector2(220, 160))
	slide._process_pointer_move(Vector2(220, 220))
	_check(presenter._slide_remaining < 0.24 and presenter._motion_offset.is_equal_approx(offset_before), "Slide retarget restarted or jumped.")
	await create_timer(0.08).timeout
	_check(art.position.y > rest.y, "Slide did not follow its second segment.")
	slide._stop_dragging()
	await create_timer(0.30).timeout
	_check(art.position.distance_to(rest) < 0.1, "Slide did not settle after release.")
	slide.set_meta("note_type", InteractionSpotManager.NoteType.SLIDE)
	slide.completed.connect(manager._on_spot_completed.bind(slide))
	slide.force_complete()
	_check(presenter._motion_kind == "accent", "Slide completion accent was missing.")

	var rub := RUB_NOTE.instantiate() as RubNote
	rub.setup({"spot_lifetime": 30.0, "target_center": Vector2(108, 108), "target_radius": 52.0,
		"required_scrub_distance": 600.0, "valid_motion_threshold": 3.0, "max_delta_per_event": 24.0})
	prompt.add_child(rub)
	rub.visual_motion.connect(manager._on_spot_visual_motion.bind(rub))
	rub.interaction_ended.connect(manager._on_spot_scrub_ended.bind(rub))
	rub._gui_input(_mouse_button(Vector2(108, 108), true))
	await create_timer(0.04).timeout
	_check(presenter._rub_intensity < 0.01, "Holding Rub activated tremor without motion.")
	rub._process_pointer_move(Vector2(128, 108))
	await create_timer(0.05).timeout
	_check(presenter._rub_intensity > 0.1, "Valid Rub movement did not activate tremor.")
	await create_timer(0.25).timeout
	_check(presenter._rub_intensity < 0.15, "Idle Rub motion did not decay.")
	rub._process_pointer_move(Vector2(108, 108))
	rub._gui_input(_mouse_button(Vector2(108, 108), false))
	_check(not presenter._rub_active, "Rub release left tremor active.")
	await create_timer(0.20).timeout
	_check(presenter._rub_intensity < 0.05, "Rub release did not fade out.")
	rub.set_meta("note_type", InteractionSpotManager.NoteType.RUB)
	rub.completed.connect(manager._on_spot_completed.bind(rub))
	rub.force_complete()
	_check(presenter._motion_kind == "accent", "Rub completion accent was missing.")

	var slide_failure := SLIDE_NOTE.instantiate() as SlideNote
	slide_failure.setup({"spot_lifetime": 30.0, "checkpoint_radius": 40.0,
		"checkpoints": PackedVector2Array([Vector2(100, 100), Vector2(220, 100), Vector2(220, 220)])})
	prompt.add_child(slide_failure)
	slide_failure.expired.connect(manager._on_spot_expired.bind(slide_failure))
	slide_failure._start_drag(Vector2(100, 100), -1)
	slide_failure._process_pointer_move(Vector2(160, 100))
	slide_failure._process_pointer_move(Vector2(220, 100))
	slide_failure.force_expire()
	_check(presenter._motion_kind == "failure", "Partial Slide failure lacked a kick.")
	var rub_failure := RUB_NOTE.instantiate() as RubNote
	rub_failure.setup({"spot_lifetime": 30.0, "target_center": Vector2(108, 108), "target_radius": 52.0,
		"required_scrub_distance": 600.0, "valid_motion_threshold": 3.0, "max_delta_per_event": 24.0})
	prompt.add_child(rub_failure)
	rub_failure.expired.connect(manager._on_spot_expired.bind(rub_failure))
	rub_failure._gui_input(_mouse_button(Vector2(108, 108), true))
	rub_failure._process_pointer_move(Vector2(128, 108))
	rub_failure.force_expire()
	_check(presenter._motion_direction.y > 0.0, "Rub failure direction was not distinct.")
	presenter.clear_body_motion()
	var untouched := CLICK_NOTE.instantiate() as ClickNote
	untouched.setup({"spot_lifetime": 30.0})
	prompt.add_child(untouched)
	untouched.expired.connect(manager._on_spot_expired.bind(untouched))
	untouched.force_expire()
	_check(presenter._motion_kind == "" and art.position.is_equal_approx(rest), "Untouched timeout produced tremble.")
	presenter.update_rub_tremor(1, 1.0)
	presenter.update_rub_tremor(2, 1.0)
	presenter.show_body_outcome(&"rub", true, Vector2.RIGHT, 1)
	_check(presenter._rub_active and presenter._rub_owner == 2, "One Rub outcome stopped another active Rub.")
	for i in range(8):
		presenter.show_slide_sway(Vector2.RIGHT if i % 2 == 0 else Vector2.DOWN)
		presenter.update_rub_tremor(123, 1.0)
		await process_frame
		_check(art.position.distance_to(rest) <= 3.55, "Overlapping events exceeded motion cap.")
		game._apply_character_alignment()
		_check(game.character_alignment_root.position.is_equal_approx(alignment_position), "Alignment absorbed visual offset.")
		_check(mask.global_position.is_equal_approx(mask_position), "Tremble moved mask.")
		_check(prompt.global_position.is_equal_approx(prompt_position), "Tremble moved prompt layer.")
		_check(anchor.global_position.is_equal_approx(anchor_position), "Tremble moved note anchor.")
	manager.resume()
	manager.suspend()
	_check(art.position.is_equal_approx(rest), "Suspension did not clear motion.")
	presenter.show_click_jolt(Vector2.RIGHT)
	manager.stop()
	_check(art.position.is_equal_approx(rest), "Stop did not clear motion.")
	presenter.show_click_jolt(Vector2.RIGHT)
	manager.start()
	_check(art.position.is_equal_approx(rest), "Restart did not clear motion.")
	presenter.show_click_jolt(Vector2.RIGHT)
	game.reset_run()
	_check(art.position.is_equal_approx(rest), "Gameplay reset did not clear motion.")
	manager.stop()
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Character presentation feedback headless test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
