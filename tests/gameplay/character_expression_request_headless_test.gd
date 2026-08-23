extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CONTROLLER_SCRIPT := preload("res://scripts/core/game_session_controller.gd")
const PROFILE_SCRIPT := preload("res://data/character_profiles/phase_character_profile.gd")

const PHYSIOLOGICAL := CONTROLLER_SCRIPT.CharacterExpressionSource.PHYSIOLOGICAL
const PSYCHOLOGICAL := CONTROLLER_SCRIPT.CharacterExpressionSource.PSYCHOLOGICAL
const NEUTRAL := PROFILE_SCRIPT.ExpressionState.NEUTRAL
const POSITIVE := PROFILE_SCRIPT.ExpressionState.POSITIVE
const NEGATIVE := PROFILE_SCRIPT.ExpressionState.NEGATIVE

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_tokens_and_source_ownership()
	_test_conflicting_requests_have_no_source_priority()
	await _test_reset_family_and_gameplay_isolation()
	if _failures.is_empty():
		print("Character expression-request headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_tokens_and_source_ownership() -> void:
	var controller = CONTROLLER_SCRIPT.new()
	_assert(controller.current_expression_state == NEUTRAL, "Default expression was not neutral.")
	var first_positive: int = controller.request_character_expression(PHYSIOLOGICAL, POSITIVE)
	_assert(controller.current_expression_state == POSITIVE, "A physiological positive request was not retained logically.")
	var newer_negative: int = controller.request_character_expression(PHYSIOLOGICAL, NEGATIVE)
	_assert(newer_negative != first_positive, "A newer same-source request reused its old token.")
	_assert(controller.current_expression_state == NEGATIVE, "A newer same-source negative request did not replace the older request.")
	_assert(not controller.clear_character_expression(PHYSIOLOGICAL, first_positive), "A stale token cleared a newer same-source request.")
	_assert(controller.current_expression_state == NEGATIVE, "A stale clear changed the logical expression.")
	var psychological_token: int = controller.request_character_expression(PSYCHOLOGICAL, NEGATIVE)
	_assert(controller.clear_character_expression(PHYSIOLOGICAL, newer_negative), "The current physiological token did not clear its source.")
	var state: Dictionary = controller.get_character_expression_request_state()
	_assert(state.requests.has(PSYCHOLOGICAL), "Clearing physiological deleted the psychological request.")
	_assert(controller.current_expression_state == NEGATIVE, "Remaining psychological request was not retained.")
	_assert(controller.clear_character_expression(PSYCHOLOGICAL, psychological_token), "Current psychological token did not clear.")
	_assert(controller.current_expression_state == NEUTRAL, "Clearing the final request did not restore neutral.")
	controller.free()


func _test_conflicting_requests_have_no_source_priority() -> void:
	var controller = CONTROLLER_SCRIPT.new()
	var physiological_token: int = controller.request_character_expression(PHYSIOLOGICAL, POSITIVE)
	var psychological_token: int = controller.request_character_expression(PSYCHOLOGICAL, NEGATIVE)
	var conflict: Dictionary = controller.get_character_expression_request_state()
	_assert(conflict.has_conflict, "Opposing source requests were not reported as a conflict.")
	_assert(conflict.requests.size() == 2, "A conflict discarded one source request.")
	_assert(conflict.presentation_expression == NEUTRAL, "Conflict compatibility behavior selected a source instead of neutral.")
	_assert(controller.clear_character_expression(PHYSIOLOGICAL, physiological_token), "Could not clear one side of a conflict.")
	_assert(controller.current_expression_state == NEGATIVE, "Remaining conflict request did not become effective.")
	_assert(not controller.character_expression_conflict, "Conflict flag remained after one source cleared.")
	controller.clear_character_expression(PSYCHOLOGICAL, psychological_token)
	controller.free()


func _test_reset_family_and_gameplay_isolation() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var scores_before := [game.arousal_model.physical, game.arousal_model.emotional, game.arousal_model.peak]
	var gameplay_before := [game.active_phase_index, game.interaction_mode, game.run_active]
	var token: int = game.request_character_expression(PSYCHOLOGICAL, POSITIVE)
	_assert(
		[game.arousal_model.physical, game.arousal_model.emotional, game.arousal_model.peak] == scores_before,
		"Requesting an expression changed gameplay scores."
	)
	_assert([game.active_phase_index, game.interaction_mode, game.run_active] == gameplay_before, "Requesting an expression changed gameplay state.")
	var positive_resolution: Dictionary = game.resolve_character_visual_state()
	_assert(positive_resolution.requested_expression == POSITIVE, "Resolver lost the positive logical request.")
	_assert(positive_resolution.resolved_expression == NEUTRAL, "Missing positive artwork did not use neutral fallback.")

	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	_assert(game.current_character_presentation_family == 1, "Band crossing did not switch presentation family.")
	_assert(game.current_expression_state == POSITIVE, "Family switching discarded a valid expression request.")
	var request_state: Dictionary = game.get_character_expression_request_state()
	_assert(request_state.requests.size() == 2, "Band crossing did not retain both source-owned expression requests.")
	_assert(request_state.requests.has(PHYSIOLOGICAL), "Band crossing did not create the Stage 6C physiological request.")

	game.reset_run()
	_assert(game.current_expression_state == NEUTRAL, "Full reset did not restore neutral.")
	_assert(game.get_character_expression_request_state().requests.is_empty(), "Full reset did not clear expression requests.")
	var replacement_token: int = game.request_character_expression(PSYCHOLOGICAL, NEGATIVE)
	_assert(replacement_token != token, "Post-reset request reused a stale token.")
	_assert(not game.clear_character_expression(PSYCHOLOGICAL, token), "A pre-reset token cleared a post-reset request.")
	_assert(game.current_expression_state == NEGATIVE, "Stale post-reset clear changed the current request.")
	var negative_resolution: Dictionary = game.resolve_character_visual_state()
	_assert(negative_resolution.requested_expression == NEGATIVE, "Resolver lost the negative logical request.")
	_assert(negative_resolution.resolved_expression == NEUTRAL, "Missing negative artwork did not use neutral fallback.")

	game._on_psychological_dialogue_timer_timeout()
	_assert(game.current_expression_state == NEGATIVE, "Dialogue timer automatically changed expression state.")
	_assert(game.get_character_expression_request_state().requests.size() == 1, "Dialogue timer automatically created or removed an expression request.")
	game.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
