extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const PSYCHOLOGICAL_MODE := 0
const PHYSIOLOGICAL_MODE := 1

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame

	var mode_toggle: InteractionModeToggle = game.get_node("%InteractionModeToggle")
	var talk_button: TextureButton = mode_toggle.talk_button
	var music_button: TextureButton = mode_toggle.music_button
	var talk_warning_badge: TextureRect = mode_toggle.talk_warning_badge
	var music_warning_badge: TextureRect = mode_toggle.music_warning_badge
	var shortcut_group: Control = mode_toggle.get_node("ShortcutGroup")
	var q_diamond: Panel = mode_toggle.get_node("ShortcutGroup/ShortcutLabel")
	var hint_position := shortcut_group.position
	var q_event := InputEventAction.new()
	q_event.action = &"toggle_interaction_mode"
	q_event.pressed = true

	_check(game.interaction_mode == PHYSIOLOGICAL_MODE, "Game did not begin in physiological mode.")
	_check(talk_button.visible and music_button.visible, "Both carousel modes must remain visible.")
	_check(music_button.size.x > talk_button.size.x and music_button.position.y < talk_button.position.y, "Physiological mode must be the large upper item.")
	_check(is_equal_approx(talk_button.size.x, 47.0) and is_equal_approx(talk_button.size.y, 47.0), "Inactive dialogue icon must be twice its previous width and height.")
	_check(talk_button.texture_normal == InteractionModeToggle.TALK_ICON and music_button.texture_normal == InteractionModeToggle.MUSIC_CLICKED, "Inactive dialogue must show the new icon while active tuning keeps its labeled art.")
	_check(not talk_warning_badge.visible and not music_warning_badge.visible, "Warning badges must start hidden.")
	_check(shortcut_group.visible and not mode_toggle.has_node("ShortcutGroup/SwitchHint"), "The old arrow hint must be removed.")
	_check(is_equal_approx(q_diamond.rotation, PI / 4.0), "Q key indicator must be diamond shaped.")
	_check_q_layout(shortcut_group, music_button, talk_button)
	mode_toggle.set_imbalance_warning(true, PSYCHOLOGICAL_MODE)
	_check(talk_button.texture_normal == InteractionModeToggle.TALK_ICON and talk_warning_badge.visible and mode_toggle.is_processing(), "Lower inactive dialogue must keep its icon and show the blinking badge.")
	mode_toggle.set_imbalance_warning(true, PHYSIOLOGICAL_MODE)
	_check(music_button.texture_normal == InteractionModeToggle.MUSIC_WARNING and not music_warning_badge.visible and mode_toggle.is_processing(), "Lower active tuning must keep its existing warning art.")
	_check(talk_button.texture_normal == InteractionModeToggle.TALK_ICON and not talk_warning_badge.visible, "Active mode warning must not affect the opposite icon.")

	game._unhandled_input(q_event)
	_check(game.interaction_mode == PSYCHOLOGICAL_MODE, "Q did not switch to dialogue mode.")
	_check(music_button.visible and talk_button.visible and mode_toggle._slide_tween.is_running(), "Q must animate both carousel items.")
	_check(music_button.texture_normal == InteractionModeToggle.MUSIC_ICON and music_warning_badge.visible and mode_toggle.is_processing(), "Lower inactive tuning must show its icon and retain the warning badge after switching.")
	await create_timer(InteractionModeToggle.SLIDE_DURATION + 0.05).timeout
	_check(talk_button.size.x > music_button.size.x and talk_button.position.y < music_button.position.y, "Q did not slide dialogue into the large upper slot.")
	_check(music_button.size == InteractionModeToggle.INACTIVE_SIZE, "Inactive tuning icon must use the same doubled slot.")
	_check_q_layout(shortcut_group, talk_button, music_button)
	_check(shortcut_group.visible and shortcut_group.position == hint_position, "Q hint changed after Q input.")
	mode_toggle.set_imbalance_warning(false, -1)
	_check(music_button.texture_normal == InteractionModeToggle.MUSIC_ICON and not music_warning_badge.visible and not mode_toggle.is_processing(), "Clearing imbalance must restore the plain tuning icon.")

	music_button.emit_signal("pressed")
	_check(game.interaction_mode == PHYSIOLOGICAL_MODE, "Clicking physiological UI did not switch to physiological mode.")
	await create_timer(InteractionModeToggle.SLIDE_DURATION + 0.05).timeout
	_check(music_button.size.x > talk_button.size.x, "Click did not restore the physiological upper slot.")
	_check(talk_button.texture_normal == InteractionModeToggle.TALK_ICON, "Inactive dialogue did not return to its icon.")
	_check_q_layout(shortcut_group, music_button, talk_button)
	_check(shortcut_group.visible and shortcut_group.position == hint_position, "Q hint changed after clicking.")

	talk_button.emit_signal("pressed")
	_check(game.interaction_mode == PSYCHOLOGICAL_MODE, "Clicking psychological UI did not switch to psychological mode.")
	await create_timer(InteractionModeToggle.SLIDE_DURATION + 0.05).timeout
	_check(talk_button.size.x > music_button.size.x, "Click did not restore the psychological upper slot.")
	_check(music_button.texture_normal == InteractionModeToggle.MUSIC_ICON, "Inactive tuning did not return to its icon.")
	mode_toggle.set_imbalance_warning(true, PSYCHOLOGICAL_MODE)
	_check(talk_button.texture_normal == InteractionModeToggle.TALK_WARNING and not talk_warning_badge.visible, "Active dialogue must use its existing warning art.")
	mode_toggle.set_imbalance_warning(true, PHYSIOLOGICAL_MODE)
	_check(music_button.texture_normal == InteractionModeToggle.MUSIC_ICON and music_warning_badge.visible, "Inactive tuning must retain its warning badge.")

	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Interaction mode toggle headless test passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_q_layout(q_hint: Control, active_icon: TextureButton, inactive_icon: TextureButton) -> void:
	var active_bottom: float = active_icon.position.y + active_icon.size.y
	var inactive_top: float = inactive_icon.position.y
	var q_center: Vector2 = q_hint.position + q_hint.size * 0.5
	_check(inactive_top - active_bottom <= 12.0 and inactive_top > active_bottom, "Mode diamonds must have a compact vertical gap.")
	_check(q_hint.size.x >= 52.0, "Q diamond must remain visible.")
	_check(is_equal_approx(inactive_icon.position.x + inactive_icon.size.x * 0.5, active_icon.position.x + active_icon.size.x * 0.5), "Inactive icon must remain horizontally aligned with the active icon.")
	_check(is_equal_approx(q_center.y, (active_bottom + inactive_top) * 0.5), "Q diamond must align with the vertical gap midpoint.")
	_check(q_center.x > active_icon.position.x + active_icon.size.x, "Q diamond must sit to the right of the facing mode corners.")
