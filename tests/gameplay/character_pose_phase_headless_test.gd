extends SceneTree

const GAME_SCREEN := preload("res://scenes/screens/GameScreen.tscn")
const CONTROLLER := preload("res://scripts/core/game_session_controller.gd")
const PROFILE := preload("res://data/character_profiles/phase_character_profile.gd")
const POSE_PROFILE := preload("res://data/character_profiles/pose_character_profile.gd")

var _failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var boundaries := [[-1.0, 0], [0.0, 0], [19.999, 0], [20.0, 1], [39.999, 1], [40.0, 2], [59.999, 2], [60.0, 3], [79.999, 3], [80.0, 4], [100.0, 4], [101.0, 4]]
    for entry in boundaries:
        _check(CONTROLLER.physical_score_to_visual_band(entry[0]) == entry[1], "Incorrect boundary at %s" % entry[0])
    var phase_one = POSE_PROFILE.new(1)
    _check(phase_one.asset_phase == 2, "Phase 1 does not use the explicit Phase 2 asset fallback.")
    _check(phase_one.get_texture_path("overall_init") == "res://assets/art/character/phase2/complete.png", "Phase 1 fallback points to another pose.")
    for phase in range(1, 6):
        var profile = POSE_PROFILE.new(phase)
        _check(profile.get_tail_frame_paths().size() == 3, "Phase %d tail is not mapped to three frames." % phase)
        for path in profile.get_tail_frame_paths():
            _check(ResourceLoader.exists(path), "Missing tail asset: %s" % path)
        _check(ResourceLoader.exists(profile.get_interaction_mask_path()), "Missing mask for phase %d." % phase)
    var game = GAME_SCREEN.instantiate()
    root.add_child(game)
    await process_frame
    game.reset_run()
    _check(game.current_presentation_phase == 2, "Initial physiology 20 should use Phase 2.")
    game.arousal_model.physical = 0.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 2, "Physiology decay regressed the pose.")
    game.arousal_model.physical = 40.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 3, "Physiology 40 did not reach lying pose.")
    _check(game.active_character_profile.get_shooting_tail_path().ends_with("tail_shooting.png"), "Lying shooting tail is unavailable.")
    game.set_shooting_tail_active(true)
    _check(game.pose_tail_layer.texture != null, "Shooting tail was not displayed by the presentation API.")
    game.set_shooting_tail_active(false)
    var pose_texture: Texture2D = game.background_placeholder.texture
    var token: int = game.request_character_expression(CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL, PROFILE.ExpressionState.POSITIVE)
    _check(game.resolve_character_visual_state().face_state_key == "face_positive", "Correct psychology choice did not select happy face.")
    _check(game.background_placeholder.texture == pose_texture, "Psychology expression changed pose.")
    _check(game.phase_2_face_layer.texture != null, "Happy face art was not displayed.")
    game.clear_character_expression(CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL, token)
    _check(game.resolve_character_visual_state().face_state_key == "face_neutral", "Clearing psychology result did not restore neutral face.")
    game.arousal_model.physical = 80.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 5, "Physiology 80 did not reach standing pose.")
    _check(game._tail_frames.size() == 3, "Standing tail does not have three frames.")
    _check(game.spot_manager._interaction_mask != null, "White mask was not supplied to note placement.")
    _check(game.background_placeholder.texture.resource_path != game.active_character_profile.get_interaction_mask_path(), "Mask was displayed as a normal pose layer.")
    game.arousal_model.physical = 0.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 5, "Standing pose regressed after decay.")
    game.reset_run()
    _check(game.current_presentation_phase == 2, "New run did not reset progression to its starting physiology.")
    game.queue_free()
    await process_frame
    if _failures.is_empty():
        print("Character pose phase tests passed.")
        quit(0)
    else:
        for failure in _failures:
            push_error(failure)
        quit(1)

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures.append(message)
