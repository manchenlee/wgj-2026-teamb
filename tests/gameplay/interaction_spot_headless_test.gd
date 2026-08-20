extends SceneTree

const SLIDE_NOTE_SCENE := preload("res://scenes/components/SlideNote.tscn")
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


class FakeAnchorRegion:
	extends Control

	func get_interaction_spot_global_rect(_anchor_id: StringName, _fallback_global_center: Vector2) -> Rect2:
		return Rect2(Vector2(100.0, 100.0), Vector2(480.0, 480.0))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_ordered_progression_and_fast_crossing()
	await _test_suspend_resume_requires_fresh_crossing()
	await _test_timeout_resolves_once()
	await _test_force_resolution_resolves_once()
	await _test_manager_scoring_and_failure_boundary()
	await _test_manager_spawns_one_slide_and_cleans_up()
	if _failures.is_empty():
		print("SlideNote headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _make_spot(lifetime: float = 30.0) -> SlideNote:
	var spot := SLIDE_NOTE_SCENE.instantiate() as SlideNote
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
	_assert(absf(spot.get_progress_ratio()) < 0.001, "Arming changed normalized Slide progress.")

	# One long event crosses checkpoints 1 and 2, but may advance only checkpoint 1.
	spot._process_pointer_move(Vector2(220.0, 20.0))
	spot._process_pointer_move(Vector2(220.0, 300.0))
	_assert(counts.progress == 1, "One motion event advanced more than one checkpoint.")
	_assert(spot.get_next_checkpoint_index() == 2, "Checkpoint 1 did not select checkpoint 2.")
	_assert(absf(spot.get_progress_ratio() - 1.0 / 3.0) < 0.001, "Checkpoint 1 progress was not normalized to 1/3.")

	# Crossing checkpoint 3 out of order must not advance checkpoint 2.
	spot._process_pointer_move(Vector2(20.0, 300.0))
	spot._process_pointer_move(Vector2(20.0, 220.0))
	spot._process_pointer_move(Vector2(140.0, 220.0))
	_assert(counts.progress == 1, "Checkpoint 3 advanced before checkpoint 2.")

	# Fast crossings count even though both endpoints are outside the circle.
	spot._process_pointer_move(Vector2(220.0, 140.0))
	spot._process_pointer_move(Vector2(220.0, 300.0))
	_assert(counts.progress == 2, "Fast segment crossing checkpoint 2 was missed.")
	_assert(absf(spot.get_progress_ratio() - 2.0 / 3.0) < 0.001, "Checkpoint 2 progress was not normalized to 2/3.")
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
	var paused_progress := spot.get_progress_ratio()
	var paused_checkpoint := spot.get_next_checkpoint_index()
	spot._process_pointer_move(Vector2(220.0, 300.0))
	await create_timer(0.1).timeout
	_assert(counts.progress == 1, "Mouse movement while suspended granted progress.")
	_assert(absf(spot.lifetime_timer.time_left - paused_time_left) < 0.02, "Lifetime advanced while suspended.")
	_assert(absf(spot.get_progress_ratio() - paused_progress) < 0.001, "Suspend changed Slide progress.")
	_assert(spot.get_next_checkpoint_index() == paused_checkpoint, "Suspend changed the active checkpoint.")

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
	var counts := {"completed": 0, "expired": 0}
	spot.completed.connect(func() -> void: counts.completed += 1)
	spot.expired.connect(func(_ratio: float) -> void: counts.expired += 1)
	await create_timer(0.12).timeout
	_assert(counts.expired == 1, "Timeout did not resolve failure exactly once.")
	spot.force_expire()
	_assert(counts.expired == 1, "Resolved timeout emitted more than once.")
	spot.force_complete()
	_assert(counts.completed == 0, "A completed outcome fired after the note timed out.")
	spot.queue_free()
	await process_frame


func _test_force_resolution_resolves_once() -> void:
	var completed_spot := _make_spot()
	var completed_counts := {"completed": 0, "expired": 0}
	completed_spot.completed.connect(func() -> void: completed_counts.completed += 1)
	completed_spot.expired.connect(func(_ratio: float) -> void: completed_counts.expired += 1)
	completed_spot.force_complete()
	completed_spot.force_complete()
	completed_spot.force_expire()
	_assert(completed_counts.completed == 1, "Force complete did not resolve the node exactly once.")
	_assert(completed_counts.expired == 0, "An expired outcome fired after force completion.")
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
	_assert(absf(scoring_model.physical - 42.0) < 0.001, "One checkpoint did not preserve the +2 incremental reward.")
	scoring_manager._on_spot_progressed(1.0 / 3.0, spot)
	scoring_manager._on_spot_progressed(1.0 / 3.0, spot)
	scoring_manager._on_spot_completed(spot)
	_assert(absf(scoring_model.physical - 51.0) < 0.001, "Full Slide scoring did not preserve +6 incremental and +5 completion.")

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


func _test_manager_spawns_one_slide_and_cleans_up() -> void:
	var manager := SPOT_MANAGER_SCRIPT.new()
	var model := FakeArousalModel.new()
	var prompt_layer := Control.new()
	var anchor_region := FakeAnchorRegion.new()
	var spawn_timer := Timer.new()
	root.add_child(prompt_layer)
	root.add_child(anchor_region)
	root.add_child(spawn_timer)

	manager.setup(model, null, prompt_layer, anchor_region, spawn_timer)
	manager.set_available_anchor_ids(["test_anchor"])
	manager.set_bounds_rect(Rect2(Vector2.ZERO, Vector2(720.0, 720.0)))
	manager.start()
	manager.force_spawn_spot()
	manager.force_spawn_spot()

	_assert(manager._active_spots.size() == 1, "Manager spawned more than one active note.")
	if manager._active_spots.size() == 1:
		_assert(manager._active_spots[0] is SlideNote, "Manager did not spawn SlideNote in Stage A.")
		var completion_counts := {"completed": 0}
		manager._active_spots[0].completed.connect(func() -> void: completion_counts.completed += 1)
		manager.force_complete_spot()
		manager.force_complete_spot()
		_assert(completion_counts.completed == 1, "Manager force complete did not resolve the actual note exactly once.")

	manager.force_spawn_spot()
	if manager._active_spots.size() == 1:
		var expiry_counts := {"expired": 0}
		manager._active_spots[0].expired.connect(func(_ratio: float) -> void: expiry_counts.expired += 1)
		manager.force_expire_spot()
		manager.force_expire_spot()
		_assert(expiry_counts.expired == 1, "Manager force expire did not resolve the actual note exactly once.")
	else:
		_assert(false, "Manager could not spawn a SlideNote for force-expire validation.")

	manager.stop()
	_assert(manager._active_spots.is_empty(), "Manager stop did not clear active notes.")
	_assert(spawn_timer.is_stopped(), "Manager stop did not stop the spawn timer.")
	prompt_layer.queue_free()
	anchor_region.queue_free()
	spawn_timer.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
