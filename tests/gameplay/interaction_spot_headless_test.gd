extends SceneTree

const SPOT_SCENE := preload("res://scenes/components/InteractionSpot.tscn")
const SPOT_MANAGER_SCRIPT := preload("res://scripts/gameplay/interaction_spot_manager.gd")
var test_points := PackedVector2Array([
	Vector2(100.0, 100.0),
	Vector2(220.0, 100.0),
	Vector2(220.0, 220.0),
	Vector2(100.0, 220.0),
])

var _failures: Array[String] = []


class FakeArousalModel:
	extends RefCounted
	var physical: float = 40.0
	var refresh_count: int = 0

	func apply_physical(delta: float) -> void:
		physical += delta

	func refresh_physical_activity() -> void:
		refresh_count += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_ordered_progression_and_fast_crossing()
	await _test_suspend_resume_requires_fresh_crossing()
	await _test_timeout_resolves_once()
	await _test_force_resolution_resolves_once()
	await _test_manager_scoring_and_failure_boundary()
	if _failures.is_empty():
		print("InteractionSpot headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _make_spot(lifetime: float = 30.0) -> InteractionSpot:
	var spot := SPOT_SCENE.instantiate() as InteractionSpot
	spot.setup({
		"spot_lifetime": lifetime,
		"checkpoint_radius": 40.0,
		"checkpoints": test_points,
	})
	root.add_child(spot)
	return spot


func _test_ordered_progression_and_fast_crossing() -> void:
	var spot := _make_spot()
	var counts := {"progress": 0, "completed": 0}
	spot.progressed.connect(func(_delta: float) -> void: counts.progress += 1)
	spot.completed.connect(func() -> void: counts.completed += 1)

	# Passing through a future checkpoint before the start must do nothing.
	spot._process_pointer_move(Vector2(300.0, 220.0))
	spot._process_pointer_move(Vector2(180.0, 220.0))
	_assert(not spot.is_armed(), "A future checkpoint armed the interaction.")

	# Cross the start. It arms but grants no progress.
	spot._process_pointer_move(Vector2(20.0, 100.0))
	spot._process_pointer_move(Vector2(180.0, 100.0))
	_assert(spot.is_armed(), "Crossing the start did not arm the interaction.")
	_assert(counts.progress == 0, "The start marker granted physiological progress.")

	# One long event crosses checkpoints 1 and 2, but may advance only checkpoint 1.
	spot._process_pointer_move(Vector2(220.0, 20.0))
	spot._process_pointer_move(Vector2(220.0, 300.0))
	_assert(counts.progress == 1, "One motion event advanced more than one checkpoint.")
	_assert(spot.get_next_checkpoint_index() == 2, "Checkpoint 1 did not select checkpoint 2.")

	# Crossing checkpoint 3 out of order must not advance checkpoint 2.
	spot._process_pointer_move(Vector2(20.0, 300.0))
	spot._process_pointer_move(Vector2(20.0, 220.0))
	spot._process_pointer_move(Vector2(140.0, 220.0))
	_assert(counts.progress == 1, "Checkpoint 3 advanced before checkpoint 2.")

	# Fast crossings count even though both endpoints are outside the circle.
	spot._process_pointer_move(Vector2(220.0, 140.0))
	spot._process_pointer_move(Vector2(220.0, 300.0))
	_assert(counts.progress == 2, "Fast segment crossing checkpoint 2 was missed.")
	spot._process_pointer_move(Vector2(20.0, 300.0))
	spot._process_pointer_move(Vector2(20.0, 220.0))
	spot._process_pointer_move(Vector2(180.0, 220.0))
	_assert(counts.progress == 3, "Checkpoint 3 did not grant final progress.")
	_assert(counts.completed == 1, "Completing checkpoint 3 did not resolve success once.")
	spot.force_complete()
	_assert(counts.completed == 1, "Resolved success emitted more than once.")
	spot.queue_free()
	await process_frame


func _test_suspend_resume_requires_fresh_crossing() -> void:
	var spot := _make_spot()
	var counts := {"progress": 0}
	spot.progressed.connect(func(_delta: float) -> void: counts.progress += 1)
	spot._process_pointer_move(Vector2(20.0, 100.0))
	spot._process_pointer_move(Vector2(180.0, 100.0))
	spot._process_pointer_move(Vector2(220.0, 20.0))
	spot._process_pointer_move(Vector2(220.0, 180.0))
	_assert(counts.progress == 1, "Suspend test could not establish checkpoint 1 progress.")

	spot.set_suspended(true)
	var paused_time_left := spot.lifetime_timer.time_left
	spot._process_pointer_move(Vector2(220.0, 300.0))
	await create_timer(0.1).timeout
	_assert(counts.progress == 1, "Mouse movement while suspended granted progress.")
	_assert(absf(spot.lifetime_timer.time_left - paused_time_left) < 0.02, "Lifetime advanced while suspended.")

	spot.set_suspended(false)
	spot._process_pointer_move(Vector2(220.0, 220.0))
	spot._process_pointer_move(Vector2(225.0, 220.0))
	_assert(counts.progress == 1, "Resume or inside-target jitter granted progress.")
	spot._process_pointer_move(Vector2(300.0, 220.0))
	spot._process_pointer_move(Vector2(180.0, 220.0))
	_assert(counts.progress == 2, "A fresh crossing after resume did not continue progress.")
	spot.queue_free()
	await process_frame


func _test_timeout_resolves_once() -> void:
	var spot := _make_spot(0.05)
	var counts := {"expired": 0}
	spot.expired.connect(func(_ratio: float) -> void: counts.expired += 1)
	await create_timer(0.12).timeout
	_assert(counts.expired == 1, "Timeout did not resolve failure exactly once.")
	spot.force_expire()
	_assert(counts.expired == 1, "Resolved timeout emitted more than once.")
	spot.queue_free()
	await process_frame


func _test_force_resolution_resolves_once() -> void:
	var completed_spot := _make_spot()
	var completed_counts := {"completed": 0}
	completed_spot.completed.connect(func() -> void: completed_counts.completed += 1)
	completed_spot.force_complete()
	completed_spot.force_complete()
	_assert(completed_counts.completed == 1, "Force complete did not resolve the node exactly once.")
	completed_spot.queue_free()
	await process_frame

	var expired_spot := _make_spot()
	var expired_counts := {"expired": 0}
	expired_spot.expired.connect(func(_ratio: float) -> void: expired_counts.expired += 1)
	expired_spot.force_expire()
	expired_spot.force_expire()
	_assert(expired_counts.expired == 1, "Force expire did not resolve the node exactly once.")
	expired_spot.queue_free()
	await process_frame


func _test_manager_scoring_and_failure_boundary() -> void:
	var scoring_manager := SPOT_MANAGER_SCRIPT.new()
	var scoring_model := FakeArousalModel.new()
	scoring_manager._arousal_model = scoring_model
	var spot := _make_spot()
	scoring_manager._on_spot_progressed(1.0 / 3.0, spot)
	scoring_manager._on_spot_completed(spot)
	_assert(absf(scoring_model.physical - 47.0) < 0.001, "Checkpoint progress and completion bonus did not preserve the +7 partial test reward.")

	var failure_manager := SPOT_MANAGER_SCRIPT.new()
	var failure_model := FakeArousalModel.new()
	failure_manager._arousal_model = failure_model
	var counts := {"failed": 0}
	failure_manager.physiological_spot_failed.connect(
		func(_ratio: float, _penalty: float) -> void: counts.failed += 1
	)
	failure_manager._on_spot_expired(0.0, spot)
	_assert(absf(failure_model.physical - 35.0) < 0.001, "Ignored-sequence timeout penalty was not applied.")
	_assert(counts.failed == 1, "Timeout did not emit the failure boundary used by the red flash.")
	spot.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
