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
    _check(phase_one.pose_name == "sitting", "Phase 1 does not use the sitting pose fallback.")
    _check(phase_one.get_texture_path("overall_init") == "res://assets/art/character/sitting/complete.png", "Phase 1 fallback points to another pose.")
    _check(POSE_PROFILE.new(3).pose_name == "lying", "Phase 3 does not use the lying pose.")
    _check(POSE_PROFILE.new(4).pose_name == "prone", "Phase 4 does not use the prone pose.")
    _check(POSE_PROFILE.new(5).pose_name == "standing", "Phase 5 does not use the standing pose.")
    for phase in range(1, 6):
        var profile = POSE_PROFILE.new(phase)
        _check(profile.get_tail_frame_paths().size() == 3, "Phase %d tail is not mapped to three frames." % phase)
        for path in profile.get_tail_frame_paths():
            _check(ResourceLoader.exists(path), "Missing tail asset: %s" % path)
        _check(ResourceLoader.exists(profile.get_interaction_mask_path()), "Missing mask for phase %d." % phase)
        for track in profile.get_tentacle_part_paths() + profile.get_tail_tentacle_paths():
            _check(track.size() == 3, "Tentacle track in phase %d is incomplete." % phase)
            for path in track:
                _check(ResourceLoader.exists(path), "Missing tentacle asset: %s" % path)
    for entry in [[0.0, 0], [19.49, 0], [19.5, 1], [20.0, 1],
            [29.49, 1], [29.5, 2], [30.0, 2], [39.99, 2]]:
        _check(CONTROLLER.physical_score_to_sitting_tail_stage(entry[0]) == entry[1],
            "Incorrect sitting tail boundary at %s" % entry[0])
    var game = GAME_SCREEN.instantiate()
    root.add_child(game)
    await process_frame
    _check(game.tentacle_layer.z_index == game.pose_tail_layer.z_index,
        "Tail tentacles are not drawn directly over the matching tail.")
    _check(game.dialogue_panel.z_index >= game.tentacle_layer.z_index,
        "Dialogue is drawn below the tentacles.")
    _check(game.character_area.get_node("PromptLayer").z_index > game.tentacle_layer.z_index,
        "Physiological notes are drawn below the tentacles.")
    game.reset_run()
    _check(game.current_presentation_phase == 2, "Initial physiology 20 should use Phase 2.")
    game.arousal_model.physical = 0.0
    game._sync_physiological_visual_band()
    game._advance_tail_animation(0.1)
    _check(game._tail_frame_index == 0, "Score below 20 did not select the first sitting tail stage.")
    _check(game.current_presentation_phase == 2, "Physiology decay regressed the pose.")
    game.arousal_model.physical = 30.0
    game._advance_tail_animation(0.1)
    _check(game._tail_frame_index == 2, "Score 30 did not select the third sitting tail stage.")
    for step in range(30):
        game.tentacle_layer.advance(0.15)
        for track in game.tentacle_layer._tracks:
            _check(track["layer"].visible, "A normal tentacle disappeared while animating.")
        _check(game.tentacle_layer._tail_tracks[2]["layer"].visible,
            "The selected sitting tail tentacle disappeared while animating.")
    game.arousal_model.physical = 40.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 3, "Physiology 40 did not reach Phase 3.")
    _check(game.active_character_profile.pose_name == "lying", "Phase 3 did not show the lying pose.")
    game.arousal_model.physical = 80.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 5, "Physiology 80 did not reach Phase 5.")
    _check(game.active_character_profile.pose_name == "standing", "Phase 5 did not show the standing pose.")
    for step in range(18):
        game._advance_tail_animation(0.13)
        for track in game.tentacle_layer._tracks + game.tentacle_layer._tail_tracks:
            _check(track["layer"].visible, "A standing tentacle disappeared while animating.")
        for track in game.tentacle_layer._tail_tracks:
            _check(track["layer"].texture.resource_path.ends_with("_%d.png" % (game._tail_frame_index + 1)),
                "A standing tail tentacle frame lost sync with the base tail.")
    _check(game.active_character_profile.get_shooting_tail_path().ends_with("tail_shooting.png"), "Standing shooting tail is unavailable.")
    game.set_shooting_tail_active(true)
    _check(game.pose_tail_layer.texture != null, "Shooting tail was not displayed by the presentation API.")
    game.set_shooting_tail_active(false)
    var pose_texture: Texture2D = game.background_placeholder.texture
    var token: int = game.request_character_expression(CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL, PROFILE.ExpressionState.PSYCHOLOGICAL_POSITIVE)
    _check(game.resolve_character_visual_state().face_state_key == "face_psychological_positive", "Correct psychology choice did not select its happy face.")
    _check(game.background_placeholder.texture == pose_texture, "Psychology expression changed pose.")
    _check(game.phase_2_face_layer.texture != null, "Happy face art was not displayed.")
    game.clear_character_expression(CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL, token)
    _check(game.resolve_character_visual_state().face_state_key == "face_neutral", "Clearing psychology result did not restore neutral face.")
    _check(game._tail_frames.size() == 3, "Phase 5 tail does not have three frames.")
    _check(game.spot_manager._interaction_mask != null, "White mask was not supplied to note placement.")
    _check(game.background_placeholder.texture.resource_path != game.active_character_profile.get_interaction_mask_path(), "Mask was displayed as a normal pose layer.")
    game.arousal_model.physical = 0.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 5, "Phase 5 pose regressed after decay.")
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
