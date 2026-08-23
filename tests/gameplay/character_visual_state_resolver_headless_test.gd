extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const GAME_SESSION_CONTROLLER_SCRIPT := preload("res://scripts/core/game_session_controller.gd")
const PROFILE_SCRIPT := preload("res://data/character_profiles/phase_character_profile.gd")
const PHASE_1_PROFILE_SCRIPT := preload("res://data/character_profiles/phase_1_character_profile.gd")
const PHASE_2_PROFILE_SCRIPT := preload("res://data/character_profiles/phase_2_character_profile.gd")

const NEUTRAL := PROFILE_SCRIPT.ExpressionState.NEUTRAL
const POSITIVE := PROFILE_SCRIPT.ExpressionState.POSITIVE
const NEGATIVE := PROFILE_SCRIPT.ExpressionState.NEGATIVE

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_all_bands_and_expression_fallbacks()
	_test_expression_and_band_independence()
	await _test_live_crossing_compatibility()
	if _failures.is_empty():
		print("Character visual-state resolver headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_all_bands_and_expression_fallbacks() -> void:
	var early_profile = PHASE_1_PROFILE_SCRIPT.new()
	var late_profile = PHASE_2_PROFILE_SCRIPT.new()
	for band in range(6):
		var profile = early_profile if band <= 2 else late_profile
		var expected_profile_id := "phase_1_profile" if band <= 2 else "phase_2_profile"
		var neutral: Dictionary = profile.resolve_visual_state(band, NEUTRAL)
		_assert(neutral.get("profile_id") == expected_profile_id, "Band %d resolved to the wrong profile family." % band)
		_assert(neutral.get("visual_band") == band, "Band %d did not resolve deterministically." % band)
		_assert(not String(neutral.get("base_state_key", "")).is_empty(), "Band %d has no neutral base state." % band)
		_assert(neutral.get("requested_expression") == NEUTRAL, "Neutral request was not retained for band %d." % band)
		_assert(neutral.get("resolved_expression") == NEUTRAL, "Neutral did not resolve for band %d." % band)
		_assert(not String(neutral.get("base_state_key", "")).contains(".png"), "Resolver exposed a constructed asset filename for band %d." % band)
		_assert(not String(neutral.get("face_state_key", "")).contains(".png"), "Resolver exposed a constructed face filename for band %d." % band)
		for expression in [POSITIVE, NEGATIVE]:
			var fallback: Dictionary = profile.resolve_visual_state(band, expression)
			_assert(fallback.get("visual_band") == band, "Expression fallback changed band %d." % band)
			_assert(fallback.get("requested_expression") == expression, "Expression request was lost for band %d." % band)
			_assert(fallback.get("resolved_expression") == NEUTRAL, "Missing expression art did not fall back to neutral for band %d." % band)
			_assert(fallback.get("base_state_key") == neutral.get("base_state_key"), "Expression fallback changed the neutral base for band %d." % band)
			_assert(fallback.get("face_state_key") == neutral.get("face_state_key"), "Expression fallback changed the neutral face for band %d." % band)


func _test_expression_and_band_independence() -> void:
	var controller = GAME_SESSION_CONTROLLER_SCRIPT.new()
	controller.arousal_model.physical = 40.0
	controller._sync_physiological_visual_band(false)
	var initial_band: int = controller.current_visual_band
	controller.set_character_expression_state(POSITIVE)
	_assert(controller.current_visual_band == initial_band, "Changing expression changed the visual band.")
	controller.arousal_model.physical = 50.0
	controller._sync_physiological_visual_band(false)
	_assert(controller.current_expression_state == POSITIVE, "Changing visual band reset the requested expression.")
	var resolved: Dictionary = controller.resolve_character_visual_state()
	_assert(resolved.get("visual_band") == 3, "Controller resolver did not use the cached visual band.")
	_assert(resolved.get("requested_expression") == POSITIVE, "Controller resolver did not retain requested expression.")
	_assert(resolved.get("resolved_expression") == NEUTRAL, "Controller resolver did not apply neutral fallback.")
	controller.free()


func _test_live_crossing_compatibility() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_character_expression_state(NEGATIVE)
	game.arousal_model.physical = 49.0
	game.arousal_model.emotional = 61.0
	game.arousal_model.peak = 37.0
	var emotional_before: float = game.arousal_model.emotional
	var peak_before: float = game.arousal_model.peak
	var phase_before: int = game.active_phase_index
	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	_assert(game.current_visual_band == 3, "Live band 2 to 3 crossing did not reach band 3.")
	_assert(game.current_character_presentation_family == 1, "Live band 2 to 3 crossing did not select Phase 2 presentation.")
	var request_state: Dictionary = game.get_character_expression_request_state()
	_assert(request_state.has_conflict and game.current_expression_state == NEUTRAL, "Live crossing did not preserve Stage 6A conflict behavior.")
	_assert(request_state.requests.has(GAME_SESSION_CONTROLLER_SCRIPT.CharacterExpressionSource.COMPATIBILITY), "Live crossing discarded the compatibility expression request.")
	_assert(request_state.requests.has(GAME_SESSION_CONTROLLER_SCRIPT.CharacterExpressionSource.PHYSIOLOGICAL), "Live crossing did not retain the physiological expression request.")
	_assert(game.arousal_model.emotional == emotional_before, "Live crossing changed psychological score.")
	_assert(game.arousal_model.peak == peak_before, "Live crossing changed peak.")
	_assert(game.active_phase_index == phase_before, "Live crossing changed gameplay phase.")
	var resolved: Dictionary = game.resolve_character_visual_state()
	_assert(resolved.get("requested_expression") == NEUTRAL, "Live resolver did not receive the neutral conflict presentation.")
	_assert(resolved.get("resolved_expression") == NEUTRAL, "Live missing negative art did not fall back safely.")
	game.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
