extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var controller: DialogueChoiceController = game.psychological_dialogue_controller
	controller.reset()
	controller.current_entry = {"feedback": ["First line", "Last line"]}
	game._push_next_dialogue_event(0)
	var first_waits_for_click: bool = game.psychological_dialogue_timer.is_stopped()
	game.dialogue_panel.current_speech_bubble.finish_dialogue_stream()
	game._on_dialogue_bubble_advance_requested()
	var last_waits_for_click: bool = game.psychological_dialogue_timer.is_stopped()
	game.dialogue_panel.current_speech_bubble.finish_dialogue_stream()
	await process_frame
	game._on_dialogue_bubble_advance_requested()
	var group_gap: float = game.psychological_dialogue_timer.wait_time
	var bubble_hidden: bool = not game.dialogue_panel.current_speech_bubble.visible
	var history_during_gap: int = game.dialogue_panel.get_dialogue_history().size()
	var gap_generation: int = game._reading_step_generation
	await process_frame
	game._on_psychological_dialogue_timer_timeout(gap_generation)
	var bubble_restored: bool = game.dialogue_panel.current_speech_bubble.visible
	var next_group_started: bool = game.dialogue_panel.get_dialogue_history().size() == history_during_gap + 1
	game._stop_runtime_timers()
	game.queue_free()
	await process_frame
	if not first_waits_for_click or not last_waits_for_click:
		push_error("An ordinary dialogue line started an automatic reading timer.")
		quit(1)
	elif not is_equal_approx(group_gap, 1.5):
		push_error("Completed dialogue group gap is not fixed at 1.5 seconds.")
		quit(1)
	elif not bubble_hidden or not bubble_restored or not next_group_started:
		push_error("The bubble did not hide during the group gap and reappear afterward.")
		quit(1)
	else:
		print("Dialogue group gap headless test passed.")
		quit(0)
