extends SceneTree

const GAME_SCREEN := preload("res://scenes/screens/GameScreen.tscn")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var output_dir := OS.get_user_data_dir().path_join("tentacle_review")
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
	quit()
