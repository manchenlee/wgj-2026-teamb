extends SceneTree

const GAME_SESSION_CONTROLLER_SCRIPT := preload("res://scripts/core/game_session_controller.gd")

const EPSILON: float = 0.0001

var _failures: Array[String] = []


func _initialize() -> void:
	_test_boundaries()
	_test_crossing_behavior()
	if _failures.is_empty():
		print("Physiological visual-band headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_boundaries() -> void:
	var first_boundary := 100.0 / 6.0
	var second_boundary := 200.0 / 6.0
	var fourth_boundary := 400.0 / 6.0
	var fifth_boundary := 500.0 / 6.0
	var cases: Array = [
		[0.0, 0],
		[first_boundary - EPSILON, 0],
		[first_boundary, 1],
		[first_boundary + EPSILON, 1],
		[second_boundary - EPSILON, 1],
		[second_boundary, 2],
		[second_boundary + EPSILON, 2],
		[50.0 - EPSILON, 2],
		[50.0, 3],
		[50.0 + EPSILON, 3],
		[fourth_boundary, 4],
		[fifth_boundary, 5],
		[100.0, 5],
		[-1.0, 0],
		[101.0, 5],
	]
	for test_case in cases:
		var physical_score: float = test_case[0]
		var expected_band: int = test_case[1]
		var actual_band: int = GAME_SESSION_CONTROLLER_SCRIPT.physical_score_to_visual_band(physical_score)
		_assert(
			actual_band == expected_band,
			"Physical score %.6f resolved to band %d instead of %d." % [
				physical_score,
				actual_band,
				expected_band,
			]
		)


func _test_crossing_behavior() -> void:
	var controller = GAME_SESSION_CONTROLLER_SCRIPT.new()
	var crossings: Array = []
	controller.physiological_visual_band_changed.connect(
		func(previous_band: int, current_band: int, direction: int) -> void:
			crossings.append([previous_band, current_band, direction])
	)

	controller.arousal_model.physical = 20.0
	controller._sync_physiological_visual_band()
	_assert(controller.current_visual_band == 1, "Initialization cached the wrong visual band.")
	_assert(crossings.is_empty(), "Initialization emitted a false visual-band crossing.")

	controller.arousal_model.physical = 30.0
	controller._sync_physiological_visual_band()
	_assert(crossings.is_empty(), "A same-band score change emitted a crossing.")

	controller.arousal_model.physical = 50.0
	controller._sync_physiological_visual_band()
	_assert_crossing(crossings, 0, 1, 3, 1, "upward crossing")

	controller.arousal_model.physical = 49.0
	controller._sync_physiological_visual_band()
	_assert_crossing(crossings, 1, 3, 2, -1, "downward crossing")

	controller.arousal_model.physical = 50.01
	controller._sync_physiological_visual_band()
	controller.arousal_model.physical = 50.01
	controller.arousal_model.apply_decay(0.01)
	controller._sync_physiological_visual_band()
	_assert_crossing(crossings, 3, 3, 2, -1, "passive-decay-compatible downward crossing")

	controller.arousal_model.physical = 100.0
	controller._sync_physiological_visual_band()
	_assert_crossing(crossings, 4, 2, 5, 1, "large direct jump")
	_assert(crossings.size() == 5, "A large jump emitted intermediate or duplicate crossings.")

	controller.arousal_model.physical = 42.0
	controller._sync_physiological_visual_band(false)
	_assert(controller.current_visual_band == 2, "Reset-style synchronization cached the wrong band.")
	_assert(crossings.size() == 5, "Reset-style synchronization emitted a false crossing.")
	controller.arousal_model.reset()
	controller._sync_physiological_visual_band(false)
	var expected_reset_band: int = GAME_SESSION_CONTROLLER_SCRIPT.physical_score_to_visual_band(
		controller.arousal_model.physical
	)
	_assert(
		controller.current_visual_band == expected_reset_band,
		"Arousal reset and visual-band cache synchronization diverged."
	)
	_assert(crossings.size() == 5, "Arousal reset synchronization emitted a false crossing.")

	controller.free()


func _assert_crossing(
		crossings: Array,
		index: int,
		expected_previous: int,
		expected_current: int,
		expected_direction: int,
		label: String
) -> void:
	_assert(crossings.size() > index, "%s did not emit a crossing." % label)
	if crossings.size() <= index:
		return
	var crossing: Array = crossings[index]
	_assert(
		crossing == [expected_previous, expected_current, expected_direction],
		"%s emitted %s instead of [%d, %d, %d]." % [
			label,
			str(crossing),
			expected_previous,
			expected_current,
			expected_direction,
		]
	)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
