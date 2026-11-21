extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_interaction_mode(1)
	game.arousal_model.physical = CONFIG.SAFE_WORD_PHYSICAL_THRESHOLD
	game._on_spot_telemetry_updated({})
	game._on_physiological_spot_completed()
	_check(game.interaction_mode == 0 and game._first_safe_word_dialogue_active,
		"Physical 50 did not force the safe-word dialogue.")
	game._push_next_dialogue_event(0)
	game._push_next_dialogue_event(0)
	_check(game.psychological_dialogue_controller.choice_prompt_pending,
		"Safe-word dialogue did not reach its choice.")
	game._on_choice_selected("option_2", "Stop")
	for index in range(20):
		if game.psychological_dialogue_controller.is_group_complete():
			break
		game._push_next_dialogue_event(0)
	_check(game.psychological_dialogue_controller.is_group_complete(),
		"Safe-word response lines did not finish.")
	game.dialogue_panel.current_speech_bubble.finish_dialogue_stream()
	game._on_dialogue_bubble_advance_requested()
	_check(game._group_gap_active and is_equal_approx(game.psychological_dialogue_timer.wait_time,
		CONFIG.PSYCHOLOGICAL_GROUP_GAP_SECONDS), "Safe-word dialogue did not start the 1.5-second gap.")
	var gap_generation: int = game._reading_step_generation
	var history_size: int = game.dialogue_panel.get_dialogue_history().size()
	_click_at(Vector2(10.0, 10.0))
	game._on_dialogue_bubble_advance_requested()
	_check(game._group_gap_active and game._reading_step_generation == gap_generation
		and game.dialogue_panel.get_dialogue_history().size() == history_size,
		"Click skipped the safe-word dialogue gap.")
	await create_timer(0.2).timeout
	_check(game._group_gap_active and game.dialogue_panel.get_dialogue_history().size() == history_size,
		"Next dialogue appeared before the 1.5-second gap elapsed.")
	await create_timer(CONFIG.PSYCHOLOGICAL_GROUP_GAP_SECONDS).timeout
	_check(not game._group_gap_active and game.dialogue_panel.get_dialogue_history().size() > history_size,
		"Next dialogue did not appear after the gap elapsed.")
	game._stop_runtime_timers()
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Safe-word group gap headless test passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _click_at(position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		root.push_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
