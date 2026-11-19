extends SceneTree

const OPENING_SCENE := preload("res://scenes/screens/OpeningScreen.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _check_interlude("r8", "r9", "r10", true)
	await _check_interlude("r24", "r25", "r26", false)
	var finale := OPENING_SCENE.instantiate()
	finale.start_step_id = "r66"
	root.add_child(finale)
	await process_frame
	await create_timer(0.5).timeout
	_check(finale.opening_tentacles.visible and finale.opening_tentacles.modulate.a > 0.99, "Final cue must fade in the tentacles.")
	var game_requests := [0]
	finale.game_requested.connect(func() -> void: game_requests[0] += 1)
	finale.dialogue_bubble.finish_dialogue_stream()
	finale.advance_input_handled()
	await create_timer(0.22).timeout
	_check(finale.modulate.a > 0.0 and finale.modulate.a < 1.0, "Final fade must include the whole opening screen.")
	_check(finale.opening_tentacles.visible and finale.dialogue_bubble.visible, "Tentacles and dialogue must remain in the shared fade.")
	_check(game_requests[0] == 0, "Game must wait for the final fade.")
	await create_timer(0.3).timeout
	_check(finale.modulate.a < 0.01 and game_requests[0] == 1, "Game must start after the shared fade.")
	finale.queue_free()
	await process_frame
	if failures.is_empty():
		print("Opening tentacles headless test passed.")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _check_interlude(line_id: String, cue_id: String, next_id: String, check_violin: bool) -> void:
	var opening := OPENING_SCENE.instantiate()
	opening.start_step_id = line_id
	root.add_child(opening)
	await process_frame
	_check(opening.character_stage.z_index < opening.opening_tentacles.z_index and opening.opening_tentacles.z_index < opening.get_node("DialogueUi").z_index, "Tentacles must appear between the character and dialogue UI.")
	var character_position: Vector2 = opening.character_root.position
	var character_texture: Texture2D = opening._base_sprite.texture
	await create_timer(opening.dialogue_bubble.get_stream_duration() + 0.1).timeout
	_check(_step_id(opening) == line_id and opening.dialogue_bubble.visible, "%s must wait for the player's click." % line_id)
	opening.advance_input_handled()
	_check(_step_id(opening) == cue_id, "Clicking %s must start %s." % [line_id, cue_id])
	await create_timer(0.25).timeout
	_check(not opening.dialogue_bubble.visible and opening.opening_tentacles.visible, "%s must hide dialogue and show tentacles." % cue_id)
	if check_violin:
		_check(opening.character_root.position == character_position and opening._base_sprite.texture == character_texture, "Normal violin moved or changed while tentacles appeared.")
	opening.advance_input_handled()
	_check(_step_id(opening) == cue_id, "Input must not interrupt %s." % cue_id)
	await create_timer(1.05).timeout
	_check(_step_id(opening) == next_id and opening.dialogue_bubble.visible, "%s must automatically show the next dialogue." % cue_id)
	await create_timer(0.5).timeout
	_check(not opening.opening_tentacles.visible, "Tentacles must fade out when %s appears." % next_id)
	opening.queue_free()
	await process_frame

func _step_id(opening: Control) -> String:
	return str(opening._entries[opening._current_entry_index].id)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
