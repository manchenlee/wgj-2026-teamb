extends SceneTree

const GAME_SCREEN := preload("res://scenes/screens/GameScreen.tscn")
const PROFILE := preload("res://data/character_profiles/phase_character_profile.gd")
const POSE_PROFILE := preload("res://data/character_profiles/pose_character_profile.gd")
const CONTROLLER := preload("res://scripts/core/game_session_controller.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for phase in range(1, 5):
		var profile = POSE_PROFILE.new(phase)
		_check(profile.get_face_texture_paths().is_empty(), "Merged pose still loads a separate face layer: %d" % phase)
		_check(profile.get_texture_path("overall_init").ends_with("default.png"),
			"Default pose art is not used for the starting state: %d" % phase)
		var default_state: Dictionary = profile.resolve_visual_state(0, PROFILE.ExpressionState.NEUTRAL)
		_check(profile.get_texture_path(default_state.base_state_key) ==
			"res://assets/art/character/%s/default.png" % profile.pose_name,
			"Phase %d resolves its default state to another image." % phase)
		var default_path: String = profile.get_texture_path("overall_init")
		var imported_image: Image = (load(default_path) as Texture2D).get_image()
		var source_image: Image = Image.load_from_file(ProjectSettings.globalize_path(default_path))
		if phase == 2 or phase == 3:
			var neutral_image: Image = Image.load_from_file(ProjectSettings.globalize_path(
				"res://assets/art/character/%s/neutral.png" % profile.pose_name))
			var default_difference := _image_difference(imported_image, source_image)
			var neutral_difference := _image_difference(imported_image, neutral_image)
			_check(default_difference < neutral_difference,
				"Phase %d imports neutral art instead of default art." % phase)
		var neutral_path: String = "res://assets/art/character/%s/neutral.png" % profile.pose_name
		_check(ResourceLoader.exists(neutral_path), "Dialogue neutral art is missing: %s" % neutral_path)
		for expression in [PROFILE.ExpressionState.NEUTRAL, PROFILE.ExpressionState.POSITIVE,
				PROFILE.ExpressionState.PSYCHOLOGICAL_POSITIVE, PROFILE.ExpressionState.NEGATIVE]:
			var state: Dictionary = profile.resolve_visual_state(0, expression)
			var path: String = profile.get_texture_path(state.base_state_key)
			_check(state.face_state_key.is_empty(), "Merged pose has a face state: %d" % phase)
			_check(ResourceLoader.exists(path), "Merged image is missing: %s" % path)
	_check(POSE_PROFILE.new(4).get_texture_path("psychological_positive") ==
		"res://assets/art/character/lying/psychological_positive.png",
		"Lying psychological reaction does not use its dedicated image.")
	var game = GAME_SCREEN.instantiate()
	root.add_child(game)
	await process_frame
	game.current_presentation_phase = 1
	game.active_character_profile = null
	game._sync_character_presentation_phase_for_visual_band(0)
	_check(game.active_character_profile.pose_name == "sitting", "Phase 1 is not sitting.")
	_check(game.background_placeholder.texture == game.character_visual_textures["overall_init"],
		"Sitting default image was not displayed.")
	_check(game.background_placeholder.texture.resource_path.ends_with("/sitting/default.png"),
		"Sitting phase did not start with default.png.")
	_check(game.phase_2_face_layer.texture == null, "Sitting face layer is still visible.")
	_check_expression(game, PROFILE.ExpressionState.POSITIVE, "positive")
	_check_expression(game, PROFILE.ExpressionState.PSYCHOLOGICAL_POSITIVE, "psychological_positive")
	_check_expression(game, PROFILE.ExpressionState.NEGATIVE, "negative")

	game.arousal_model.physical = 25.0
	game._sync_physiological_visual_band()
	_check(game.active_character_profile.pose_name == "standing", "Phase 2 is not standing.")
	_check(game.background_placeholder.texture.resource_path.ends_with("/standing/default.png"),
		"Standing phase did not start with default.png.")
	_check_expression(game, PROFILE.ExpressionState.POSITIVE, "positive")
	_check_expression(game, PROFILE.ExpressionState.PSYCHOLOGICAL_POSITIVE, "psychological_positive")
	_check_expression(game, PROFILE.ExpressionState.NEGATIVE, "negative")

	game.arousal_model.physical = 50.0
	game._sync_physiological_visual_band()
	_check(game.active_character_profile.pose_name == "prone", "Phase 3 is not prone.")
	_check(game.background_placeholder.texture.resource_path.ends_with("/prone/default.png"),
		"Prone phase did not start with default.png.")
	_check_expression(game, PROFILE.ExpressionState.POSITIVE, "positive")
	_check_expression(game, PROFILE.ExpressionState.PSYCHOLOGICAL_POSITIVE, "psychological_positive")
	_check_expression(game, PROFILE.ExpressionState.NEGATIVE, "negative")

	game.arousal_model.physical = 80.0
	game._sync_physiological_visual_band()
	_check(game.active_character_profile.pose_name == "lying", "Phase 4 is not lying.")
	_check(game.background_placeholder.texture.resource_path.ends_with("/lying/default.png"),
		"Lying phase did not start with default.png.")
	_check_expression(game, PROFILE.ExpressionState.POSITIVE, "positive")
	_check_expression(game, PROFILE.ExpressionState.PSYCHOLOGICAL_POSITIVE, "psychological_positive")
	_check_expression(game, PROFILE.ExpressionState.NEGATIVE, "negative")
	_check(game.phase_2_face_layer.texture == null, "Lying face layer is still visible.")
	game.queue_free()
	await process_frame

	var ending_data := JSON.parse_string(FileAccess.get_file_as_string("res://assets/dialogue/endings.json")) as Dictionary
	for entry in ending_data.get("entries", {}).values():
		for step in entry.get("steps", []):
			var character: Dictionary = step.get("character", {})
			_check(character.get("base", "") == "res://assets/art/character/sitting/negative.png",
				"Ending dialogue does not use merged negative art.")
			_check(character.get("layers", []).is_empty(), "Ending dialogue still overlays a face.")
	if _failures.is_empty():
		print("Merged pose art tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _check_expression(game: Control, expression: int, texture_key: String) -> void:
	var token: int = game.request_character_expression(
		CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL, expression)
	_check(game.background_placeholder.texture == game.character_visual_textures.get(texture_key),
		"Merged expression was not displayed: %s" % texture_key)
	_check(game.phase_2_face_layer.texture == null, "Separate face was displayed: %s" % texture_key)
	game.clear_character_expression(CONTROLLER.CharacterExpressionSource.PSYCHOLOGICAL, token)
	_check(game.background_placeholder.texture == game.character_visual_textures["overall_init"],
		"Default image was not restored: %s" % texture_key)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _image_difference(left: Image, right: Image) -> float:
	var difference := 0.0
	for y in range(0, left.get_height(), 8):
		for x in range(0, left.get_width(), 8):
			var a: Color = left.get_pixel(x, y)
			var b: Color = right.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
	return difference
