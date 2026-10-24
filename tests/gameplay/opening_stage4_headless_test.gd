extends SceneTree

const OPENING_SCENE := preload("res://scenes/screens/OpeningScreen.tscn")
const MAIN_SCENE := preload("res://scenes/Main.tscn")
const Config := preload("res://scripts/gameplay/GameConfig.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_branches_and_tutorial_returns()
	await _test_skip_and_restart()
	if failures.is_empty():
		print("Stage 4 opening headless tests passed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _test_branches_and_tutorial_returns() -> void:
	var opening := OPENING_SCENE.instantiate()
	root.add_child(opening)
	await process_frame
	_advance_to(opening, "r37")
	_check(_choice_labels(opening) == ["Tutorial", "Safety-word setup"], "First branch choices are incorrect.")
	_press_choice(opening, 0)
	_check(_step_id(opening) == "r42", "First tutorial did not start.")
	opening._advance_script()
	await process_frame
	_check(_step_id(opening) == "r37" and _choice_labels(opening) == ["Tutorial", "Safety-word setup"], "First tutorial did not return to first branch.")
	_check(not opening.safe_word_completed, "Tutorial marked safety-word setup complete.")
	_press_choice(opening, 1)
	_advance_to(opening, "r56")
	var requests := [0]
	opening.safe_word_requested.connect(func() -> void: requests[0] += 1)
	opening._advance_script()
	opening._advance_script()
	_check(requests[0] == 1, "Safety-word action emitted more than once.")
	opening.queue_free()
	await process_frame

	var resumed := OPENING_SCENE.instantiate()
	resumed.start_step_id = "r58"
	resumed.safe_word_completed = true
	root.add_child(resumed)
	await process_frame
	_advance_to(resumed, "r37")
	_check(_choice_labels(resumed) == ["Tutorial", "Start Game"], "Second branch choices are incorrect.")
	_press_choice(resumed, 0)
	_check(_step_id(resumed) == "r42", "Second tutorial did not start.")
	resumed._advance_script()
	await process_frame
	_check(_step_id(resumed) == "r37" and _choice_labels(resumed) == ["Tutorial", "Start Game"], "Second tutorial did not return to second branch.")
	_check(resumed.safe_word_completed, "Tutorial lost completed safety-word state.")
	_press_choice(resumed, 1)
	_advance_to(resumed, "r66")
	var game_requests := [0]
	resumed.game_requested.connect(func() -> void: game_requests[0] += 1)
	resumed._advance_script()
	resumed._advance_script()
	_check(game_requests[0] == 1, "Start Game action emitted more than once.")
	resumed.queue_free()
	await process_frame
	var second_tutorial := OPENING_SCENE.instantiate()
	second_tutorial.start_step_id = "r37"
	second_tutorial.safe_word_completed = true
	root.add_child(second_tutorial)
	await process_frame
	_press_choice(second_tutorial, 0)
	second_tutorial._play_fade_in_effect(1.0, 0.0, 1.0)
	var skips := [0]
	second_tutorial.skip_pressed.connect(func() -> void: skips[0] += 1)
	second_tutorial._on_skip_pressed()
	second_tutorial._on_skip_pressed()
	second_tutorial._advance_script()
	_check(skips[0] == 1 and _step_id(second_tutorial) == "r42", "Skip during second tutorial emitted twice or advanced stale dialogue.")
	second_tutorial.queue_free()
	await process_frame

func _test_skip_and_restart() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	main._show_opening()
	await create_timer(0.65).timeout
	var opening = main.current_screen
	_advance_to(opening, "r37")
	_press_choice(opening, 0)
	opening._play_fade_in_effect(1.0, 0.0, 1.0)
	opening._on_skip_pressed()
	opening._on_skip_pressed()
	_check(main.current_screen_id == "safe_word", "Skip during first tutorial did not route to setup.")
	await create_timer(0.65).timeout
	_check(main.current_screen_id == "safe_word", "Duplicate Skip caused a second transition.")
	var setup = main.current_screen
	setup.safe_word_input.text = "測試安全詞"
	setup._on_continue_pressed()
	setup._on_continue_pressed()
	_check(main.safe_word_completed and main.current_safe_word == "測試安全詞", "Setup did not store completion and the chosen word.")
	await create_timer(0.65).timeout
	_check(main.current_screen_id == "opening" and _step_id(main.current_screen) == "r58", "Setup did not resume its dialogue.")
	opening = main.current_screen
	opening._play_fade_in_effect(1.0, 0.0, 1.0)
	opening._on_skip_pressed()
	opening._on_skip_pressed()
	_check(main.current_screen_id == "game", "Skip during post-setup dialogue did not enter gameplay.")
	await create_timer(0.65).timeout
	_check(main.current_screen.safe_word == "測試安全詞", "Skip did not preserve the chosen safety word.")
	main._show_ending("success")
	await create_timer(0.65).timeout
	main.current_screen.restart_pressed.emit()
	await create_timer(0.65).timeout
	_check(main.current_screen_id == "game" and main.current_screen.safe_word == "測試安全詞", "Restart did not preserve the completed setup.")
	main._show_title()
	await create_timer(0.65).timeout
	_check(not main.safe_word_completed and main.current_safe_word == Config.SAFE_WORD_DEFAULT, "Returning to title did not reset opening state.")
	main._show_opening()
	await create_timer(0.65).timeout
	_check(not main.current_screen.safe_word_completed, "New opening inherited completed setup.")
	main.current_screen._on_skip_pressed()
	await create_timer(0.65).timeout
	_check(main.current_screen_id == "safe_word", "Skip before setup after restart did not open setup.")
	main.current_screen._on_skip_pressed()
	await create_timer(0.65).timeout
	_check(main.current_safe_word == Config.SAFE_WORD_DEFAULT and main.safe_word_completed, "Setup Skip lost default safety-word fallback.")
	main.queue_free()
	await process_frame

func _advance_to(opening: Control, step_id: String) -> void:
	for index in range(60):
		if _step_id(opening) == step_id:
			return
		opening._advance_script()
	_check(false, "Opening did not reach %s." % step_id)

func _step_id(opening: Control) -> String:
	return str(opening._entries[opening._current_entry_index].id)

func _choice_labels(opening: Control) -> Array[String]:
	var labels: Array[String] = []
	for button in opening._choice_buttons.get_children():
		if not button.is_queued_for_deletion():
			labels.append((button.get_node("Label") as Label).text)
	return labels

func _press_choice(opening: Control, index: int) -> void:
	(opening._choice_buttons.get_child(index) as TextureButton).pressed.emit()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
