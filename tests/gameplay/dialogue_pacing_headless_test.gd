extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")
const DIALOGUE_CONTROLLER := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const PHASE_CONFIG := preload("res://data/phases/phase_config.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_safe_word_substitution_and_validation()
	_test_reading_duration_bounds()
	await _test_choice_timer_and_penalty()
	await _test_safe_word_threshold_flow()
	await _test_manual_and_automatic_dialogue_advance()
	if _failures.is_empty():
		print("Dialogue pacing headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _test_safe_word_substitution_and_validation() -> void:
	_assert(CONFIG.normalize_safe_word("  \t\n  ") == CONFIG.SAFE_WORD_DEFAULT, "Whitespace did not use the default safe word.")
	_assert(CONFIG.normalize_safe_word("  Blue\n\u202E Moon  ") == "Blue Moon", "Control characters were not removed from the safe word.")
	_assert(CONFIG.normalize_safe_word("x".repeat(32)).length() == CONFIG.SAFE_WORD_MAX_LENGTH, "Safe word was not length limited.")
	var controller = DIALOGUE_CONTROLLER.new()
	controller.set_phase_config(PHASE_CONFIG.new())
	controller.set_safe_word("  天藍  ")
	var prompt: Dictionary = controller.next_event(50.0, 50.0, true)
	_assert(prompt.get("text", "").contains("天藍"), "Configured safe word was not substituted in authored dialogue.")
	_assert(not prompt.get("text", "").contains("【安全詞】"), "Literal safe-word marker remained in dialogue.")
	controller.set_safe_word("")
	controller.reset()
	prompt = controller.next_event(50.0, 50.0, true)
	_assert(prompt.get("text", "").contains(CONFIG.SAFE_WORD_DEFAULT), "Default safe word was not substituted.")
	controller.set_safe_word("A\nB")
	_assert(controller.safe_word == "AB", "Programmatic safe word retained a control character.")

func _test_reading_duration_bounds() -> void:
	var phase = PHASE_CONFIG.new({
		"feedback_message_interval_min": 2.0,
		"feedback_message_interval_max": 6.0,
		"feedback_characters_per_second": 12.0,
		"feedback_reading_lead_seconds": 1.0
	})
	_assert(phase.choice_timeout_seconds == 8.0, "Initial choice timeout is not eight seconds.")
	_assert(phase.choice_timeout_emotional_penalty == 2.0, "Initial timeout penalty is not two points.")
	_assert(PHASE_CONFIG.new({"choice_timeout_emotional_penalty": 3.5}).choice_timeout_emotional_penalty == 3.5, "Timeout penalty cannot be configured.")
	_assert(is_equal_approx(phase.reading_duration_for_text(""), 2.0), "Short line did not use reading minimum.")
	_assert(is_equal_approx(phase.reading_duration_for_text("字".repeat(36)), 4.0), "Reading time did not scale with text length.")
	_assert(is_equal_approx(phase.reading_duration_for_text("字".repeat(200)), 6.0), "Long line exceeded reading maximum.")

func _test_choice_timer_and_penalty() -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.psychological_dialogue_timer.stop()
	game.choice_timeout_timer.stop()
	game.arousal_model.physical = 50.0
	game.arousal_model.emotional = 50.0
	game.psychological_dialogue_controller.reset()
	game.psychological_dialogue_controller.current_entry = {
		"condition": {"physical": "any", "emotional": "any"},
		"feedback": ["請選擇。"],
		"choice": [
			{"id": "good", "text": "好", "effect": "positive"},
			{"id": "bad", "text": "不好", "effect": "negative"}
		]
	}
	game._push_next_dialogue_event(0)
	_assert(game.psychological_dialogue_controller.choice_prompt_pending, "Choice prompt was not opened.")
	_assert(is_equal_approx(game.choice_timeout_timer.wait_time, 8.0), "Authoritative choice timer did not start at eight seconds.")
	var countdown: ProgressBar = game.choice_panel.get_node("ChoiceContainer/ChoiceCountdown")
	await process_frame
	_assert(countdown.visible and countdown.value > 0.99, "Choice countdown was not visible or synchronized at start.")
	_assert(countdown.size.y <= 6.0, "Choice countdown bar is not slim.")
	_assert(game.choice_panel.get_node_or_null("ChoiceContainer/ChoiceCountdown/Label") == null, "Choice countdown still shows seconds text.")
	var first_button: TextureButton = game.choice_panel.get_node("ChoiceContainer/ChoiceButton1")
	var second_button: TextureButton = game.choice_panel.get_node("ChoiceContainer/ChoiceButton2")
	_assert(is_equal_approx(first_button.size.y, 100.0) and is_equal_approx(second_button.size.y, 100.0), "Choice buttons retained oversized transparent margins.")
	_assert(absf(second_button.position.y - (first_button.position.y + first_button.size.y)) < 1.0, "Choice buttons still have a large layout gap.")
	game.choice_timeout_timer.set_paused(true)
	var paused_time: float = game.choice_timeout_timer.time_left
	await create_timer(0.08).timeout
	game._update_choice_timer_visual()
	_assert(absf(game.choice_timeout_timer.time_left - paused_time) < 0.03, "Paused choice timer continued counting.")
	_assert(absf(countdown.value - game.choice_timeout_timer.time_left / game.choice_timeout_timer.wait_time) <= 0.02, "Countdown diverged from the authoritative timer.")
	game.choice_timeout_timer.set_paused(false)
	var emotional_before_timeout: float = game.arousal_model.emotional
	game._on_choice_timeout()
	_assert(is_equal_approx(game.arousal_model.emotional, emotional_before_timeout - 2.0), "Ordinary timeout did not apply exactly two emotional points.")
	_assert(not game._has_failed_safe_word_choice, "Choice timeout disabled safe-word dialogue.")
	_assert(not game.psychological_dialogue_controller.choice_prompt_pending, "Timeout retained a pending choice.")
	_assert(game.choice_timeout_timer.is_stopped() and not countdown.visible, "Timeout left the timer or countdown active.")
	_assert(game.choice_panel.get_node("TimeoutFeedback").visible, "Ordinary timeout gave no brief feedback.")
	var score_after_timeout: float = game.arousal_model.emotional
	game._on_choice_timeout()
	_assert(is_equal_approx(game.arousal_model.emotional, score_after_timeout), "Duplicate timeout applied a second penalty.")
	for item in game.dialogue_panel.get_dialogue_history():
		_assert(item.get("speaker_type", "") != "player", "Timeout was recorded as a selected answer.")

	game.psychological_dialogue_timer.stop()
	game.psychological_dialogue_controller.current_entry = {
		"condition": {"event": "safe_word"},
		"feedback": ["安全詞。"]
	}
	game.psychological_dialogue_controller.current_feedback_index = 0
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game.choice_timeout_timer.start(8.0)
	game._on_choice_timeout()
	_assert(is_equal_approx(game.arousal_model.emotional, score_after_timeout), "Safe-word timeout received the ordinary penalty.")
	_assert(not game.psychological_dialogue_controller.choice_prompt_pending, "Safe-word timeout did not clear its decision.")
	game.psychological_dialogue_timer.stop()
	game.arousal_model.emotional = 40.0
	game.psychological_dialogue_controller.current_entry = {
		"condition": {"physical": "any"},
		"feedback": ["請選擇。"],
		"choice": [{"id": "good", "text": "好", "effect": "positive"}]
	}
	game.psychological_dialogue_controller.current_feedback_index = 0
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game.choice_timeout_timer.start(8.0)
	game._on_choice_selected("good", "好")
	_assert(is_equal_approx(game.arousal_model.emotional, 50.0), "Selected answer did not retain its existing reward.")
	_assert(not game._has_failed_safe_word_choice, "Reward choice disabled safe-word dialogue.")
	game._on_choice_timeout()
	_assert(is_equal_approx(game.arousal_model.emotional, 50.0), "A selected answer was penalized by a late timeout.")

	game.psychological_dialogue_timer.stop()
	game.psychological_dialogue_controller.current_entry = {"condition": {"physical": "any"}, "feedback": ["再選一次。"]}
	game.psychological_dialogue_controller.current_feedback_index = 0
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game.choice_timeout_timer.start(8.0)
	game.set_interaction_mode(1)
	_assert(game.choice_timeout_timer.paused, "Physical mode did not pause an outstanding choice.")
	game._on_choice_timeout()
	_assert(is_equal_approx(game.arousal_model.emotional, 50.0), "Paused physical-mode choice applied a penalty.")
	game.set_interaction_mode(0)
	_assert(not game.choice_timeout_timer.paused, "Returning to psychological mode left the choice timer paused.")
	game.psychological_dialogue_controller.reset()
	game.psychological_dialogue_controller.current_entry = {
		"condition": {"physical": "any", "emotional": "any"},
		"feedback": ["Penalty choice"],
		"choice": [{"id": "bad", "text": "Bad", "effect": "negative"}]
	}
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game._on_choice_selected("bad", "Bad")
	_assert(not game._has_failed_safe_word_choice, "Ordinary penalty choice disabled safe-word dialogue.")
	game.psychological_dialogue_timer.stop()
	game.psychological_dialogue_controller.reset()
	game.psychological_dialogue_controller.current_entry = {
		"condition": {"event": "safe_word"},
		"feedback": ["Safe-word choice"],
		"choice": [{"id": "good", "text": "Stop", "effect": "positive"}]
	}
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game._on_choice_selected("good", "Stop")
	_assert(not game._has_failed_safe_word_choice, "Correct safe-word choice disabled future safe-word dialogue.")
	game.psychological_dialogue_timer.stop()
	game.psychological_dialogue_controller.reset()
	game.psychological_dialogue_controller.current_entry = {
		"condition": {"event": "safe_word"},
		"feedback": ["Safe-word choice"],
		"choice": [{"id": "bad", "text": "Continue", "effect": "negative"}]
	}
	game.psychological_dialogue_controller.choice_prompt_pending = true
	game._on_choice_selected("bad", "Continue")
	_assert(game._has_failed_safe_word_choice, "Wrong safe-word choice did not disable future safe-word dialogue.")
	for index in range(100):
		game.psychological_dialogue_timer.stop()
		game.psychological_dialogue_controller.reset()
		game._push_next_dialogue_event(0)
		var condition: Dictionary = game.psychological_dialogue_controller.current_entry.get("condition", {})
		_assert(condition.get("event", "") != "safe_word", "Safe-word dialogue appeared after a wrong safe-word choice on draw %d." % index)
	game._reset_run_for_phase_index(0)
	_assert(not game._has_failed_safe_word_choice, "New run did not restore safe-word eligibility.")
	game._stop_runtime_timers()
	_assert(game.choice_timeout_timer.is_stopped(), "Runtime cleanup left the choice timer running.")
	game.queue_free()
	await process_frame

func _test_safe_word_threshold_flow() -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_interaction_mode(1)
	game.arousal_model.physical = 49.0
	for index in range(50):
		game.psychological_dialogue_controller.reset()
		game.set_interaction_mode(0)
		var condition: Dictionary = game.psychological_dialogue_controller.current_entry.get("condition", {})
		_assert(condition.get("event", "") != "safe_word", "Safe-word dialogue appeared before physical 50 on draw %d." % index)
		game.set_interaction_mode(1)
	_assert(not game._safe_word_threshold_reached, "Physical 49 marked the threshold reached.")
	game.arousal_model.physical = 50.0
	game._on_spot_telemetry_updated({})
	_assert(game._safe_word_pending and game.interaction_mode == 1, "Threshold did not queue the safe-word dialogue until the spot finished.")
	game.arousal_model.physical = 48.0
	game._on_physiological_spot_completed()
	var safe_condition: Dictionary = game.psychological_dialogue_controller.current_entry.get("condition", {})
	_assert(game.interaction_mode == 0 and safe_condition.get("event", "") == "safe_word", "Spot completion did not show the queued safe-word dialogue.")
	_assert(game._first_safe_word_shown and not game._safe_word_pending, "First safe-word prompt did not consume the guarantee.")
	game.set_interaction_mode(1)
	_assert(game._safe_word_pending and not game._first_safe_word_shown, "Leaving the first safe-word dialogue lost its guarantee.")
	game.set_interaction_mode(0)
	safe_condition = game.psychological_dialogue_controller.current_entry.get("condition", {})
	_assert(safe_condition.get("event", "") == "safe_word" and game._first_safe_word_shown, "Returning to psychological mode did not replay the safe-word dialogue.")
	game._push_next_dialogue_event(0)
	game._push_next_dialogue_event(0)
	game._on_choice_selected("option_2", "Stop")
	_assert(not game._has_failed_safe_word_choice and not game._first_safe_word_dialogue_active, "Correct safe-word answer did not preserve repeat eligibility.")
	var probe_rng := RandomNumberGenerator.new()
	var repeat_seed := -1
	for seed_value in range(100):
		probe_rng.seed = seed_value
		if probe_rng.randf() < CONFIG.SAFE_WORD_EVENT_CHANCE:
			repeat_seed = seed_value
			break
	_assert(repeat_seed >= 0, "Could not find a deterministic safe-word repeat draw.")
	game.feedback_rng.seed = repeat_seed
	game.psychological_dialogue_controller.reset()
	game._push_next_dialogue_event(0)
	safe_condition = game.psychological_dialogue_controller.current_entry.get("condition", {})
	_assert(safe_condition.get("event", "") == "safe_word", "Safe-word dialogue did not remain available after the guaranteed appearance.")
	game.reset_run()
	_assert(not game._safe_word_threshold_reached and not game._first_safe_word_shown, "New run retained the previous threshold event.")
	game.start_direct_in_phase_2()
	safe_condition = game.psychological_dialogue_controller.current_entry.get("condition", {})
	_assert(safe_condition.get("event", "") == "safe_word" and game._first_safe_word_shown, "Direct start at physical 50 did not show the first safe-word dialogue.")
	game.reset_run()
	game.set_interaction_mode(1)
	game.arousal_model.physical = 100.0
	game.arousal_model.emotional = 95.0
	game._on_spot_telemetry_updated({})
	game._check_ending()
	_assert(game._first_safe_word_dialogue_active and not game.ending_transition_started, "Ending bypassed the threshold safe-word dialogue.")
	game._push_next_dialogue_event(0)
	game._push_next_dialogue_event(0)
	game._on_choice_selected("option_2", "Stop")
	game._check_ending()
	_assert(game.ending_transition_started, "Ending did not resume after the threshold safe-word choice.")
	game._stop_runtime_timers()
	game.queue_free()
	await process_frame

func _test_manual_and_automatic_dialogue_advance() -> void:
	root.size = Vector2i(1440, 1024)
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var bubble: CurrentSpeechBubble = game.dialogue_panel.current_speech_bubble
	_assert(game.dialogue_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Conversation viewport captured outside clicks.")
	_assert(bubble.mouse_filter == Control.MOUSE_FILTER_STOP, "Dialogue bubble does not receive clicks.")
	_assert(bubble.text_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Dialogue text captured clicks.")

	_prepare_two_line_dialogue(game)
	await process_frame
	var first_generation: int = game._reading_step_generation
	var first_wait: float = game.psychological_dialogue_timer.wait_time
	_click_at(Vector2(10.0, 10.0))
	_assert(game.dialogue_panel.get_dialogue_history().size() == 1, "Outside click advanced dialogue.")
	_assert(game._reading_step_generation == first_generation, "Outside click consumed the reading step.")
	_click_at(bubble.global_position + bubble.size * 0.5)
	_assert(game.dialogue_panel.get_dialogue_history().size() == 2, "Bubble click did not advance immediately.")
	_assert(game.psychological_dialogue_controller.choice_prompt_pending, "Manual advance skipped the choice prompt.")
	_assert(game.psychological_dialogue_timer.is_stopped(), "Manual advance left the reading timer active.")
	_assert(game.choice_timeout_timer.time_left > 0.0, "Manual advance did not start the choice countdown.")
	_assert(first_wait >= 2.0 and first_wait <= 6.0, "Manual test did not use the configured reading interval.")
	var history_at_choice: int = game.dialogue_panel.get_dialogue_history().size()
	_click_at(bubble.global_position + bubble.size * 0.5)
	_assert(game.dialogue_panel.get_dialogue_history().size() == history_at_choice, "Bubble click dismissed a pending choice.")
	_assert(game.psychological_dialogue_controller.choice_prompt_pending, "Bubble click cleared a pending choice.")
	_assert(not game.choice_timeout_timer.is_stopped(), "Bubble click stopped the choice countdown.")

	await process_frame
	_prepare_two_line_dialogue(game)
	await process_frame
	var automatic_generation: int = game._reading_step_generation
	game.psychological_dialogue_timer.start(0.05)
	await create_timer(0.10).timeout
	_assert(game.dialogue_panel.get_dialogue_history().size() == 2, "Reading timer did not advance dialogue.")
	_assert(game.psychological_dialogue_controller.choice_prompt_pending, "Automatic advance skipped the choice prompt.")
	game._on_psychological_dialogue_timer_timeout(automatic_generation)
	_assert(game.dialogue_panel.get_dialogue_history().size() == 2, "Stale timeout advanced a choice prompt.")

	await process_frame
	_prepare_two_line_dialogue(game)
	await process_frame
	var race_generation: int = game._reading_step_generation
	_click_at(bubble.global_position + bubble.size * 0.5)
	game._on_psychological_dialogue_timer_timeout(race_generation)
	_assert(game.dialogue_panel.get_dialogue_history().size() == 2, "Click followed by timeout skipped dialogue.")
	_assert(game.psychological_dialogue_controller.choice_prompt_pending, "Click/timeout race lost the choice prompt.")

	await process_frame
	_prepare_two_line_dialogue(game)
	await process_frame
	race_generation = game._reading_step_generation
	game._on_psychological_dialogue_timer_timeout(race_generation)
	_click_at(bubble.global_position + bubble.size * 0.5)
	_assert(game.dialogue_panel.get_dialogue_history().size() == 2, "Timeout followed by click skipped dialogue.")
	_assert(game.psychological_dialogue_controller.choice_prompt_pending, "Timeout/click race lost the choice prompt.")

	await process_frame
	_prepare_two_line_dialogue(game, ["First line", "Second line", "Third line"])
	await process_frame
	_click_at(bubble.global_position + bubble.size * 0.5)
	_click_at(bubble.global_position + bubble.size * 0.5)
	_assert(game.dialogue_panel.get_dialogue_history().size() == 2, "Two clicks in one frame skipped the newly displayed line.")
	await process_frame
	_click_at(bubble.global_position + bubble.size * 0.5)
	_assert(game.dialogue_panel.get_dialogue_history().size() == 3, "A later click did not advance the new line.")

	await process_frame
	_prepare_two_line_dialogue(game)
	await process_frame
	var old_generation: int = game._reading_step_generation
	game.set_interaction_mode(1)
	_assert(not bubble.is_visible_in_tree() and game.psychological_dialogue_timer.is_stopped(), "Physical mode kept the bubble or reading step active.")
	game._on_dialogue_bubble_advance_requested()
	game._on_psychological_dialogue_timer_timeout(old_generation)
	_assert(game.dialogue_panel.get_dialogue_history().size() == 1, "Hidden bubble or stale timeout advanced dialogue.")
	game.set_interaction_mode(0)
	await process_frame
	_assert(game._reading_step_generation != old_generation and game._reading_step_active, "Returning to psychological mode did not start a fresh reading step.")
	var generation_before_reset: int = game._reading_step_generation
	game.reset_run()
	await process_frame
	var history_after_reset: int = game.dialogue_panel.get_dialogue_history().size()
	game._on_psychological_dialogue_timer_timeout(generation_before_reset)
	_assert(game.dialogue_panel.get_dialogue_history().size() == history_after_reset, "Pre-reset timeout advanced the new run.")
	var generation_before_ending: int = game._reading_step_generation
	game._begin_ending_transition("failure")
	var history_at_ending: int = game.dialogue_panel.get_dialogue_history().size()
	game._on_psychological_dialogue_timer_timeout(generation_before_ending)
	game._on_dialogue_bubble_advance_requested()
	_assert(game.dialogue_panel.get_dialogue_history().size() == history_at_ending, "Ending transition accepted a stale advance.")
	game._stop_runtime_timers()
	game.queue_free()
	await process_frame

func _prepare_two_line_dialogue(game, feedback_lines: Array = ["First line", "Second line"]) -> void:
	game.psychological_dialogue_timer.stop()
	game.choice_timeout_timer.stop()
	game.choice_panel.clear_choices()
	game.dialogue_panel.clear_history()
	game.psychological_dialogue_controller.reset()
	game.psychological_dialogue_controller.current_entry = {
		"condition": {"physical": "any", "emotional": "any"},
		"feedback": feedback_lines,
		"choice": [
			{"id": "good", "text": "Yes", "effect": "positive"},
			{"id": "bad", "text": "No", "effect": "negative"}
		]
	}
	game._push_next_dialogue_event(0)

func _click_at(position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		root.push_input(event)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
