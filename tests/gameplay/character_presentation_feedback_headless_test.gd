extends SceneTree

const GAME_SCREEN := preload("res://scenes/screens/GameScreen.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = GAME_SCREEN.instantiate()
	root.add_child(game)
	await process_frame
	var presenter: CharacterPresenter = game.character_area
	var art: Control = game.background_anchor
	var mask: Control = game.interaction_mask_anchor
	var prompt_layer: Control = presenter.prompt_layer
	var note := Control.new()
	note.position = Vector2(300.0, 240.0)
	prompt_layer.add_child(note)
	var art_rest := art.position
	var mask_position := mask.global_position
	var prompt_position := prompt_layer.global_position
	var note_position := note.global_position
	var alignment_position: Vector2 = game.character_alignment_root.position
	_check(mask.global_position.is_equal_approx(game.background_placeholder.global_position), "Mask reference is not aligned with the displayed sprite.")
	_check(mask.size.is_equal_approx(game.background_placeholder.size), "Mask reference size differs from the displayed sprite.")

	presenter.show_body_tremble(true)
	var good_peak := 0.0
	for i in range(2):
		await process_frame
		good_peak = maxf(good_peak, art.position.distance_to(art_rest))
		game._apply_character_alignment()
		_check(game.character_alignment_root.position.is_equal_approx(alignment_position), "Alignment absorbed a temporary tremble offset.")
	_check(good_peak > 0.1, "Good interaction did not move the art.")
	_check(mask.global_position.is_equal_approx(mask_position), "Good tremble moved the interaction mask.")
	_check(prompt_layer.global_position.is_equal_approx(prompt_position), "Good tremble moved the prompt layer.")
	_check(note.global_position.is_equal_approx(note_position), "Good tremble moved a physical note.")
	await create_timer(0.21).timeout
	_check(art.position.is_equal_approx(art_rest), "Good tremble did not settle at rest.")

	presenter.show_body_tremble(false)
	var bad_peak := 0.0
	for i in range(2):
		await process_frame
		bad_peak = maxf(bad_peak, art.position.distance_to(art_rest))
	_check(bad_peak > good_peak, "Bad interaction did not produce the stronger jolt.")
	_check(mask.global_position.is_equal_approx(mask_position), "Bad tremble moved the interaction mask.")
	_check(note.global_position.is_equal_approx(note_position), "Bad tremble moved a physical note.")
	await create_timer(0.18).timeout
	_check(art.position.is_equal_approx(art_rest), "Bad tremble did not settle at rest.")

	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Character presentation feedback headless test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
