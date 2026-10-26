extends SceneTree

const GAME_SCREEN := preload("res://scenes/screens/GameScreen.tscn")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var output_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join("tentacle_review")
	DirAccess.make_dir_recursive_absolute(output_dir)
	for score in [0.0, 20.0, 30.0, 40.0, 60.0, 80.0]:
		var game := GAME_SCREEN.instantiate()
		root.add_child(game)
		game.apply_debug_values(score)
		await process_frame
		await process_frame
		var file_path := output_dir.path_join("score_%02d.png" % int(score))
		var result := root.get_texture().get_image().save_png(file_path)
		print("Captured %s: %d" % [file_path, result])
		game.queue_free()
		await process_frame
	for frame in range(3):
		var game := GAME_SCREEN.instantiate()
		root.add_child(game)
		game.apply_debug_values(40.0)
		game.set_process(false)
		game._tail_frame_index = frame
		game._update_shooting_tail_layer()
		game.tentacle_layer.set_tail_index(frame)
		await process_frame
		await process_frame
		var frame_path := output_dir.path_join("lying_tail_frame_%d.png" % (frame + 1))
		var frame_result := root.get_texture().get_image().save_png(frame_path)
		print("Captured %s: %d" % [frame_path, frame_result])
		game.queue_free()
		await process_frame
	var game := GAME_SCREEN.instantiate()
	root.add_child(game)
	game.apply_debug_values(30.5)
	game.toggle_interaction_mode()
	var waist_anchor: Array[String] = ["Waist"]
	game.spot_manager.set_available_anchor_ids(waist_anchor)
	game.force_spawn_spot()
	await process_frame
	await process_frame
	var note_path := output_dir.path_join("physiological_note.png")
	var note_result := root.get_texture().get_image().save_png(note_path)
	print("Captured %s: %d" % [note_path, note_result])
	game.queue_free()
	quit()
