extends SceneTree

const OPENING_SCENE := preload("res://scenes/screens/OpeningScreen.tscn")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")
const CHOICE_SCENE := preload("res://scenes/components/ChoicePanel.tscn")
const CONTROLLER_SCRIPT := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const PHASE_CONFIG := preload("res://data/phases/phase_1_config.gd")
const MODEL_SCRIPT := preload("res://scripts/gameplay/arousal_model.gd")
const MAIN_SCENE := preload("res://scenes/Main.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("Workbook test: opening")
	await _test_opening_branches()
	print("Workbook test: choices")
	await _test_choices()
	print("Workbook test: endings")
	await _test_endings()
	print("Workbook test: screen flow")
	await _test_screen_flow()
	if failures.is_empty():
		print("Workbook dialogue headless tests passed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _test_opening_branches() -> void:
	var opening := OPENING_SCENE.instantiate()
	root.add_child(opening)
	await process_frame
	_check(opening._entries.size() == 53, "Opening step count is incorrect.")
	_check(opening.get_node_or_null("SafeArea/RootLayout/TopRow/ChapterLabel") == null, "Opening still shows a chapter heading.")
	_check(opening.get_node_or_null("SafeArea/RootLayout/DialogueBox/DialogueLayout/FooterRow") == null, "Opening still shows a footer or Next button.")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(100, 500)
	var before_click: int = opening._current_entry_index
	opening._input(click)
	_check(opening._current_entry_index == before_click + 1, "Click does not advance visual novel dialogue.")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	var before_enter: int = opening._current_entry_index
	opening._unhandled_input(enter)
	_check(opening._current_entry_index == before_enter + 1, "Enter does not advance visual novel dialogue.")
	for index in range(60):
		if opening._current_entry_index >= opening._find_step_index("r37"):
			break
		opening._advance_script()
	_check(opening._choice_buttons.get_child_count() == 3, "Opening does not present three branches.")
	(opening._choice_buttons.get_child(0) as TextureButton).pressed.emit()
	_check(opening._entries[opening._current_entry_index].id == "r42", "Tutorial choice does not route to its workbook branch.")
	opening._advance_script()
	_check(opening._entries[opening._current_entry_index].id == "r37", "Tutorial branch does not return to choices.")
	await process_frame
	(opening._choice_buttons.get_child(1) as TextureButton).pressed.emit()
	for index in range(20):
		if opening._entries[opening._current_entry_index].id == "r56":
			break
		opening._advance_script()
	var safe_word_requested := [false]
	opening.safe_word_requested.connect(func() -> void: safe_word_requested[0] = true)
	opening._advance_script()
	_check(safe_word_requested[0], "Safe-word branch does not open setup.")
	opening.queue_free()
	await process_frame
	var resumed := OPENING_SCENE.instantiate()
	resumed.start_step_id = "r58"
	root.add_child(resumed)
	await process_frame
	_check(resumed._entries[resumed._current_entry_index].id == "r58", "Opening does not resume after safe-word setup.")
	for index in range(10):
		if resumed._entries[resumed._current_entry_index].id == "r61":
			break
		resumed._advance_script()
	resumed._advance_script()
	_check(resumed._entries[resumed._current_entry_index].id == "r37", "Safe-word branch does not return to choices.")
	await process_frame
	(resumed._choice_buttons.get_child(2) as TextureButton).pressed.emit()
	for index in range(10):
		if resumed._entries[resumed._current_entry_index].id == "r66":
			break
		resumed._advance_script()
	var game_requested := [false]
	resumed.game_requested.connect(func() -> void: game_requested[0] = true)
	resumed._advance_script()
	_check(game_requested[0], "Direct-start branch does not enter gameplay.")
	resumed.queue_free()
	await process_frame

func _test_choices() -> void:
	var panel := CHOICE_SCENE.instantiate()
	root.add_child(panel)
	await process_frame
	var seen_orders := {}
	var selected_ids: Array[String] = []
	panel.choice_selected.connect(func(choice_id: String, _choice_text: String) -> void: selected_ids.append(choice_id))
	for index in range(30):
		panel.show_choices([{"id": "option_1", "text": "A"}, {"id": "option_2", "text": "B"}])
		await process_frame
		seen_orders[panel._choice_data[0].id] = true
		panel.emit_choice_by_index(0)
		_check(selected_ids[-1] == panel._choice_data[0].id, "Randomized top choice lost its semantic ID.")
	_check(seen_orders.size() == 2, "Choice positions did not vary across presentations.")
	panel.queue_free()
	await process_frame
	var controller = CONTROLLER_SCRIPT.new()
	controller.set_phase_config(PHASE_CONFIG.new())
	var source := JSON.parse_string(FileAccess.get_file_as_string("res://assets/dialogue/feedback.json")) as Dictionary
	for entry_variant in source.entries:
		var entry := entry_variant as Dictionary
		for choice_variant in entry.choice:
			var choice := choice_variant as Dictionary
			controller.current_entry = entry.duplicate(true)
			var model = MODEL_SCRIPT.new()
			var outcome := controller.apply_choice(choice.id, model)
			var expected_sign := 1 if choice.effect == "positive" else -1
			_check(signf(outcome.delta) == expected_sign, "Choice %s has wrong score effect." % entry.id)
			_check(outcome.reply == entry.response[choice.id][0], "Choice %s starts the wrong branch." % entry.id)
			for line_index in range(1, entry.response[choice.id].size()):
				var next_line := controller.next_event(40.0, 40.0)
				_check(next_line.text == entry.response[choice.id][line_index], "Choice %s skipped or reordered a response line." % entry.id)
			controller.reset()

func _test_endings() -> void:
	var ending_data := JSON.parse_string(FileAccess.get_file_as_string("res://assets/dialogue/endings.json")) as Dictionary
	for result_type in ["peak_depletion_failure", "physical_imbalance_failure", "emotional_imbalance_failure", "success"]:
		var ending := ENDING_SCENE.instantiate()
		ending.set_result(result_type)
		root.add_child(ending)
		await process_frame
		var steps := ending_data.entries[result_type].steps as Array
		_check(ending._novel_screen != null, "Ending %s did not use the visual novel view." % result_type)
		_check(ending._novel_screen.dialogue_label.get_parsed_text() == steps[0].text, "Ending %s started on the wrong line." % result_type)
		for index in range(steps.size()):
			ending._novel_screen._advance_script()
		await process_frame
		_check(ending._novel_screen == null, "Ending %s did not reach its final image." % result_type)
		ending.queue_free()
		await process_frame

func _test_screen_flow() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	main._show_opening()
	await create_timer(0.7).timeout
	_check(main.current_screen_id == "opening", "Router did not enter opening.")
	main._show_opening_safe_word()
	await create_timer(0.7).timeout
	_check(main.current_screen_id == "safe_word", "Router did not enter safe-word setup.")
	main._resume_opening_after_safe_word("測試")
	await create_timer(0.7).timeout
	_check(main.current_screen.start_step_id == "r58", "Router did not resume workbook opening.")
	main._show_game("測試")
	await create_timer(0.7).timeout
	_check(main.current_screen_id == "game", "Router did not enter gameplay.")
	main._show_ending("success")
	await create_timer(0.7).timeout
	_check(main.current_screen_id == "ending" and main.current_screen._novel_screen != null, "Router did not enter visual novel ending.")
	main.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
