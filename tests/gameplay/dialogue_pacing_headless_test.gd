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
	var countdown: ProgressBar = game.choice_panel.get_node("ChoiceCountdown")
	await process_frame
	_assert(countdown.visible and countdown.value > 0.99, "Choice countdown was not visible or synchronized at start.")
	_assert(countdown.size.y <= 6.0, "Choice countdown bar is not slim.")
	_assert(game.choice_panel.get_node_or_null("ChoiceCountdown/Label") == null, "Choice countdown still shows seconds text.")
	var first_button: TextureButton = game.choice_panel.get_node("ChoiceButton1")
	var second_button: TextureButton = game.choice_panel.get_node("ChoiceButton2")
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
	game._stop_runtime_timers()
	_assert(game.choice_timeout_timer.is_stopped(), "Runtime cleanup left the choice timer running.")
	game.queue_free()
	await process_frame

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
