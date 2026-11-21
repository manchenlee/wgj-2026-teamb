extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const ROUTER_SCRIPT := preload("res://scripts/core/screen_router.gd")

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
	_assert(game.violin_audio != null, "Gameplay violin audio backend was not created.")
	_assert(game.violin_audio._clef_backend.is_available(), "Default gameplay launch did not load the bundled GeneralUser GS SF2.")
	_assert(game.spot_manager.click_audio_requested.is_connected(game.violin_audio.play_click), "Click audio route is missing.")
	_assert(game.spot_manager.slide_audio_requested.is_connected(game.violin_audio.play_slide_checkpoint), "Slide audio route is missing.")
	_assert(game.spot_manager.rub_audio_motion.is_connected(game.violin_audio.rub_motion), "Rub audio route is missing.")

	_assert(not requests.is_empty(), "Entering gameplay did not request a BGM track.")
	if not requests.is_empty():
		var initial_request: Dictionary = requests[0]
		_assert(
			initial_request.get("track_key") == "gameplay",
			"Entering gameplay did not request the piano BGM."
		)
		_assert(bool(initial_request.get("use_fade", false)), "Gameplay BGM did not request a fade.")
	_assert(game.has_switched_to_game_bgm, "Gameplay BGM state was not activated on entry.")
	_assert(game.last_requested_bgm_key == "gameplay", "Initial gameplay BGM state was not retained.")

	game.arousal_model.peak = 50.0
	game._update_bgm_state()
	_assert(requests.size() == 1, "Crossing the peak threshold changed the piano BGM.")

	var router = ROUTER_SCRIPT.new()
	router._setup_bgm_library()
	var gameplay_stream: AudioStream = router.bgm_library.get("gameplay")
	_assert(gameplay_stream is AudioStreamOggVorbis, "Gameplay BGM is not the piano OGG.")
	if gameplay_stream is AudioStreamOggVorbis:
		_assert((gameplay_stream as AudioStreamOggVorbis).loop, "Piano OGG loop is disabled.")
	_assert(router.bgm_library.get("default") is AudioStreamMP3, "Title BGM changed.")
	_assert(router.bgm_library.get("ending") is AudioStreamMP3, "Ending BGM changed.")
	_assert(router.violin_timeline.load_from_file("res://data/violin_timeline.json"), "Router could not load MIDI pitch data.")
	var player := AudioStreamPlayer.new()
	player.stream = gameplay_stream
	root.add_child(player)
	router.active_bgm_player = player
	router.current_bgm_key = "gameplay"
	player.play(2.5)
	await process_frame
	_assert(router.get_gameplay_midi_pitch() == 71, "Router pitch lookup did not use the live BGM position.")
	player.stop()
	_assert(router.get_gameplay_midi_pitch() == -1, "Router returned a pitch without active gameplay BGM.")
	player.queue_free()

	game.queue_free()
	router.free()
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
