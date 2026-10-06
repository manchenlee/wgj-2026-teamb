extends SceneTree

const GAME_SCREEN := preload("res://scenes/screens/GameScreen.tscn")
const CONTROLLER := preload("res://scripts/core/game_session_controller.gd")
const PROFILE := preload("res://data/character_profiles/phase_character_profile.gd")
var _failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var game = GAME_SCREEN.instantiate()
    root.add_child(game)
    await process_frame
    var physical_before: float = game.arousal_model.physical
    var pose_before: int = game.current_presentation_phase
    var source := CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL
    var good: int = game.request_character_expression(source, PROFILE.ExpressionState.POSITIVE)
    _check(game.current_expression_state == PROFILE.ExpressionState.POSITIVE, "Correct result did not set positive expression.")
    _check(game.resolve_character_visual_state().resolved_expression == PROFILE.ExpressionState.POSITIVE, "Positive face art was unavailable.")
    var bad: int = game.request_character_expression(source, PROFILE.ExpressionState.NEGATIVE)
    _check(not game.clear_character_expression(source, good), "Stale result cleared newer face request.")
    _check(game.resolve_character_visual_state().face_state_key == "face_negative", "Incorrect result did not select angry face.")
    _check(game.arousal_model.physical == physical_before and game.current_presentation_phase == pose_before, "Psychology expression changed physiology or pose.")
    game.clear_character_expression(source, bad)
    _check(game.current_expression_state == PROFILE.ExpressionState.NEUTRAL, "Clearing result did not restore neutral.")
    game.arousal_model.physical = 60.0
    game._sync_physiological_visual_band()
    _check(game.current_expression_state == PROFILE.ExpressionState.NEUTRAL, "Physiology crossing changed expression.")
    game.reset_run()
    _check(game.current_expression_state == PROFILE.ExpressionState.NEUTRAL, "New run did not reset expression.")
    game.queue_free()
    await process_frame
    if _failures.is_empty():
        print("Character expression-request tests passed.")
        quit(0)
        return
    for failure in _failures:
        push_error(failure)
    quit(1)

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures.append(message)
