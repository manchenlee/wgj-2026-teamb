extends SceneTree

const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = GAME_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	for score in [25.0, 49.0]:
		game.arousal_model.physical = score
		game._sync_physiological_visual_band()
		game._track_safe_word_threshold()
		if game._safe_word_threshold_reached or game._safe_word_pending:
			_failures.append("Safe word triggered at physical %s." % score)
	if game.current_presentation_phase != 2:
		_failures.append("Physical 25-49 did not use the standing pose.")
	game.arousal_model.physical = 50.0
	game._track_safe_word_threshold()
	if not game._safe_word_threshold_reached or not game._safe_word_pending:
		_failures.append("Safe word did not queue at physical 50.")
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Safe-word threshold tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
