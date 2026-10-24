extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const OPENING_SCENE := preload("res://scenes/screens/OpeningScreen.tscn")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _check_game_layout()
	await _check_opening_and_ending_styles()
	if failures.is_empty():
		print("Stage 3 dialogue layout headless tests passed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _check_game_layout() -> void:
	var game := GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.custom_minimum_size = Vector2.ZERO
	game.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var panel: ChoicePanel = game.get_node("%ChoicePanel")
	var bubble: CurrentSpeechBubble = game.get_node("ConversationViewport/CurrentSpeechBubble")
	var first: TextureButton = panel.get_node("ChoiceContainer/ChoiceButton1")
	var second: TextureButton = panel.get_node("ChoiceContainer/ChoiceButton2")
	var countdown: ProgressBar = panel.get_node("ChoiceContainer/ChoiceCountdown")
	var combo: Label = game.get_node("%StatusHUD/ComboLabel")
	game.dialogue_panel.append_history("Layout check")
	panel.show_choices([{"id": "good", "text": "Choice one"}, {"id": "bad", "text": "Choice two"}])
	await process_frame
	await process_frame
	for width in [1440.0, 1024.0, 720.0]:
		game.size = Vector2(width, 1024.0)
		await process_frame
		game.dialogue_panel.refresh_active_dialogue_position()
		await process_frame
		_check(absf(bubble.global_position.x + bubble.size.x * 0.5 - width * 0.5) < 2.0, "Dialogue bubble is not centered at width %s: game=%s, panel=%s, x=%s, size=%s." % [width, game.size.x, game.dialogue_panel.size.x, bubble.global_position.x, bubble.size.x])
		_check(absf(first.global_position.x + first.size.x - bubble.global_position.x - bubble.size.x) < 2.0, "Choices and bubble right edges differ at width %s." % width)
		_check(absf(second.global_position.x + second.size.x - bubble.global_position.x - bubble.size.x) < 2.0, "Second choice and bubble right edges differ at width %s." % width)
		_check(first.global_position.x >= 0.0, "Choices leave the left edge at width %s." % width)
		_check(bubble.global_position.y - (second.global_position.y + second.size.y) <= 16.0, "Gap above dialogue is excessive at width %s." % width)
		_check(bubble.global_position.y >= second.global_position.y + second.size.y, "Choice overlaps dialogue at width %s." % width)
		_check(absf(countdown.global_position.y + countdown.size.y - second.global_position.y - second.size.y) < 1.0, "Countdown is not on the choice container bottom edge.")
	_check((countdown.get_theme_stylebox("fill") as StyleBoxFlat).bg_color == Color.WHITE, "Countdown fill is not white.")
	_check(bubble.text_label.get_theme_font_size("font_size") == 30, "Psychological dialogue font differs from shared body size.")
	_check((first.get_node("Label") as Label).get_theme_font_size("font_size") == 28, "Choice font size changed.")
	_check(combo.get_theme_font_size("font_size") == 36, "Combo font was not increased.")
	_check(combo.position.y >= (game.get_node("%StatusHUD/EmotionalBar/Track") as Control).position.y + (game.get_node("%StatusHUD/EmotionalBar/Track") as Control).size.y, "Combo overlaps status bar.")
	game._stop_runtime_timers()
	game.queue_free()
	await process_frame

func _check_opening_and_ending_styles() -> void:
	var opening := OPENING_SCENE.instantiate()
	root.add_child(opening)
	await process_frame
	opening.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_check(opening.dialogue_label.get_theme_font_size("normal_font_size") == 30, "Opening dialogue font differs.")
	_check(opening.speaker_label.get_theme_font_size("font_size") == 30, "Opening speaker font differs.")
	while opening._current_entry_index < opening._find_step_index("r37"):
		opening._advance_script()
	_check(opening._choice_buttons.get_child_count() == 3, "Opening branch count changed.")
	for button in opening._choice_buttons.get_children():
		_check(button is TextureButton, "Opening choice does not use the shared visual component.")
		_check((button.get_node("Label") as Label).get_theme_font_size("font_size") == 28, "Opening choice text differs from game choices.")
	opening.size = Vector2(720.0, 1024.0)
	await process_frame
	for button in opening._choice_buttons.get_children():
		_check(button.global_position.x >= 0.0 and button.global_position.x + button.size.x <= 720.0, "Opening choice clips in a narrow window.")
	_check(opening.get_node_or_null("SafeArea/RootLayout/DialogueBox/DialogueLayout/ChoiceCountdown") == null, "Opening choices gained a countdown.")
	opening.queue_free()
	await process_frame
	var ending := ENDING_SCENE.instantiate()
	root.add_child(ending)
	await process_frame
	_check((ending.get_node("OuterMargin/Layout/EndingBody") as Label).get_theme_font_size("font_size") == 30, "Ending narrative font differs.")
	ending.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
