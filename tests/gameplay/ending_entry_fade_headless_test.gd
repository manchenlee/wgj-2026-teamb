extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _check_fade(CONFIG.SUCCESS_ENDING, Color.WHITE)
	await _check_fade(CONFIG.EMOTIONAL_IMBALANCE_FAILURE_ENDING, Color.BLACK)
	if _failures.is_empty():
		print("Ending entry fade headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)

func _check_fade(ending_type: String, expected_color: Color) -> void:
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	main._show_ending(ending_type)
	var overlay: ColorRect = main.screen_transition_overlay
	_assert(main.current_screen_id == CONFIG.SCREEN_ENDING, "%s did not enter the ending screen." % ending_type)
	_assert(overlay.visible and is_equal_approx(overlay.color.a, 1.0),
		"%s did not start its entry fade fully covered." % ending_type)
	_assert(is_equal_approx(overlay.color.r, expected_color.r) \
			and is_equal_approx(overlay.color.g, expected_color.g) \
			and is_equal_approx(overlay.color.b, expected_color.b),
		"%s used the wrong entry fade color." % ending_type)
	await create_timer(0.25).timeout
	_assert(overlay.visible and overlay.color.a > 0.0 and overlay.color.a < 1.0,
		"%s did not gradually reveal the ending." % ending_type)
	await create_timer(0.4).timeout
	_assert(not overlay.visible and overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"%s left its entry overlay active." % ending_type)
	main.queue_free()
	await process_frame

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
