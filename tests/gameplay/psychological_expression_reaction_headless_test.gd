extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CONTROLLER_SCRIPT := preload("res://scripts/core/game_session_controller.gd")
const PROFILE_SCRIPT := preload("res://data/character_profiles/phase_character_profile.gd")

const PSYCHOLOGICAL_MODE := CONTROLLER_SCRIPT.InteractionMode.PSYCHOLOGICAL
const PHYSIOLOGICAL_MODE := CONTROLLER_SCRIPT.InteractionMode.PHYSIOLOGICAL
const PSYCHOLOGICAL_SOURCE := CONTROLLER_SCRIPT.CharacterExpressionSource.PSYCHOLOGICAL
const PHYSIOLOGICAL_SOURCE := CONTROLLER_SCRIPT.CharacterExpressionSource.PHYSIOLOGICAL
const NEUTRAL := PROFILE_SCRIPT.ExpressionState.NEUTRAL
const POSITIVE := PROFILE_SCRIPT.ExpressionState.POSITIVE
const NEGATIVE := PROFILE_SCRIPT.ExpressionState.NEGATIVE

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_good_and_bad_choice_paths()
	await _test_reaction_duration_and_mode_switch()
	await _test_stale_token_and_source_isolation()
	await _test_physiological_spot_paths()
	if _failures.is_empty():
		print("Psychological expression-reaction headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_good_and_bad_choice_paths() -> void:
	var game = await _create_game()
	var initial_physical: float = game.arousal_model.physical
	var initial_emotional: float = game.arousal_model.emotional
	var initial_band: int = game.current_visual_band
	var initial_phase: int = game.active_phase_index
	var initial_bgm_key: String = game.last_requested_bgm_key
	var heart_count_before: int = game.character_area.prompt_layer.get_child_count()
	_prepare_choice(game, "positive", ["positive reply one", "positive reply two"])
	game._on_choice_selected("good", "good choice")
	var good_request: Dictionary = _request_for(game, PSYCHOLOGICAL_SOURCE)
	_assert(good_request.get("expression") == POSITIVE, "Good choice did not request psychological POSITIVE.")
	_assert(game.arousal_model.emotional == initial_emotional + 10.0, "Good choice no longer applies exactly +10 emotional score.")
	_assert(game.character_area.prompt_layer.get_child_count() == heart_count_before + 5, "Good choice did not use the existing five-heart burst path.")
	_assert(not game.failure_flash.visible, "Good choice unexpectedly used failure feedback.")
	_assert(game.current_expression_state == POSITIVE, "Good reaction was not displayed immediately.")
	_assert(game.psychological_dialogue_controller.current_feedback_index == -1, "Choice response incorrectly remained in the pre-choice feedback sequence.")
	_assert(game.arousal_model.physical == initial_physical and game.current_visual_band == initial_band, "Good expression request changed physical score or visual band.")
	_assert(game.active_phase_index == initial_phase, "Good expression request changed gameplay config.")
	_assert(not game.ending_transition_started and game.last_requested_bgm_key == initial_bgm_key, "Good expression request changed ending or BGM state.")
	game.queue_free()
	await process_frame

	game = await _create_game()
	initial_emotional = game.arousal_model.emotional
	initial_physical = game.arousal_model.physical
	initial_band = game.current_visual_band
	_prepare_choice(game, "negative", ["negative reply one", "negative reply two"])
	game._on_choice_selected("bad", "bad choice")
	var bad_request: Dictionary = _request_for(game, PSYCHOLOGICAL_SOURCE)
	_assert(bad_request.get("expression") == NEGATIVE, "Bad choice did not request psychological NEGATIVE.")
	_assert(game.arousal_model.emotional == initial_emotional - 5.0, "Bad choice no longer applies exactly -5 emotional score.")
	_assert(game.failure_flash.visible, "Bad choice did not use the existing failure-flash path.")
	_assert(game.arousal_model.physical == initial_physical and game.current_visual_band == initial_band, "Bad expression request changed physical score or visual band.")
	game.queue_free()
	await process_frame


func _test_reaction_duration_and_mode_switch() -> void:
	var game = await _create_game()
	_prepare_choice(game, "positive", ["one of several authored response options", "another option"])
	game._on_choice_selected("good", "good choice")
	_assert(game.current_expression_state == POSITIVE, "Positive request was not active while the response line was displayed.")
	_assert(not game.psychological_dialogue_timer.is_stopped(), "Post-choice round-completion timer was not scheduled.")

	game.set_interaction_mode(PHYSIOLOGICAL_MODE)
	_assert(game.current_expression_state == POSITIVE, "Mode switch cleared the psychological reaction.")
	_assert(game.psychological_dialogue_timer.paused, "Psychological dialogue timer did not pause in physiological mode.")
	game._advance_character_expression_reactions(0.49)
	_assert(game.current_expression_state == POSITIVE, "Psychological reaction ended before 0.5 seconds.")
	game._advance_character_expression_reactions(0.02)
	_assert(game.current_expression_state == NEUTRAL, "Psychological reaction did not return to neutral after 0.5 seconds.")

	game.set_interaction_mode(PSYCHOLOGICAL_MODE)
	_assert(not game.get_character_expression_request_state().requests.has(PSYCHOLOGICAL_SOURCE), "Returning to psychological mode retained the previous dialogue reaction.")
	_assert(game.current_expression_state == NEUTRAL, "A new psychological dialogue did not begin neutral.")
	_assert(not game.psychological_dialogue_controller.current_line.is_empty(), "A new psychological dialogue did not produce an opening line.")
	_assert(game.dialogue_panel.get_dialogue_history().size() == 1, "A new psychological dialogue did not replace the previous history with one opening line.")
	game.queue_free()
	await process_frame


func _test_stale_token_and_source_isolation() -> void:
	var game = await _create_game()
	_prepare_choice(game, "positive", ["first response"])
	game._on_choice_selected("good", "first choice")
	var stale_token: int = _request_for(game, PSYCHOLOGICAL_SOURCE).get("token", -1)
	_prepare_choice(game, "negative", ["newer response"])
	game._on_choice_selected("bad", "newer choice")
	var current_token: int = _request_for(game, PSYCHOLOGICAL_SOURCE).get("token", -1)
	_assert(current_token != stale_token, "Newer psychological reaction reused the old token.")
	_assert(not game.clear_character_expression(PSYCHOLOGICAL_SOURCE, stale_token), "Stale token cleared a newer reaction.")
	_assert(game.current_expression_state == NEGATIVE, "Stale callback changed the newer psychological reaction.")

	var physiological_token: int = game.request_character_expression(PHYSIOLOGICAL_SOURCE, POSITIVE)
	var conflict: Dictionary = game.get_character_expression_request_state()
	_assert(conflict.has_conflict and conflict.presentation_expression == POSITIVE, "Newest reaction did not appear during overlapping requests.")
	_assert(game.clear_character_expression(PSYCHOLOGICAL_SOURCE, current_token), "Current token did not clear psychological reaction.")
	var remaining: Dictionary = game.get_character_expression_request_state()
	_assert(remaining.requests.has(PHYSIOLOGICAL_SOURCE), "Clearing psychological reaction deleted physiological request.")
	_assert(remaining.presentation_expression == POSITIVE and not remaining.has_conflict, "Remaining physiological request was not restored after conflict.")
	_assert(game.clear_character_expression(PHYSIOLOGICAL_SOURCE, physiological_token), "Physiological cleanup failed.")
	game.queue_free()
	await process_frame


func _test_physiological_spot_paths() -> void:
	var game = await _create_game()
	game._on_physiological_spot_completed()
	_assert(game.current_expression_state == POSITIVE, "Completed spot did not show positive face.")
	game._advance_character_expression_reactions(0.49)
	_assert(game.current_expression_state == POSITIVE, "Completed spot reaction ended before 0.5 seconds.")
	game._advance_character_expression_reactions(0.02)
	_assert(game.current_expression_state == NEUTRAL, "Completed spot reaction did not return to neutral.")
	game._on_physiological_spot_failed(0.0, 0.0)
	_assert(game.current_expression_state == NEGATIVE, "Missed spot did not show negative face.")
	game._advance_character_expression_reactions(0.5)
	_assert(game.current_expression_state == NEUTRAL, "Missed spot reaction did not return to neutral.")
	game.queue_free()
	await process_frame


func _create_game():
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_interaction_mode(PSYCHOLOGICAL_MODE)
	return game


func _prepare_choice(game, effect: String, responses: Array) -> void:
	game.psychological_dialogue_controller.current_entry = {
		"choice": [
			{"id": "good", "effect": effect},
			{"id": "bad", "effect": effect},
		],
		"response": {
			"good": responses,
			"bad": responses,
		},
	}
	game.psychological_dialogue_controller.current_feedback_index = 1
	game.psychological_dialogue_controller.choice_prompt_pending = true


func _request_for(game, source: int) -> Dictionary:
	return game.get_character_expression_request_state().requests.get(source, {})


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
