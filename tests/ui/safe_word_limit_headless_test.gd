extends SceneTree

const SAFE_WORD_SCENE := preload("res://scenes/screens/SafeWordScreen.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var screen := SAFE_WORD_SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	var input: LineEdit = screen.safe_word_input
	var counter: Label = screen.character_counter
	var warning: Label = screen.limit_warning
	var panel: PanelContainer = screen.get_node("ModalCenter/PromptPanel")
	var panel_size := panel.size
	var input_position := input.global_position
	var button_position: Vector2 = screen.continue_button.global_position
	_check(counter.text == "2 / 10", "Initial counter is incorrect.")
	input.text = "1234567890"
	screen._on_safe_word_changed(input.text)
	_check(input.text == "1234567890" and not warning.visible, "Exactly ten characters should be valid.")
	input.text = "12345678901"
	screen._on_safe_word_changed(input.text)
	_check(input.text == "1234567890", "Typing beyond the limit was not truncated.")
	_check(counter.text == "10 / 10" and warning.visible, "Over-limit feedback is missing.")
	input.text = "貼上超過十個字的內容測試"
	screen._on_safe_word_changed(input.text)
	_check(input.text.length() == 10 and warning.visible, "Long pasted text was not limited.")
	await create_timer(1.6).timeout
	_check(not warning.visible, "Warning did not clear after 1.5 seconds.")
	_check(panel.size == panel_size and input.global_position == input_position and screen.continue_button.global_position == button_position, "Feedback shifted dialog layout.")
	screen._on_reset_pressed()
	_check(input.text.is_empty() and counter.text == "0 / 10", "Reset did not update the counter.")
	_check(not warning.visible, "Reset did not clear the warning.")
	screen.queue_free()
	if failures.is_empty():
		print("Safe word limit headless tests passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
