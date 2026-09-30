extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	var requests: Array[Dictionary] = []
	game.bgm_requested.connect(func(track_key: String, use_fade: bool) -> void:
		requests.append({"track_key": track_key, "use_fade": use_fade})
	)
	root.add_child(game)
	await process_frame

	_assert(not requests.is_empty(), "Entering gameplay did not request a BGM track.")
	if not requests.is_empty():
		var initial_request: Dictionary = requests[0]
		_assert(
			initial_request.get("track_key") == "overall_high",
			"Entering gameplay did not switch from the default BGM to overall_high."
		)
		_assert(bool(initial_request.get("use_fade", false)), "Gameplay BGM did not request a fade.")
	_assert(game.has_switched_to_game_bgm, "Gameplay BGM state was not activated on entry.")
	_assert(game.last_requested_bgm_key == "overall_high", "Initial gameplay BGM state was not retained.")

	game.arousal_model.peak = 50.0
	game._update_bgm_state()
	_assert(requests.size() == 2, "Crossing the peak BGM threshold did not request a second track.")
	if requests.size() == 2:
		_assert(requests[1].get("track_key") == "overall_low", "Peak threshold selected the wrong BGM.")

	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Game BGM headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
