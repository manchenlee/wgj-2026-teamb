extends SceneTree

const SLIDE_NOTE_SCENE := preload("res://scenes/components/SlideNote.tscn")
const CLICK_NOTE_SCENE := preload("res://scenes/components/ClickNote.tscn")
const RUB_NOTE_SCENE := preload("res://scenes/components/RubNote.tscn")
const SPOT_MANAGER_SCRIPT := preload("res://scripts/gameplay/interaction_spot_manager.gd")
const PHASE_CONFIG_SCRIPT := preload("res://data/phases/phase_config.gd")
const CONFIG := preload("res://scripts/gameplay/GameConfig.gd")
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
		return Rect2(Vector2(100.0, 100.0), Vector2(1000.0, 1000.0))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_shared_approach_circle_geometry()
	await _test_click_input_and_scoring()
	await _test_click_timeout_and_failure()
	await _test_click_suspend_resume()
	await _test_click_force_resolution()
	await _test_rub_input_and_progress()
	await _test_rub_completion_and_scoring()
	await _test_rub_touch_input()
	await _test_rub_timeout_and_failure()
	await _test_rub_suspend_resume()
	await _test_rub_force_resolution()
	await _test_ordered_progression_and_fast_crossing()
	await _test_suspend_resume_requires_fresh_crossing()
	await _test_timeout_resolves_once()
	await _test_force_resolution_resolves_once()
	await _test_manager_scoring_and_failure_boundary()
	await _test_partial_slide_timeout_and_failure()
	_test_weighted_note_type_selection()
	await _test_manager_production_timer_allows_concurrency()
	await _test_manager_weighted_production_and_debug_spawns()
	await _test_manager_stop_cleanup_and_restart()
	if _failures.is_empty():
		print("Mixed physiological note headless tests passed.")
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


func _make_click_note(lifetime: float = 30.0) -> ClickNote:
	var note := CLICK_NOTE_SCENE.instantiate() as ClickNote
	note.setup({
		"spot_lifetime": lifetime,
		"target_center": Vector2(84.0, 84.0),
		"target_radius": 40.0,
	})
	root.add_child(note)
	return note


func _make_rub_note(lifetime: float = 30.0, required_distance: float = 600.0) -> RubNote:
	var note := RUB_NOTE_SCENE.instantiate() as RubNote
	note.setup({
		"spot_lifetime": lifetime,
		"required_scrub_distance": required_distance,
		"valid_motion_threshold": 3.0,
		"max_delta_per_event": 24.0,
		"target_center": Vector2(108.0, 108.0),
		"target_radius": 52.0,
	})
	root.add_child(note)
	return note


func _mouse_button_event(position: Vector2, pressed: bool, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button_index
	event.pressed = pressed
	return event


func _screen_touch_event(position: Vector2, pressed: bool, index: int = 0) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	event.index = index
	return event


func _mouse_motion_event(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	return event


func _screen_drag_event(position: Vector2, index: int) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.index = index
	return event


func _test_click_input_and_scoring() -> void:
	var note := _make_click_note()
	var counts := {"progress": 0, "progress_delta": 0.0, "completed": 0}
	note.progressed.connect(func(delta: float) -> void:
		counts.progress += 1
		counts.progress_delta += delta
	)
	note.completed.connect(func() -> void: counts.completed += 1)

	var motion := InputEventMouseMotion.new()
	motion.position = note.target_center
	note._gui_input(motion)
	note._gui_input(_mouse_button_event(note.target_center, false))
	note._gui_input(_mouse_button_event(note.target_center + Vector2(note.target_radius + 1.0, 0.0), true))
	note._gui_input(_mouse_button_event(note.target_center, true, MOUSE_BUTTON_RIGHT))
	_assert(counts.completed == 0, "Movement, release, outside click, or secondary click completed ClickNote.")

	note._gui_input(_mouse_button_event(note.target_center, true))
	note._gui_input(_mouse_button_event(note.target_center, true))
	_assert(counts.progress == 1, "ClickNote did not emit progress exactly once.")
	_assert(absf(counts.progress_delta - 1.0) < 0.001, "ClickNote did not emit full normalized progress.")
	_assert(counts.completed == 1, "ClickNote did not complete exactly once from an inside press.")
	note.force_expire()
	_assert(counts.completed == 1, "ClickNote resolved again after successful input.")
	note.queue_free()
	await process_frame

	var scoring_note := _make_click_note()
	var manager := SPOT_MANAGER_SCRIPT.new()
	var model := FakeArousalModel.new()
	manager._arousal_model = model
	scoring_note.progressed.connect(manager._on_spot_progressed.bind(scoring_note))
	scoring_note.completed.connect(manager._on_spot_completed.bind(scoring_note))
	scoring_note._gui_input(_mouse_button_event(scoring_note.target_center, true))
	_assert(absf(model.physical - 43.0) < 0.001, "ClickNote did not apply the current +1 progress and +2 completion reward once.")
	scoring_note.queue_free()
	await process_frame

	var touch_note := _make_click_note()
	var touch_counts := {"completed": 0}
	touch_note.completed.connect(func() -> void: touch_counts.completed += 1)
	touch_note._gui_input(_screen_touch_event(touch_note.target_center, false))
	_assert(touch_counts.completed == 0, "Touch release completed ClickNote.")
	touch_note._gui_input(_screen_touch_event(touch_note.target_center, true))
	_assert(touch_counts.completed == 1, "Touch press inside ClickNote did not complete it.")
	touch_note.queue_free()
	await process_frame


func _test_click_timeout_and_failure() -> void:
	var note := _make_click_note(0.05)
	var manager := SPOT_MANAGER_SCRIPT.new()
	var model := FakeArousalModel.new()
	manager._arousal_model = model
	var counts := {"expired": 0, "failed": 0, "ratio": -1.0}
	note.expired.connect(func(ratio: float) -> void:
		counts.expired += 1
		counts.ratio = ratio
	)
	note.expired.connect(manager._on_spot_expired.bind(note))
	manager.physiological_spot_failed.connect(
		func(_ratio: float, _penalty: float) -> void: counts.failed += 1
	)
	await create_timer(0.12).timeout
	_assert(counts.expired == 1, "Untouched ClickNote did not expire exactly once.")
	_assert(absf(counts.ratio) < 0.001, "Untouched ClickNote timeout progress was not zero.")
	_assert(absf(model.physical - 35.0) < 0.001, "ClickNote timeout did not apply the existing ignored penalty.")
	_assert(counts.failed == 1, "ClickNote timeout did not emit the existing failure boundary once.")
	note.force_complete()
	_assert(counts.expired == 1, "Timed-out ClickNote resolved again after force completion.")
	note.queue_free()
	await process_frame


func _test_click_suspend_resume() -> void:
	var note := _make_click_note()
	var counts := {"completed": 0}
	note.completed.connect(func() -> void: counts.completed += 1)
	_assert(note._get_approach_center().is_equal_approx(note.target_center), "Click approach center differed from its target.")
	_assert(absf(note._get_approach_target_radius() - note.target_radius) < 0.001, "Click approach radius differed from its target radius.")

	note.set_suspended(true)
	var paused_time_left := note.lifetime_timer.time_left
	var paused_radius := note._calculate_approach_radius(paused_time_left / note.spot_lifetime)
	note._gui_input(_mouse_button_event(note.target_center, true))
	await create_timer(0.1).timeout
	var suspended_radius := note._calculate_approach_radius(note.lifetime_timer.time_left / note.spot_lifetime)
	_assert(counts.completed == 0, "Suspended ClickNote accepted an inside click.")
	_assert(note.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Suspended ClickNote still consumed pointer input.")
	_assert(absf(note.lifetime_timer.time_left - paused_time_left) < 0.02, "ClickNote lifetime advanced while suspended.")
	_assert(absf(suspended_radius - paused_radius) < 0.02, "Click approach radius changed while suspended.")

	note.set_suspended(false)
	_assert(note.mouse_filter == Control.MOUSE_FILTER_STOP, "Resumed ClickNote did not restore pointer input.")
	var resumed_radius := note._calculate_approach_radius(note.lifetime_timer.time_left / note.spot_lifetime)
	_assert(absf(resumed_radius - paused_radius) < 0.02, "Click approach radius reset on resume.")
	_assert(counts.completed == 0, "A suspended click carried over after resume.")
	await create_timer(0.1).timeout
	var continued_radius := note._calculate_approach_radius(note.lifetime_timer.time_left / note.spot_lifetime)
	_assert(continued_radius < resumed_radius, "Click approach radius did not continue shrinking after resume.")
	note._gui_input(_mouse_button_event(note.target_center, true))
	_assert(counts.completed == 1, "A new click after resume did not complete ClickNote.")
	note.queue_free()
	await process_frame


func _test_click_force_resolution() -> void:
	var completed_note := _make_click_note()
	var completed_counts := {"progress": 0, "completed": 0, "expired": 0}
	completed_note.progressed.connect(func(_delta: float) -> void: completed_counts.progress += 1)
	completed_note.completed.connect(func() -> void: completed_counts.completed += 1)
	completed_note.expired.connect(func(_ratio: float) -> void: completed_counts.expired += 1)
	completed_note.force_complete()
	completed_note.force_complete()
	completed_note._gui_input(_mouse_button_event(completed_note.target_center, true))
	_assert(completed_counts.completed == 1, "Forced ClickNote completion emitted more than once.")
	_assert(completed_counts.progress == 0, "Click after forced completion emitted progress.")
	_assert(completed_counts.expired == 0, "Forced-complete ClickNote also expired.")
	completed_note.queue_free()
	await process_frame

	var expired_note := _make_click_note()
	var expired_counts := {"completed": 0, "expired": 0}
	expired_note.completed.connect(func() -> void: expired_counts.completed += 1)
	expired_note.expired.connect(func(_ratio: float) -> void: expired_counts.expired += 1)
	expired_note.force_expire()
	expired_note.force_expire()
	expired_note._gui_input(_mouse_button_event(expired_note.target_center, true))
	_assert(expired_counts.expired == 1, "Forced ClickNote expiry emitted more than once.")
	_assert(expired_counts.completed == 0, "Expired ClickNote also completed from input.")
	expired_note.queue_free()
	await process_frame


func _test_rub_input_and_progress() -> void:
	var note := _make_rub_note(30.0, 100.0)
	var counts := {"started": 0, "ended": 0, "progress": 0, "delta": 0.0}
	note.interaction_started.connect(func() -> void: counts.started += 1)
	note.interaction_ended.connect(func() -> void: counts.ended += 1)
	note.progressed.connect(func(delta: float) -> void:
		counts.progress += 1
		counts.delta += delta
	)
	var center := note.target_center

	note._gui_input(_mouse_motion_event(center + Vector2(10.0, 0.0)))
	note._gui_input(_mouse_button_event(center + Vector2(note.target_radius + 1.0, 0.0), true))
	note._gui_input(_mouse_motion_event(center))
	note._gui_input(_mouse_button_event(center, true, MOUSE_BUTTON_RIGHT))
	_assert(not note.is_rubbing(), "Outside press, secondary click, or movement started RubNote.")
	_assert(absf(note.get_progress_ratio()) < 0.001, "Movement without an active Rub press added progress.")

	note._gui_input(_mouse_button_event(center, true))
	_assert(note.is_rubbing(), "Primary press inside did not start RubNote.")
	_assert(counts.started == 1, "RubNote did not emit one interaction-started signal.")
	note._gui_input(_mouse_motion_event(center + Vector2(2.0, 0.0)))
	_assert(absf(note.accumulated_scrub_distance) < 0.001, "Sub-threshold Rub movement added progress.")
	note._gui_input(_mouse_motion_event(center + Vector2(20.0, 0.0)))
	_assert(absf(note.accumulated_scrub_distance - 18.0) < 0.001, "Valid Rub movement used the wrong distance.")
	note._gui_input(_mouse_motion_event(center + Vector2(-20.0, 0.0)))
	_assert(absf(note.accumulated_scrub_distance - 42.0) < 0.001, "Large Rub movement was not capped at 24 px.")

	note._gui_input(_mouse_motion_event(center + Vector2(note.target_radius + 10.0, 0.0)))
	note._gui_input(_mouse_motion_event(center))
	_assert(absf(note.accumulated_scrub_distance - 42.0) < 0.001, "Leaving or first re-entering the Rub circle added progress.")
	note._gui_input(_mouse_motion_event(center + Vector2(10.0, 0.0)))
	_assert(absf(note.accumulated_scrub_distance - 52.0) < 0.001, "Fresh inside movement after re-entry did not progress.")
	_assert(absf(counts.delta - 0.52) < 0.001, "RubNote emitted incorrect normalized progress deltas.")

	note._gui_input(_mouse_button_event(center, false))
	_assert(not note.is_rubbing(), "Primary release did not stop RubNote.")
	_assert(counts.ended == 1, "RubNote did not emit one interaction-ended signal.")
	note._gui_input(_mouse_motion_event(center + Vector2(-10.0, 0.0)))
	_assert(absf(note.accumulated_scrub_distance - 52.0) < 0.001, "Movement after release added Rub progress.")
	note.queue_free()
	await process_frame


func _test_rub_completion_and_scoring() -> void:
	var note := _make_rub_note(30.0, 60.0)
	var manager := SPOT_MANAGER_SCRIPT.new()
	var model := FakeArousalModel.new()
	manager._arousal_model = model
	var counts := {"completed": 0, "expired": 0, "progress_delta": 0.0}
	note.progressed.connect(func(delta: float) -> void: counts.progress_delta += delta)
	note.progressed.connect(manager._on_spot_progressed.bind(note))
	note.completed.connect(func() -> void: counts.completed += 1)
	note.completed.connect(manager._on_spot_completed.bind(note))
	note.expired.connect(func(_ratio: float) -> void: counts.expired += 1)
	var center := note.target_center
	note._gui_input(_mouse_button_event(center, true))
	note._gui_input(_mouse_motion_event(center + Vector2(20.0, 0.0)))
	note._gui_input(_mouse_motion_event(center + Vector2(-20.0, 0.0)))
	note._gui_input(_mouse_motion_event(center + Vector2(20.0, 0.0)))
	note._gui_input(_mouse_motion_event(center + Vector2(-20.0, 0.0)))
	note._gui_input(_mouse_button_event(center, false))
	_assert(absf(counts.progress_delta - 1.0) < 0.001, "Completed Rub progress deltas did not total 1.0.")
	_assert(counts.completed == 1, "RubNote did not complete exactly once.")
	_assert(counts.expired == 0, "Completed RubNote also expired.")
	_assert(absf(model.physical - 43.0) < 0.001, "RubNote did not apply the current +1 progress and +2 completion reward once.")
	note.force_complete()
	_assert(counts.completed == 1, "Completed RubNote resolved more than once.")
	note.queue_free()
	await process_frame


func _test_rub_touch_input() -> void:
	var note := _make_rub_note(30.0, 100.0)
	var counts := {"started": 0, "ended": 0}
	note.interaction_started.connect(func() -> void: counts.started += 1)
	note.interaction_ended.connect(func() -> void: counts.ended += 1)
	var center := note.target_center
	note._gui_input(_screen_touch_event(center, true, 2))
	_assert(note.is_rubbing(), "Touch press inside did not start RubNote.")
	note._gui_input(_screen_drag_event(center + Vector2(12.0, 0.0), 3))
	_assert(absf(note.get_progress_ratio()) < 0.001, "Unrelated touch drag progressed RubNote.")
	note._gui_input(_screen_drag_event(center + Vector2(12.0, 0.0), 2))
	_assert(absf(note.accumulated_scrub_distance - 12.0) < 0.001, "Matching touch drag did not progress RubNote.")
	note._gui_input(_screen_touch_event(center, false, 3))
	_assert(note.is_rubbing(), "Unrelated touch release stopped RubNote.")
	note._gui_input(_screen_touch_event(center, false, 2))
	_assert(not note.is_rubbing(), "Matching touch release did not stop RubNote.")
	_assert(counts.started == 1 and counts.ended == 1, "Touch Rub did not emit one start/end pair.")
	note.queue_free()
	await process_frame


func _test_rub_timeout_and_failure() -> void:
	var untouched_note := _make_rub_note(0.05, 100.0)
	var untouched_manager := SPOT_MANAGER_SCRIPT.new()
	var untouched_model := FakeArousalModel.new()
	untouched_manager._arousal_model = untouched_model
	var untouched_counts := {"expired": 0, "failed": 0, "ratio": -1.0}
	untouched_note.expired.connect(func(ratio: float) -> void:
		untouched_counts.expired += 1
		untouched_counts.ratio = ratio
	)
	untouched_note.expired.connect(untouched_manager._on_spot_expired.bind(untouched_note))
	untouched_manager.physiological_spot_failed.connect(
		func(_ratio: float, _penalty: float) -> void: untouched_counts.failed += 1
	)
	await create_timer(0.12).timeout
	_assert(untouched_counts.expired == 1, "Untouched RubNote did not expire once.")
	_assert(absf(untouched_counts.ratio) < 0.001, "Untouched RubNote timeout progress was not zero.")
	_assert(absf(untouched_model.physical - 35.0) < 0.001, "Untouched RubNote did not use the ignored penalty.")
	_assert(untouched_counts.failed == 1, "Rub timeout did not emit the failure boundary once.")
	untouched_note.queue_free()
	await process_frame

	var partial_note := _make_rub_note(0.05, 100.0)
	var partial_manager := SPOT_MANAGER_SCRIPT.new()
	var partial_model := FakeArousalModel.new()
	partial_manager._arousal_model = partial_model
	var partial_counts := {"expired": 0, "ratio": -1.0}
	partial_note.expired.connect(func(ratio: float) -> void:
		partial_counts.expired += 1
		partial_counts.ratio = ratio
	)
	partial_note.progressed.connect(partial_manager._on_spot_progressed.bind(partial_note))
	partial_note.expired.connect(partial_manager._on_spot_expired.bind(partial_note))
	partial_note._gui_input(_mouse_button_event(partial_note.target_center, true))
	partial_note._gui_input(_mouse_motion_event(partial_note.target_center + Vector2(30.0, 0.0)))
	await create_timer(0.12).timeout
	_assert(partial_counts.expired == 1, "Partially rubbed note did not expire once.")
	_assert(absf(partial_counts.ratio - 0.24) < 0.001, "Partial Rub timeout reported incorrect normalized progress.")
	_assert(absf(partial_model.physical - 38.24) < 0.001, "Partial Rub scoring or penalty routing changed unexpectedly.")
	partial_note.queue_free()
	await process_frame


func _test_rub_suspend_resume() -> void:
	var note := _make_rub_note(30.0, 100.0)
	var center := note.target_center
	note._gui_input(_mouse_button_event(center, true))
	note._gui_input(_mouse_motion_event(center + Vector2(20.0, 0.0)))
	var progress_before_suspend := note.get_progress_ratio()
	_assert(note._get_approach_center().is_equal_approx(center), "Rub approach center differed from its target.")
	_assert(absf(note._get_approach_target_radius() - note.target_radius) < 0.001, "Rub approach radius differed from its target.")
	note.set_suspended(true)
	var paused_time_left := note.lifetime_timer.time_left
	var paused_radius := note._calculate_approach_radius(paused_time_left / note.spot_lifetime)
	_assert(not note.is_rubbing(), "Suspending RubNote did not clear held input.")
	_assert(not note._has_pointer_sample and note._active_touch_index == -1, "Suspending RubNote did not clear pointer/touch state.")
	note._gui_input(_mouse_motion_event(center + Vector2(-20.0, 0.0)))
	await create_timer(0.1).timeout
	_assert(absf(note.get_progress_ratio() - progress_before_suspend) < 0.001, "Rub progress changed while suspended.")
	_assert(absf(note.lifetime_timer.time_left - paused_time_left) < 0.02, "Rub lifetime advanced while suspended.")
	var suspended_radius := note._calculate_approach_radius(note.lifetime_timer.time_left / note.spot_lifetime)
	_assert(absf(suspended_radius - paused_radius) < 0.02, "Rub approach radius changed while suspended.")

	note.set_suspended(false)
	var resumed_radius := note._calculate_approach_radius(note.lifetime_timer.time_left / note.spot_lifetime)
	_assert(absf(resumed_radius - paused_radius) < 0.02, "Rub approach radius reset on resume.")
	note._gui_input(_mouse_motion_event(center + Vector2(-20.0, 0.0)))
	_assert(absf(note.get_progress_ratio() - progress_before_suspend) < 0.001, "Rub movement without a fresh press progressed after resume.")
	await create_timer(0.1).timeout
	var continued_radius := note._calculate_approach_radius(note.lifetime_timer.time_left / note.spot_lifetime)
	_assert(continued_radius < resumed_radius, "Rub approach radius did not continue after resume.")
	note._gui_input(_mouse_button_event(center, true))
	note._gui_input(_mouse_motion_event(center + Vector2(-10.0, 0.0)))
	_assert(note.get_progress_ratio() > progress_before_suspend, "Fresh Rub press after resume did not continue progress.")
	note.queue_free()
	await process_frame


func _test_rub_force_resolution() -> void:
	var completed_note := _make_rub_note()
	var completed_counts := {"completed": 0, "expired": 0}
	completed_note.completed.connect(func() -> void: completed_counts.completed += 1)
	completed_note.expired.connect(func(_ratio: float) -> void: completed_counts.expired += 1)
	completed_note.force_complete()
	completed_note.force_complete()
	completed_note.force_expire()
	completed_note._gui_input(_mouse_button_event(completed_note.target_center, true))
	_assert(completed_counts.completed == 1 and completed_counts.expired == 0, "Forced Rub completion was not exclusive and exact-once.")
	completed_note.queue_free()
	await process_frame

	var expired_note := _make_rub_note()
	var expired_counts := {"completed": 0, "expired": 0}
	expired_note.completed.connect(func() -> void: expired_counts.completed += 1)
	expired_note.expired.connect(func(_ratio: float) -> void: expired_counts.expired += 1)
	expired_note.force_expire()
	expired_note.force_expire()
	expired_note.force_complete()
	expired_note._gui_input(_mouse_button_event(expired_note.target_center, true))
	_assert(expired_counts.expired == 1 and expired_counts.completed == 0, "Forced Rub expiry was not exclusive and exact-once.")
	expired_note.queue_free()
	await process_frame


func _test_shared_approach_circle_geometry() -> void:
	var spot := _make_spot()
	var target_radius := spot.checkpoint_radius
	_assert(
		absf(spot._calculate_approach_radius(1.0) - target_radius * spot.approach_start_scale) < 0.001,
		"The approach circle did not start at the configured scale."
	)
	var half_radius := spot._calculate_approach_radius(0.5)
	_assert(
		half_radius > target_radius and half_radius < target_radius * spot.approach_start_scale,
		"The half-lifetime approach radius was not between its start and target radii."
	)
	_assert(
		absf(spot._calculate_approach_radius(0.0) - target_radius) < 0.001,
		"The approach circle did not end at the target radius."
	)
	_assert(spot._get_approach_center().is_equal_approx(test_points[0]), "The approach circle did not begin at the start marker.")

	spot._input(_mouse_button_event(test_points[0], true))
	_assert(spot._get_approach_center().is_equal_approx(test_points[1]), "Arming did not move the approach circle to checkpoint 1.")
	await create_timer(0.1).timeout
	var time_before_checkpoint := spot.lifetime_timer.time_left
	var radius_before_checkpoint := spot._calculate_approach_radius(
		time_before_checkpoint / spot.spot_lifetime
	)
	spot._input(_mouse_motion_event(Vector2(220.0, 20.0)))
	spot._input(_mouse_motion_event(Vector2(220.0, 180.0)))
	_assert(spot._get_approach_center().is_equal_approx(test_points[2]), "Checkpoint 1 did not move the approach circle to checkpoint 2.")
	var time_after_checkpoint := spot.lifetime_timer.time_left
	var radius_after_checkpoint := spot._calculate_approach_radius(
		time_after_checkpoint / spot.spot_lifetime
	)
	_assert(time_after_checkpoint > time_before_checkpoint, "Changing checkpoints did not reset the per-checkpoint timer.")
	_assert(radius_after_checkpoint > radius_before_checkpoint, "Changing checkpoints did not reset the approach circle.")

	spot.set_suspended(true)
	var paused_time_left := spot.lifetime_timer.time_left
	var paused_radius := spot._calculate_approach_radius(paused_time_left / spot.spot_lifetime)
	await create_timer(0.1).timeout
	var suspended_radius := spot._calculate_approach_radius(
		spot.lifetime_timer.time_left / spot.spot_lifetime
	)
	_assert(absf(spot.lifetime_timer.time_left - paused_time_left) < 0.02, "Approach test lifetime advanced while suspended.")
	_assert(absf(suspended_radius - paused_radius) < 0.02, "Approach radius changed while suspended.")
	spot.set_suspended(false)
	var resumed_radius := spot._calculate_approach_radius(
		spot.lifetime_timer.time_left / spot.spot_lifetime
	)
	_assert(absf(resumed_radius - paused_radius) < 0.02, "Approach radius reset after resume.")
	await create_timer(0.1).timeout
	var continued_radius := spot._calculate_approach_radius(
		spot.lifetime_timer.time_left / spot.spot_lifetime
	)
	_assert(continued_radius < resumed_radius, "Approach radius did not continue shrinking after resume.")
	spot.queue_free()
	await process_frame


func _test_ordered_progression_and_fast_crossing() -> void:
	var spot := _make_spot()
	var counts := {"progress": 0, "completed": 0}
	spot.progressed.connect(func(_delta: float) -> void: counts.progress += 1)
	spot.completed.connect(func() -> void: counts.completed += 1)

	# Hovering or pressing a future checkpoint before the start must do nothing.
	spot._input(_mouse_motion_event(Vector2(180.0, 220.0)))
	spot._input(_mouse_button_event(test_points[2], true))
	spot._input(_mouse_button_event(test_points[2], false))
	_assert(not spot.is_armed(), "Hovering or pressing a future checkpoint armed the interaction.")

	# Press the start. It arms but grants no progress.
	spot._input(_mouse_button_event(test_points[0], true))
	_assert(spot.is_armed() and spot.is_dragging(), "Pressing the start did not arm the drag interaction.")
	_assert(counts.progress == 0, "The start marker granted physiological progress.")
	_assert(absf(spot.get_progress_ratio()) < 0.001, "Arming changed normalized Slide progress.")
	spot._input(_mouse_button_event(test_points[0], false))
	spot._input(_mouse_motion_event(Vector2(220.0, 300.0)))
	_assert(counts.progress == 0 and not spot.is_dragging(), "Slide progressed from hover movement after the button was released.")
	spot._input(_mouse_button_event(test_points[0], true))

	# One long event crosses checkpoints 1 and 2, but may advance only checkpoint 1.
	spot._input(_mouse_motion_event(Vector2(220.0, 20.0)))
	spot._input(_mouse_motion_event(Vector2(220.0, 300.0)))
	_assert(counts.progress == 1, "One motion event advanced more than one checkpoint.")
	_assert(spot.get_next_checkpoint_index() == 2, "Checkpoint 1 did not select checkpoint 2.")
	_assert(absf(spot.get_progress_ratio() - 1.0 / 3.0) < 0.001, "Checkpoint 1 progress was not normalized to 1/3.")

	# Crossing checkpoint 3 out of order must not advance checkpoint 2.
	spot._input(_mouse_motion_event(Vector2(20.0, 300.0)))
	spot._input(_mouse_motion_event(Vector2(20.0, 220.0)))
	spot._input(_mouse_motion_event(Vector2(140.0, 220.0)))
	_assert(counts.progress == 1, "Checkpoint 3 advanced before checkpoint 2.")

	# Fast crossings count even though both endpoints are outside the circle.
	spot._input(_mouse_motion_event(Vector2(220.0, 140.0)))
	spot._input(_mouse_motion_event(Vector2(220.0, 300.0)))
	_assert(counts.progress == 2, "Fast segment crossing checkpoint 2 was missed.")
	_assert(absf(spot.get_progress_ratio() - 2.0 / 3.0) < 0.001, "Checkpoint 2 progress was not normalized to 2/3.")
	spot._input(_mouse_motion_event(Vector2(20.0, 300.0)))
	spot._input(_mouse_motion_event(Vector2(20.0, 220.0)))
	spot._input(_mouse_motion_event(Vector2(180.0, 220.0)))
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
	spot._input(_mouse_button_event(test_points[0], true))
	spot._input(_mouse_motion_event(Vector2(220.0, 20.0)))
	spot._input(_mouse_motion_event(Vector2(220.0, 180.0)))
	_assert(counts.progress == 1, "Suspend test could not establish checkpoint 1 progress.")

	spot.set_suspended(true)
	var paused_time_left := spot.lifetime_timer.time_left
	var paused_progress := spot.get_progress_ratio()
	var paused_checkpoint := spot.get_next_checkpoint_index()
	spot._input(_mouse_motion_event(Vector2(220.0, 300.0)))
	await create_timer(0.1).timeout
	_assert(counts.progress == 1, "Mouse movement while suspended granted progress.")
	_assert(absf(spot.lifetime_timer.time_left - paused_time_left) < 0.02, "Lifetime advanced while suspended.")
	_assert(absf(spot.get_progress_ratio() - paused_progress) < 0.001, "Suspend changed Slide progress.")
	_assert(spot.get_next_checkpoint_index() == paused_checkpoint, "Suspend changed the active checkpoint.")

	spot.set_suspended(false)
	spot._input(_mouse_motion_event(Vector2(220.0, 220.0)))
	spot._input(_mouse_motion_event(Vector2(225.0, 220.0)))
	_assert(counts.progress == 1, "Resume or inside-target jitter granted progress.")
	spot._input(_mouse_button_event(test_points[1], true))
	spot._input(_mouse_motion_event(Vector2(220.0, 260.0)))
	_assert(counts.progress == 2, "A fresh press-and-drag after resume did not continue progress.")
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
	_assert(absf(scoring_model.physical - (40.0 + 1.0 / 3.0)) < 0.001, "One checkpoint did not receive one third of the current +1 progress pool.")
	scoring_manager._on_spot_progressed(1.0 / 3.0, spot)
	scoring_manager._on_spot_progressed(1.0 / 3.0, spot)
	scoring_manager._on_spot_completed(spot)
	_assert(absf(scoring_model.physical - 43.0) < 0.001, "Full Slide did not apply the current +1 progress and +2 completion reward once.")

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


func _test_partial_slide_timeout_and_failure() -> void:
	var manager := SPOT_MANAGER_SCRIPT.new()
	var model := FakeArousalModel.new()
	manager._arousal_model = model
	var spot := _make_spot(0.08)
	manager._active_spots.append(spot)
	var counts := {"expired": 0, "failed": 0, "ratio": -1.0, "penalty": -1.0}
	spot.progressed.connect(manager._on_spot_progressed.bind(spot))
	spot.expired.connect(func(ratio: float) -> void:
		counts.expired += 1
		counts.ratio = ratio
	)
	spot.expired.connect(manager._on_spot_expired.bind(spot))
	manager.physiological_spot_failed.connect(func(_ratio: float, penalty: float) -> void:
		counts.failed += 1
		counts.penalty = penalty
	)

	spot._input(_mouse_button_event(test_points[0], true))
	spot._input(_mouse_motion_event(Vector2(220.0, 20.0)))
	spot._input(_mouse_motion_event(Vector2(220.0, 180.0)))
	_assert(absf(spot.get_progress_ratio() - 1.0 / 3.0) < 0.001, "Partial Slide setup did not reach exactly one checkpoint.")
	await create_timer(0.16).timeout
	_assert(counts.expired == 1, "Partial Slide did not expire exactly once.")
	_assert(counts.failed == 1, "Partial Slide timeout did not emit the shared failure signal exactly once.")
	_assert(absf(counts.ratio - 1.0 / 3.0) < 0.001, "Partial Slide timeout reported the wrong normalized progress ratio.")
	_assert(absf(counts.penalty - CONFIG.SPOT_EXPIRY_PENALTY_PARTIAL) < 0.001, "Partial Slide timeout used the wrong penalty.")
	var expected_physical := 40.0 + CONFIG.SPOT_PROGRESS_GAIN_TOTAL / 3.0 - CONFIG.SPOT_EXPIRY_PENALTY_PARTIAL
	_assert(absf(model.physical - expected_physical) < 0.001, "Partial Slide progress or timeout penalty was applied incorrectly.")
	var physical_after_timeout := model.physical
	spot.force_expire()
	spot.force_complete()
	_assert(absf(model.physical - physical_after_timeout) < 0.001, "Resolved Slide changed score again.")
	spot.queue_free()
	await process_frame


func _test_weighted_note_type_selection() -> void:
	var manager := SPOT_MANAGER_SCRIPT.new()
	_assert(manager._select_note_type_for_roll(0.0, 6.0, 3.0, 1.0) == manager.NoteType.CLICK, "The start of the 6/3/1 range did not select Click.")
	_assert(manager._select_note_type_for_roll(5.999, 6.0, 3.0, 1.0) == manager.NoteType.CLICK, "The end of the Click range did not select Click.")
	_assert(manager._select_note_type_for_roll(6.0, 6.0, 3.0, 1.0) == manager.NoteType.SLIDE, "The start of the Slide range did not select Slide.")
	_assert(manager._select_note_type_for_roll(8.999, 6.0, 3.0, 1.0) == manager.NoteType.SLIDE, "The end of the Slide range did not select Slide.")
	_assert(manager._select_note_type_for_roll(9.0, 6.0, 3.0, 1.0) == manager.NoteType.RUB, "The start of the Rub range did not select Rub.")
	_assert(manager._select_note_type_for_roll(9.999, 6.0, 3.0, 1.0) == manager.NoteType.RUB, "The end of the Rub range did not select Rub.")

	_assert(manager._select_note_type_for_roll(0.5, 1.0, 0.0, 0.0) == manager.NoteType.CLICK, "A Click-only weight did not select Click.")
	_assert(manager._select_note_type_for_roll(0.5, 0.0, 1.0, 0.0) == manager.NoteType.SLIDE, "A Slide-only weight did not select Slide.")
	_assert(manager._select_note_type_for_roll(0.5, 0.0, 0.0, 1.0) == manager.NoteType.RUB, "A Rub-only weight did not select Rub.")
	_assert(manager._select_note_type_for_roll(0.5, -5.0, 2.0, -1.0) == manager.NoteType.SLIDE, "Negative weights were not clamped to zero.")
	_assert(manager._select_note_type_for_roll(0.0, 0.0, 0.0, 0.0) == manager.NoteType.CLICK, "All-zero weights did not fall back to Click.")

	var phase_config = PHASE_CONFIG_SCRIPT.new()
	_assert(absf(phase_config.click_note_weight - 6.0) < 0.001, "PhaseConfig Click weight default is not 6.")
	_assert(absf(phase_config.slide_note_weight - 3.0) < 0.001, "PhaseConfig Slide weight default is not 3.")
	_assert(absf(phase_config.rub_note_weight - 1.0) < 0.001, "PhaseConfig Rub weight default is not 1.")
	_assert(absf(phase_config.click_note_lifetime - CONFIG.CLICK_NOTE_LIFETIME) < 0.001, "PhaseConfig Click lifetime does not preserve the current configured value.")
	_assert(absf(phase_config.slide_checkpoint_time_limit - CONFIG.SLIDE_CHECKPOINT_TIME_LIMIT) < 0.001, "PhaseConfig Slide checkpoint limit does not preserve the current configured value.")
	_assert(absf(phase_config.rub_note_lifetime - CONFIG.RUB_NOTE_LIFETIME) < 0.001, "PhaseConfig Rub lifetime does not preserve the current configured value.")
	_assert(absf(phase_config.spot_spawn_delay_min - 1.1) < 0.001, "PhaseConfig minimum spawn delay is not doubled.")
	_assert(absf(phase_config.spot_spawn_delay_max - 1.6) < 0.001, "PhaseConfig maximum spawn delay is not doubled.")
	_assert(phase_config.spot_max_active_count == 3, "PhaseConfig active-note cap is not three.")


func _test_manager_weighted_production_and_debug_spawns() -> void:
	var manager := SPOT_MANAGER_SCRIPT.new()
	var model := FakeArousalModel.new()
	var phase_config = PHASE_CONFIG_SCRIPT.new()
	var prompt_layer := Control.new()
	var anchor_region := FakeAnchorRegion.new()
	var spawn_timer := Timer.new()
	root.add_child(prompt_layer)
	root.add_child(anchor_region)
	root.add_child(spawn_timer)

	manager.setup(model, null, prompt_layer, anchor_region, spawn_timer)
	manager.set_phase_config(phase_config)
	manager.set_available_anchor_ids(["test_anchor_a", "test_anchor_b", "test_anchor_c", "test_anchor_d"])
	manager.set_bounds_rect(Rect2(Vector2.ZERO, Vector2(1200.0, 1200.0)))
	manager.start()

	phase_config.click_note_weight = 1.0
	phase_config.slide_note_weight = 0.0
	phase_config.rub_note_weight = 0.0
	manager._on_spawn_timer_timeout()
	_assert(manager._active_spots.size() == 1, "Weighted production did not spawn one ClickNote.")
	if manager._active_spots.size() == 1:
		_assert(manager._active_spots[0] is ClickNote, "Click-only production weights did not instantiate ClickNote.")
		_assert(absf(manager._active_spots[0].spot_lifetime - CONFIG.CLICK_NOTE_LIFETIME) < 0.001, "Production ClickNote did not use the current configured lifetime.")
		_assert(manager._build_telemetry_dict("test").active_note_type == &"click", "Telemetry did not expose the active Click type.")
		var active_note := manager._active_spots[0]
		manager.suspend()
		manager._on_spawn_timer_timeout()
		_assert(manager._active_spots.size() == 1 and manager._active_spots[0] == active_note, "Suspend spawned or rerolled the active note.")
		manager.resume()
		_assert(manager._active_spots.size() == 1 and manager._active_spots[0] == active_note, "Resume rerolled the active note.")
		manager.force_expire_spot()
		_assert(not spawn_timer.is_stopped(), "Resolution did not leave the manager on its normal spawn schedule.")

	phase_config.click_note_weight = 0.0
	phase_config.slide_note_weight = 1.0
	manager._on_spawn_timer_timeout()
	_assert(manager._active_spots.size() == 1 and manager._active_spots[0] is SlideNote, "Slide-only production weights did not instantiate SlideNote.")
	if manager._active_spots.size() == 1:
		_assert(absf(manager._active_spots[0].spot_lifetime - CONFIG.SLIDE_CHECKPOINT_TIME_LIMIT) < 0.001, "Production Slide did not use the current checkpoint time limit.")
	manager.force_expire_spot()

	phase_config.slide_note_weight = 0.0
	phase_config.rub_note_weight = 1.0
	manager._on_spawn_timer_timeout()
	_assert(manager._active_spots.size() == 1 and manager._active_spots[0] is RubNote, "Rub-only production weights did not instantiate RubNote.")
	if manager._active_spots.size() == 1:
		_assert(absf(manager._active_spots[0].spot_lifetime - CONFIG.RUB_NOTE_LIFETIME) < 0.001, "Production RubNote did not use the current configured lifetime.")
		_assert(absf((manager._active_spots[0] as RubNote).target_radius - CONFIG.RUB_TARGET_RADIUS) < 0.001, "Production RubNote did not use the current configured radius.")
	manager.force_expire_spot()

	phase_config.rub_note_weight = 0.0
	manager._on_spawn_timer_timeout()
	_assert(manager._active_spots.size() == 1 and manager._active_spots[0] is ClickNote, "All-zero production weights did not instantiate the Click fallback.")
	manager.force_expire_spot()

	phase_config.click_note_weight = 1.0
	manager._on_spawn_timer_timeout()
	manager._on_spawn_timer_timeout()
	manager._on_spawn_timer_timeout()
	manager._on_spawn_timer_timeout()
	_assert(manager._active_spots.size() == 3, "Production spawning did not enforce the three-note active cap.")
	while not manager._active_spots.is_empty():
		manager.force_expire_spot()

	manager.force_spawn_click_note()
	manager.force_spawn_spot()
	manager.force_spawn_rub_note()
	manager.force_spawn_click_note()
	_assert(manager._active_spots.size() == 3, "Mixed debug spawning did not enforce the three-note active cap.")
	if manager._active_spots.size() == 3:
		_assert(manager._active_spots[0] is ClickNote, "The explicit Click debug spawn did not create ClickNote.")
		_assert(manager._active_spots[1] is SlideNote, "The explicit Slide debug spawn did not create SlideNote.")
		_assert(manager._active_spots[2] is RubNote, "The explicit Rub debug spawn did not create RubNote.")
		_assert(_active_note_rects_do_not_overlap(manager._active_spots), "Mixed notes overlap, including the SlideNote path bounds.")
		var mixed_telemetry := manager._build_telemetry_dict("test")
		_assert(mixed_telemetry.active_note_types == PackedStringArray(["click", "slide", "rub"]), "Telemetry did not report every active mixed-note type.")
		_assert(manager.get_debug_spot_state().contains("click,slide,rub"), "Debug state did not report every active mixed-note type.")

	manager.stop()
	_assert(manager._active_spots.is_empty(), "Manager stop did not clear active notes.")
	_assert(spawn_timer.is_stopped(), "Manager stop did not stop the spawn timer.")
	prompt_layer.queue_free()
	anchor_region.queue_free()
	spawn_timer.queue_free()
	await process_frame


func _test_manager_production_timer_allows_concurrency() -> void:
	var manager := SPOT_MANAGER_SCRIPT.new()
	var model := FakeArousalModel.new()
	var phase_config = PHASE_CONFIG_SCRIPT.new()
	phase_config.click_note_weight = 1.0
	phase_config.slide_note_weight = 0.0
	phase_config.rub_note_weight = 0.0
	var prompt_layer := Control.new()
	var anchor_region := FakeAnchorRegion.new()
	var spawn_timer := Timer.new()
	root.add_child(prompt_layer)
	root.add_child(anchor_region)
	root.add_child(spawn_timer)
	manager.setup(model, null, prompt_layer, anchor_region, spawn_timer)
	manager.set_phase_config(phase_config)
	manager.set_available_anchor_ids(["test_anchor_a", "test_anchor_b", "test_anchor_c", "test_anchor_d"])
	manager.set_bounds_rect(Rect2(Vector2.ZERO, Vector2(1200.0, 1200.0)))
	manager.start()

	# First spawn occurs at 1.0 s and the next no later than 1.6 s after that,
	# while ClickNote remains live for the current 2.0 s baseline.
	await create_timer(2.7).timeout
	_assert(manager._active_spots.size() >= 2, "The real production timer still allowed only one concurrent note.")
	_assert(manager._active_spots.size() <= 3, "The real production timer exceeded the three-note cap.")
	_assert(_active_note_rects_do_not_overlap(manager._active_spots), "Timer-spawned notes overlap.")

	manager.stop()
	prompt_layer.queue_free()
	anchor_region.queue_free()
	spawn_timer.queue_free()
	await process_frame


func _test_manager_stop_cleanup_and_restart() -> void:
	var manager := SPOT_MANAGER_SCRIPT.new()
	var model := FakeArousalModel.new()
	var phase_config = PHASE_CONFIG_SCRIPT.new()
	var prompt_layer := Control.new()
	var anchor_region := FakeAnchorRegion.new()
	var spawn_timer := Timer.new()
	root.add_child(prompt_layer)
	root.add_child(anchor_region)
	root.add_child(spawn_timer)
	manager.setup(model, null, prompt_layer, anchor_region, spawn_timer)
	manager.set_phase_config(phase_config)
	manager.set_available_anchor_ids(["test_anchor_a", "test_anchor_b", "test_anchor_c", "test_anchor_d"])
	manager.set_bounds_rect(Rect2(Vector2.ZERO, Vector2(1200.0, 1200.0)))
	var failure_count := 0
	manager.physiological_spot_failed.connect(func(_ratio: float, _penalty: float) -> void: failure_count += 1)
	var physical_before_stop := model.physical
	for note_type in [manager.NoteType.CLICK, manager.NoteType.SLIDE, manager.NoteType.RUB]:
		manager.start()
		match note_type:
			manager.NoteType.CLICK:
				manager.force_spawn_click_note()
			manager.NoteType.RUB:
				manager.force_spawn_rub_note()
			_:
				manager.force_spawn_spot()
		_assert(manager._active_spots.size() == 1, "Cleanup test could not spawn the requested note type.")
		var note: InteractionNote = manager._active_spots[0] if manager._active_spots.size() == 1 else null
		if is_instance_valid(note):
			var time_before_switch := note.lifetime_timer.time_left
			for _switch_index in range(3):
				manager.suspend()
				_assert(not note.visible and note.lifetime_timer.is_paused(), "Manager suspend did not hide and pause the active note.")
				manager._on_spawn_timer_timeout()
				_assert(manager._active_spots.size() == 1 and manager._active_spots[0] == note, "Suspension changed or rerolled the active note.")
				manager.resume()
				_assert(note.visible and not note.lifetime_timer.is_paused(), "Manager resume did not restore the same active note.")
			_assert(note.lifetime_timer.time_left <= time_before_switch, "Rapid mode switching increased the authoritative lifetime.")
		manager.stop()
		_assert(manager._active_spots.is_empty(), "Manager stop left a stale active-note reference.")
		_assert(spawn_timer.is_stopped(), "Manager stop left the production timer running.")
		if is_instance_valid(note):
			_assert(note.lifetime_timer.is_paused(), "Manager stop did not pause a note lifetime before cleanup.")
			note.force_expire()
			note.force_complete()
		await process_frame
	_assert(absf(model.physical - physical_before_stop) < 0.001, "A cleaned-up note produced a late score or penalty.")
	_assert(failure_count == 0, "Manager cleanup emitted a false physiological failure.")

	phase_config.click_note_weight = 1.0
	phase_config.slide_note_weight = 0.0
	phase_config.rub_note_weight = 0.0
	manager.start()
	manager._on_spawn_timer_timeout()
	_assert(manager._active_spots.size() == 1 and manager._active_spots[0] is ClickNote, "Manager restart did not resume normal production spawning.")
	if manager._active_spots.size() == 1:
		var telemetry := manager._build_telemetry_dict("test")
		_assert(telemetry.active_spots == 1, "Telemetry reported a stale active-note count after restart.")
		_assert(telemetry.active_note_type == &"click", "Telemetry reported the wrong active note type after restart.")
		_assert(absf(float(telemetry.physical_now) - model.physical) < 0.001, "Telemetry reported a stale physiological score.")
		manager.force_complete_spot()
		_assert(manager._active_spots.is_empty(), "Forced completion did not resolve the production note.")
		manager._on_spawn_timer_timeout()
		_assert(manager._active_spots.size() == 1, "Production could not continue after forced completion.")
		manager.force_expire_spot()
		manager._on_spawn_timer_timeout()
		_assert(manager._active_spots.size() == 1, "Production could not continue after forced expiry.")
	manager.stop()
	prompt_layer.queue_free()
	anchor_region.queue_free()
	spawn_timer.queue_free()
	await process_frame


func _active_note_rects_do_not_overlap(notes: Array[InteractionNote]) -> bool:
	for first_index in range(notes.size()):
		var first_rect: Rect2 = notes[first_index].get_meta("placement_rect") as Rect2
		for second_index in range(first_index + 1, notes.size()):
			var second_rect: Rect2 = notes[second_index].get_meta("placement_rect") as Rect2
			if first_rect.intersects(second_rect, true):
				return false
	return true


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
