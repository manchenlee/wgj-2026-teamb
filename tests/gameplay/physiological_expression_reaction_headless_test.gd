extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const CONTROLLER_SCRIPT := preload("res://scripts/core/game_session_controller.gd")
const PROFILE_SCRIPT := preload("res://data/character_profiles/phase_character_profile.gd")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")

const PSYCHOLOGICAL_MODE := CONTROLLER_SCRIPT.InteractionMode.PSYCHOLOGICAL
const PHYSIOLOGICAL_MODE := CONTROLLER_SCRIPT.InteractionMode.PHYSIOLOGICAL
const PHYSIOLOGICAL_SOURCE := CONTROLLER_SCRIPT.CharacterExpressionSource.PHYSIOLOGICAL
const PSYCHOLOGICAL_SOURCE := CONTROLLER_SCRIPT.CharacterExpressionSource.PSYCHOLOGICAL
const POSITIVE := PROFILE_SCRIPT.ExpressionState.POSITIVE
const NEGATIVE := PROFILE_SCRIPT.ExpressionState.NEGATIVE

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_crossing_direction_hearts_and_ordering()
	await _test_timeout_rearm_and_stale_tokens()
	await _test_passive_decay_and_large_jumps()
	await _test_mode_switch_and_psychological_coexistence()
	await _test_initialization_and_reset()
	if _failures.is_empty():
		print("Physiological expression-reaction headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_crossing_direction_hearts_and_ordering() -> void:
	var game = await _create_game()
	var initial_scores: Array = [game.arousal_model.emotional, game.arousal_model.peak]
	var initial_phase: int = game.active_phase_index
	var initial_bgm: String = game.last_requested_bgm_key
	var heart_count: int = game.character_area.prompt_layer.get_child_count()
	var crossing_snapshots: Array = []
	game.physiological_visual_band_changed.connect(
		func(_previous: int, current: int, _direction: int) -> void:
			crossing_snapshots.append({
				"band": game.current_visual_band,
				"signal_band": current,
				"expression": _request_for(game, PHYSIOLOGICAL_SOURCE).get("expression", -1),
			})
	)
	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	_assert(_request_for(game, PHYSIOLOGICAL_SOURCE).get("expression") == POSITIVE, "Upward crossing did not request PHYSIOLOGICAL/POSITIVE.")
	_assert(game.character_area.prompt_layer.get_child_count() == heart_count + 5, "Upward crossing did not invoke the existing five-heart path exactly once.")
	_assert(not crossing_snapshots.is_empty() and crossing_snapshots[0] == {"band": 3, "signal_band": 3, "expression": POSITIVE}, "Base band was not updated before the physiological reaction/crossing event: %s" % str(crossing_snapshots))

	heart_count = game.character_area.prompt_layer.get_child_count()
	game.arousal_model.physical = 49.0
	game._sync_physiological_visual_band()
	_assert(_request_for(game, PHYSIOLOGICAL_SOURCE).get("expression") == NEGATIVE, "Downward crossing did not request PHYSIOLOGICAL/NEGATIVE.")
	_assert(game.character_area.prompt_layer.get_child_count() == heart_count, "Downward crossing incorrectly triggered hearts.")
	_assert([game.arousal_model.emotional, game.arousal_model.peak] == initial_scores, "Expression integration changed emotional or peak scoring.")
	_assert(game.active_phase_index == initial_phase and not game.phase_transition_in_progress, "Expression integration changed phase behavior.")
	_assert(not game.ending_transition_started and game.last_requested_bgm_key == initial_bgm, "Expression integration changed ending or BGM behavior.")
	await _free_game(game)


func _test_timeout_rearm_and_stale_tokens() -> void:
	var game = await _create_game()
	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	var positive_token: int = game._physiological_expression_request_token
	await create_timer(0.8).timeout
	game.arousal_model.physical = 49.0
	game._sync_physiological_visual_band()
	var negative_token: int = game._physiological_expression_request_token
	_assert(negative_token != positive_token, "A re-armed crossing reused the old physiological token.")
	_assert(game.physiological_expression_timer.time_left > 1.3, "Second crossing did not re-arm the 1.5-second lifetime.")
	_assert(not game._complete_physiological_expression_reaction(positive_token), "Stale POSITIVE timeout cleared newer NEGATIVE.")
	_assert(_request_for(game, PHYSIOLOGICAL_SOURCE).get("expression") == NEGATIVE, "Stale POSITIVE timeout changed newer NEGATIVE.")
	await create_timer(0.8).timeout
	_assert(_request_for(game, PHYSIOLOGICAL_SOURCE).get("expression") == NEGATIVE, "Newer reaction expired on the older reaction's deadline.")
	await create_timer(0.8).timeout
	_assert(not game.get_character_expression_request_state().requests.has(PHYSIOLOGICAL_SOURCE), "Physiological expression did not automatically clear after its own 1.5 seconds.")

	game.arousal_model.physical = 49.0
	game._sync_physiological_visual_band(false)
	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	positive_token = game._physiological_expression_request_token
	game.arousal_model.physical = 49.0
	game._sync_physiological_visual_band()
	negative_token = game._physiological_expression_request_token
	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	var newer_positive_token: int = game._physiological_expression_request_token
	_assert(not game._complete_physiological_expression_reaction(negative_token), "Stale NEGATIVE timeout cleared newer POSITIVE.")
	_assert(not game._complete_physiological_expression_reaction(positive_token), "Older POSITIVE timeout cleared newest POSITIVE.")
	_assert(newer_positive_token != positive_token and _request_for(game, PHYSIOLOGICAL_SOURCE).get("expression") == POSITIVE, "NEGATIVE-to-POSITIVE replacement was not retained.")
	await _free_game(game)


func _test_passive_decay_and_large_jumps() -> void:
	var game = await _create_game()
	game.arousal_model.physical = 50.01
	game._sync_physiological_visual_band(false)
	game.arousal_model.apply_decay(0.01)
	game._sync_physiological_visual_band()
	_assert(game.current_visual_band == 2 and _request_for(game, PHYSIOLOGICAL_SOURCE).get("expression") == NEGATIVE, "Passive-decay crossing did not use normal NEGATIVE behavior.")
	game._reset_physiological_expression_reaction()

	game.arousal_model.physical = 20.0
	game._sync_physiological_visual_band(false)
	var token_generation: int = game._next_character_expression_token
	var heart_count: int = game.character_area.prompt_layer.get_child_count()
	game.arousal_model.physical = 100.0
	game._sync_physiological_visual_band()
	_assert(game.current_visual_band == 5 and game._next_character_expression_token == token_generation + 1, "Large upward jump emitted more than one physiological reaction.")
	_assert(game.character_area.prompt_layer.get_child_count() == heart_count + 5, "Large upward jump did not emit exactly one heart burst.")
	game._reset_physiological_expression_reaction()
	token_generation = game._next_character_expression_token
	heart_count = game.character_area.prompt_layer.get_child_count()
	game.arousal_model.physical = 20.0
	game._sync_physiological_visual_band()
	_assert(game.current_visual_band == 1 and game._next_character_expression_token == token_generation + 1, "Large downward jump emitted more than one physiological reaction.")
	_assert(_request_for(game, PHYSIOLOGICAL_SOURCE).get("expression") == NEGATIVE, "Large downward jump did not request one NEGATIVE reaction.")
	_assert(game.character_area.prompt_layer.get_child_count() == heart_count, "Large downward jump incorrectly triggered hearts.")
	await _free_game(game)


func _test_mode_switch_and_psychological_coexistence() -> void:
	var game = await _create_game()
	var psychological_token: int = game.request_character_expression(PSYCHOLOGICAL_SOURCE, NEGATIVE)
	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	var state: Dictionary = game.get_character_expression_request_state()
	_assert(state.has_conflict and state.presentation_expression == PROFILE_SCRIPT.ExpressionState.NEUTRAL, "Coexisting conflicting requests changed Stage 6A conflict behavior.")
	game.set_interaction_mode(PHYSIOLOGICAL_MODE)
	game.set_interaction_mode(PSYCHOLOGICAL_MODE)
	_assert(not game.physiological_expression_timer.paused, "Interaction-mode switching paused physiological lifetime.")
	await create_timer(CONFIG.PHYSIOLOGICAL_EXPRESSION_DURATION_SECONDS + 0.1).timeout
	state = game.get_character_expression_request_state()
	_assert(not state.requests.has(PHYSIOLOGICAL_SOURCE), "Physiological request survived its lifetime after mode switching.")
	_assert(state.requests.has(PSYCHOLOGICAL_SOURCE) and state.presentation_expression == NEGATIVE, "Physiological expiry cleared or changed the psychological request.")
	game.clear_character_expression(PSYCHOLOGICAL_SOURCE, psychological_token)
	await _free_game(game)


func _test_initialization_and_reset() -> void:
	var game = await _create_game()
	_assert(not game.get_character_expression_request_state().requests.has(PHYSIOLOGICAL_SOURCE), "Initialization emitted a physiological expression reaction.")
	_assert(game.physiological_expression_timer.is_stopped(), "Initialization armed the physiological expression timer.")
	var initial_hearts: int = game.character_area.prompt_layer.get_child_count()
	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	var stale_token: int = game._physiological_expression_request_token
	game.reset_run()
	_assert(game.physiological_expression_timer.is_stopped(), "Reset did not stop physiological expression lifetime.")
	_assert(not game.get_character_expression_request_state().requests.has(PHYSIOLOGICAL_SOURCE), "Reset did not clear physiological expression request.")
	_assert(game._physiological_expression_request_token == -1, "Reset retained a physiological lifetime token.")
	_assert(not game._complete_physiological_expression_reaction(stale_token), "Pre-reset timeout remained valid after reset.")
	_assert(game.character_area.prompt_layer.get_child_count() == initial_hearts + 5, "Reset synchronization emitted an extra heart reaction.")
	await _free_game(game)


func _create_game():
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._stop_runtime_timers()
	return game


func _free_game(game) -> void:
	game.queue_free()
	await process_frame


func _request_for(game, source: int) -> Dictionary:
	return game.get_character_expression_request_state().requests.get(source, {})


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
