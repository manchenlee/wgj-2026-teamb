extends SceneTree

const GAME_SCREEN := preload("res://scenes/screens/GameScreen.tscn")
const CONTROLLER := preload("res://scripts/core/game_session_controller.gd")
const PROFILE := preload("res://data/character_profiles/phase_character_profile.gd")
const POSE_PROFILE := preload("res://data/character_profiles/pose_character_profile.gd")

var _failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var boundaries := [[-1.0, 0], [0.0, 0], [24.999, 0], [25.0, 1], [49.999, 1], [50.0, 2], [74.999, 2], [75.0, 3], [100.0, 3], [101.0, 3]]
    for entry in boundaries:
        _check(CONTROLLER.physical_score_to_visual_band(entry[0]) == entry[1], "Incorrect boundary at %s" % entry[0])
    var phase_one = POSE_PROFILE.new(1)
    _check(phase_one.pose_name == "sitting", "Phase 1 does not use the sitting pose fallback.")
    _check(phase_one.get_texture_path("overall_init") == "res://assets/art/character/sitting/default.png", "Phase 1 fallback points to another pose.")
    _check(phase_one.get_face_texture_paths().is_empty(), "Sitting still loads a separate face.")
    _check(POSE_PROFILE.new(2).pose_name == "standing", "Phase 2 does not use the standing pose.")
    _check(POSE_PROFILE.new(2).get_texture_path("overall_init") == "res://assets/art/character/standing/default.png", "Phase 2 loads the wrong character art.")
    _check(POSE_PROFILE.new(2).get_face_texture_paths().is_empty(), "Standing still loads a separate face.")
    _check(POSE_PROFILE.new(3).pose_name == "prone", "Phase 3 does not use the prone pose.")
    _check(POSE_PROFILE.new(3).get_texture_path("overall_init") == "res://assets/art/character/prone/default.png", "Phase 3 loads the wrong character art.")
    _check(POSE_PROFILE.new(3).get_face_texture_paths().is_empty(), "Prone still loads a separate face.")
    _check(POSE_PROFILE.new(4).pose_name == "lying", "Phase 4 does not use the lying pose.")
    _check(POSE_PROFILE.new(4).get_texture_path("overall_init") == "res://assets/art/character/lying/default.png", "Phase 4 loads the wrong character art.")
    _check(POSE_PROFILE.new(4).get_face_texture_paths().is_empty(), "Lying still loads a separate face.")
    for phase in [1]:
        var sitting_profile = POSE_PROFILE.new(phase)
        for index in range(3):
            var tail_number: int = [2, 1, 3][index]
            _check(sitting_profile.get_tail_frame_paths()[index].ends_with("tail_%d.png" % tail_number), "Phase %d uses the wrong tail at stage %d." % [phase, index])
            _check(sitting_profile.get_tail_tentacle_paths()[index][0].ends_with("tail_%d_1.png" % tail_number), "Phase %d uses the wrong tail tentacle at stage %d." % [phase, index])
    for phase in range(1, 5):
        var profile = POSE_PROFILE.new(phase)
        _check(profile.get_tail_frame_paths().size() == 3, "Phase %d tail is not mapped to three frames." % phase)
        for path in profile.get_tail_frame_paths():
            _check(ResourceLoader.exists(path), "Missing tail asset: %s" % path)
        _check(ResourceLoader.exists(profile.get_interaction_mask_path()), "Missing mask for phase %d." % phase)
        for track in profile.get_tentacle_part_paths() + profile.get_tail_tentacle_paths():
            _check(track.size() == 3, "Tentacle track in phase %d is incomplete." % phase)
            for path in track:
                _check(ResourceLoader.exists(path), "Missing tentacle asset: %s" % path)
    for entry in [[0.0, 0], [14.49, 0], [14.5, 1], [15.0, 1],
            [19.49, 1], [19.5, 2], [20.0, 2], [24.99, 2]]:
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
    game.current_presentation_phase = 1
    game.active_character_profile = null
    game._sync_character_presentation_phase_for_visual_band(0)
    _check(game.current_presentation_phase == 1, "Visual band 0 should use Phase 1.")
    game.arousal_model.physical = 0.0
    game._sync_physiological_visual_band()
    game._advance_tail_animation(0.1)
    _check(game._tail_frame_index == 0, "Score below 15 did not select the first sitting tail stage.")
    _check(game.pose_tail_layer.texture.resource_path.ends_with("tail_2.png"), "Score below 15 did not show tail_2.")
    _check(game.tentacle_layer._tail_tracks[0]["layer"].texture.resource_path.contains("tail_2_"), "Score below 15 did not show the tail_2 tentacle.")
    _check(game.current_presentation_phase == 1, "Physiology decay regressed the pose.")
    game.arousal_model.physical = 15.0
    game._advance_tail_animation(0.1)
    _check(game.pose_tail_layer.texture.resource_path.ends_with("tail_1.png"), "Score 15 did not show tail_1.")
    _check(game.tentacle_layer._tail_tracks[1]["layer"].texture.resource_path.contains("tail_1_"), "Score 15 did not show the tail_1 tentacle.")
    game.arousal_model.physical = 20.0
    game._advance_tail_animation(0.1)
    _check(game._tail_frame_index == 2, "Score 20 did not select the third sitting tail stage.")
    _check(game.pose_tail_layer.texture.resource_path.ends_with("tail_3.png"), "Score 20 did not show tail_3.")
    _check(game.tentacle_layer._tail_tracks[2]["layer"].texture.resource_path.contains("tail_3_"), "Score 20 did not show the tail_3 tentacle.")
    for step in range(30):
        game.tentacle_layer.advance(0.15)
        for track in game.tentacle_layer._tracks:
            _check(track["layer"].visible, "A normal tentacle disappeared while animating.")
        _check(game.tentacle_layer._tail_tracks[2]["layer"].visible,
            "The selected sitting tail tentacle disappeared while animating.")
    game.arousal_model.physical = 25.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 2, "Physiology 25 did not reach Phase 2.")
    _check(game.active_character_profile.pose_name == "standing", "Phase 2 did not show the standing pose.")
    _check(game.resolve_character_visual_state().base_state_key == "overall_init", "Phase 2 did not select the default art.")
    _check(game.phase_2_face_layer.texture == null, "Phase 2 still displays a separate face.")
    _check(game.tentacle_layer._tracks.size() == 4, "Phase 2 did not load its standing tentacles.")
    _check(game.tentacle_layer._tail_tracks.is_empty(), "Phase 2 loaded the lying tail tentacles.")
    game.arousal_model.physical = 50.0
    game._sync_physiological_visual_band()
    _check(game.active_character_profile.pose_name == "prone", "Phase 3 did not show the prone pose.")
    _check(game.resolve_character_visual_state().base_state_key == "overall_init", "Phase 3 did not select the default art.")
    _check(game.phase_2_face_layer.texture == null, "Phase 3 still displays a separate face.")
    game.arousal_model.physical = 75.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 4, "Physiology 75 did not reach Phase 4.")
    _check(game.active_character_profile.pose_name == "lying", "Phase 4 did not show the lying pose.")
    _check(game.tentacle_layer._tracks.size() == 4, "Phase 4 did not load its lying tentacles.")
    _check(game.tentacle_layer._tail_tracks.size() == 3, "Phase 4 did not load its lying tail tentacles.")
    for step in range(18):
        game._advance_tail_animation(0.13)
        for track in game.tentacle_layer._tracks + game.tentacle_layer._tail_tracks:
            _check(track["layer"].visible, "A lying tentacle disappeared while animating.")
        for track in game.tentacle_layer._tail_tracks:
            _check(track["layer"].texture.resource_path.ends_with("_%d.png" % (game._tail_frame_index + 1)),
                "A lying tail tentacle frame lost sync with the base tail.")
    _check(game.active_character_profile.get_shooting_tail_path().ends_with("tail_shooting.png"), "Lying shooting tail is unavailable.")
    game.set_shooting_tail_active(true)
    _check(game.pose_tail_layer.texture != null, "Shooting tail was not displayed by the presentation API.")
    game.set_shooting_tail_active(false)
    var pose_texture: Texture2D = game.background_placeholder.texture
    var token: int = game.request_character_expression(CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL, PROFILE.ExpressionState.PSYCHOLOGICAL_POSITIVE)
    _check(game.resolve_character_visual_state().base_state_key == "psychological_positive", "Correct psychology choice did not select its happy art.")
    _check(game.background_placeholder.texture != pose_texture, "Psychology expression did not change the merged image.")
    _check(game.phase_2_face_layer.texture == null, "Lying still displays a separate face.")
    game.clear_character_expression(CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL, token)
    _check(game.resolve_character_visual_state().base_state_key == "overall_init", "Clearing psychology result did not restore neutral art.")
    _check(game._tail_frames.size() == 3, "Phase 4 tail does not have three frames.")
    _check(game.spot_manager._interaction_mask != null, "White mask was not supplied to note placement.")
    _check(game.background_placeholder.texture.resource_path != game.active_character_profile.get_interaction_mask_path(), "Mask was displayed as a normal pose layer.")
    game.arousal_model.physical = 0.0
    game._sync_physiological_visual_band()
    _check(game.current_presentation_phase == 4, "Phase 4 pose regressed after decay.")
    game.reset_run()
    _check(game.current_presentation_phase == 1, "New run did not reset progression to its starting physiology.")
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
