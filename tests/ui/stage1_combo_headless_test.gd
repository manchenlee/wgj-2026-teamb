extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const HUD_SCENE := preload("res://scenes/components/StatusHUD.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_hud_layout_and_pulse()
	await _test_mode_visibility_and_combo_preservation()
	if _failures.is_empty():
		print("Stage 1 combo headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _test_hud_layout_and_pulse() -> void:
	var hud = HUD_SCENE.instantiate()
	root.add_child(hud)
	await process_frame
	var combo: Label = hud.get_node("ComboLabel")
	var emotional_track: ColorRect = hud.get_node("EmotionalBar/Track")
	_assert(combo.position.y >= emotional_track.position.y + emotional_track.size.y, "Combo overlaps the emotional bar.")
	_assert(combo.get_theme_font_size("font_size") == 56, "Combo font size differs from the game HUD.")
	_assert(combo.get_theme_constant("outline_size") == 6, "Combo white outline is not thick enough.")
	hud.update_combo(2, true)
	_assert(combo.visible and hud._combo_pulse_tween != null, "Physical combo did not appear and pulse.")
	hud.set_physical_mode_active(false)
	_assert(not combo.visible and hud._combo_pulse_tween == null, "Psychological mode did not stop the combo pulse.")
	hud.update_combo(3, true)
	_assert(not combo.visible and combo.text == "3 COMBO", "Hidden combo lost its value.")
	hud.set_physical_mode_active(true)
	_assert(combo.visible and combo.text == "3 COMBO", "Physical mode did not restore the combo.")
	for width in [1050.0, 1300.0]:
		hud.size.x = width
		await process_frame
		_assert(is_equal_approx(combo.position.x + combo.size.x, width + 280.0), "Combo is not right aligned at HUD width %s." % width)
		_assert(combo.position.x > width * 0.65, "Combo is too close to the character area at HUD width %s." % width)
	hud.queue_free()
	await process_frame

func _test_mode_visibility_and_combo_preservation() -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	var combo: Label = game.get_node("%StatusHUD/ComboLabel")
	_assert(not combo.visible, "Combo was visible at game start in psychological mode.")
	game.set_interaction_mode(1)
	game._on_physiological_spot_completed()
	game._on_physiological_spot_completed()
	_assert(game.current_combo == 2 and combo.visible, "Physical combo did not reach the HUD.")
	game.set_interaction_mode(0)
	_assert(game.current_combo == 2 and not combo.visible, "Mode switch changed or exposed the combo.")
	game.set_interaction_mode(1)
	_assert(game.current_combo == 2 and combo.visible, "Physical mode did not restore the retained combo.")
	game.size = Vector2(1600.0, 1024.0)
	await process_frame
	var hud: Control = game.get_node("%StatusHUD")
	_assert(is_equal_approx(hud.global_position.x, game.global_position.x), "Status HUD is not aligned with the left edge.")
	_assert(is_equal_approx(combo.global_position.x + combo.size.x, hud.global_position.x + hud.size.x + 280.0), "Combo did not stay right aligned after viewport resize.")
	game._stop_runtime_timers()
	game.queue_free()
	await process_frame

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
