extends SceneTree

const MANAGER := preload("res://scripts/gameplay/interaction_spot_manager.gd")
const PHASE := preload("res://data/phases/phase_config.gd")

var failures: Array[String] = []

class FakeAnchor:
	extends Control
	func get_interaction_spot_global_rect(_id: StringName, _fallback: Vector2) -> Rect2:
		return Rect2(Vector2(200, 200), Vector2(2400, 2400))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var production := MANAGER.new() as InteractionSpotManager
	_check(production.load_chart_file("res://data/violin_interaction_chart.json"), "Production chart failed to load")
	_check(production.get_chart_debug_state()["mode"] == "Production", "Production mode mislabeled")
	_check(not production.load_chart_variant_bank("res://data/missing_chart_variants.json", "Moderate", 2026), "Missing bank unexpectedly loaded")
	_check(production._chart_events.size() == 73 and production.get_chart_debug_state()["mode"] == "Production", "Missing bank did not retain Production fallback")
	for mode in ["Moderate", "High"]:
		var first := MANAGER.new() as InteractionSpotManager
		var second := MANAGER.new() as InteractionSpotManager
		var path := "res://data/violin_interaction_chart_%s_variants.json" % mode.to_lower()
		_check(first.load_chart_variant_bank(path, mode, 2026), "%s bank failed" % mode)
		_check(second.load_chart_variant_bank(path, mode, 2026), "%s bank failed twice" % mode)
		_check(first._chart_events == second._chart_events, "%s selection was not deterministic" % mode)
		_check(first._chart_events.size() > 0, "%s selected an empty chart" % mode)
		_check(first.get_chart_debug_state()["variant_index"] == 0, "%s default seed did not select base chart" % mode)
		var changed_seed := MANAGER.new() as InteractionSpotManager
		_check(changed_seed.load_chart_variant_bank(path, mode, 2027), "%s alternate seed failed" % mode)
		_check(changed_seed._chart_events != first._chart_events, "%s alternate seed produced same chart" % mode)
	var context := _context()
	var manager := context["manager"] as InteractionSpotManager
	_check(manager.load_chart_variant_bank("res://data/violin_interaction_chart_moderate_variants.json", "Moderate", 2026), "Runtime bank load failed")
	manager.start()
	var six_event: Dictionary = {}
	for event: Dictionary in manager._chart_events:
		if float(event["spawn_time"]) > 139.0 and (event["checkpoints"] as Array).size() == 6:
			six_event = event
			break
	_check(not six_event.is_empty(), "No six-point Slide found near loop end")
	manager.advance_chart(float(six_event["spawn_time"]) - 0.1)
	_check((six_event["checkpoints"] as Array).size() == 6, "Expected a six-point Slide near loop end")
	manager.advance_chart(float(six_event["spawn_time"]))
	_check(manager._active_spots.size() == 1, "Six-point Slide did not spawn")
	if manager._active_spots.size() == 1:
		var slide := manager._active_spots[0] as SlideNote
		_check(slide != null and slide.checkpoints.size() == 6, "Slide did not retain six checkpoints")
		_check(is_equal_approx(slide.spot_lifetime, 2.0), "Slide checkpoint timeout changed")
		var pitches: PackedInt32Array = slide.get_meta("checkpoint_pitches")
		for i in range(6):
			_check(pitches[i] == int(six_event["checkpoints"][i]["pitch"]), "Slide pitch binding lost")
		manager.advance_chart(145.4)
		manager.advance_chart(0.0)
		_check(manager._chart_loop_index == 1, "Loop index did not advance")
		_check(manager._active_spots.has(slide), "Cross-loop Slide was removed")
		_check(manager.get_chart_debug_state()["variant_index"] == 1, "Next loop did not select next variant")
		var prior_events: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/violin_interaction_chart_moderate.json"))["events"]
		_check(manager._chart_events != prior_events, "Consecutive Moderate loops selected identical events")
		var first_next: Dictionary = manager._chart_events[0]
		manager.advance_chart(float(first_next["spawn_time"]))
		var consumed := manager._chart_next_index
		manager.advance_chart(float(first_next["spawn_time"]))
		_check(consumed == 1 and manager._chart_next_index == 1, "Next-loop event was duplicated or lost")
		var heard: Array[int] = []
		manager.slide_audio_requested.connect(func(pitch: int) -> void: heard.append(pitch))
		slide._start_drag(slide.checkpoints[0], -1)
		for i in range(1, slide.checkpoints.size()):
			slide._process_pointer_move(slide.checkpoints[i])
		_check(heard == Array(pitches), "Slide did not emit all bound pitches")
		var prior := manager.get_chart_loop_stats(0)
		_check(prior["completed"] == 1 and prior["triggered_pitches"] == 6, "Cross-loop outcome attributed to wrong loop")
		_check(prior["spawned_pitch_opportunities"] == 6, "Slide opportunities counted incorrectly")
		_check(prior["slide_sizes"][6] == 1, "Six-point Slide missing from distribution")
		_check(prior["intended_pitch_opportunities"] >= prior["spawned_pitch_opportunities"], "Availability exceeds chart coverage")
		_check(manager.get_chart_loop_stats(1)["completed"] == 0, "New loop received old Slide outcome")
		print("TEST_SAMPLE_STATS: ", JSON.stringify(prior))
	manager.stop()
	(context["layer"] as Control).queue_free()
	(context["anchor"] as Control).queue_free()
	(context["timer"] as Timer).queue_free()
	_test_deterministic_placement()
	_test_psychological_loop_wrap()
	if failures.is_empty():
		print("MIDI chart variant runtime tests passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _context() -> Dictionary:
	var layer := Control.new()
	layer.size = Vector2(3000, 3000)
	root.add_child(layer)
	var anchor := FakeAnchor.new()
	root.add_child(anchor)
	var timer := Timer.new()
	root.add_child(timer)
	var manager := MANAGER.new() as InteractionSpotManager
	manager.setup(null, null, layer, anchor, timer)
	manager.set_phase_config(PHASE.new())
	manager.set_available_anchor_ids(["a", "b", "c", "d"])
	manager.set_bounds_rect(Rect2(Vector2.ZERO, layer.size))
	return {"manager": manager, "layer": layer, "anchor": anchor, "timer": timer}


func _test_deterministic_placement() -> void:
	var positions: Array[Vector2] = []
	for attempt in range(2):
		var context := _context()
		var manager := context["manager"] as InteractionSpotManager
		_check(manager.load_chart_variant_bank("res://data/violin_interaction_chart_moderate_variants.json", "Moderate", 2026), "Placement test bank failed")
		manager.start()
		var event: Dictionary = manager._chart_events[0]
		manager.advance_chart(float(event["spawn_time"]) - 0.1)
		manager.advance_chart(float(event["spawn_time"]))
		_check(manager._active_spots.size() == 1, "Placement test event did not spawn")
		if manager._active_spots.size() == 1:
			positions.append(manager._active_spots[0].position)
		manager.stop()
		(context["layer"] as Control).queue_free()
		(context["anchor"] as Control).queue_free()
		(context["timer"] as Timer).queue_free()
	_check(positions.size() == 2 and positions[0] == positions[1], "Same seed/event produced different placement")


func _test_psychological_loop_wrap() -> void:
	var context := _context()
	var manager := context["manager"] as InteractionSpotManager
	_check(manager.load_chart_variant_bank("res://data/violin_interaction_chart_moderate_variants.json", "Moderate", 2026), "Psychological test bank failed")
	manager.start()
	manager.advance_chart(140.0)
	manager.suspend()
	manager.advance_chart(0.0)
	_check(manager.get_chart_loop_stats(0)["skip_reasons"].get("psychological_mode", 0) > 0, "Cross-loop psychological events were not skipped as hidden")
	_check(manager.get_chart_loop_stats(0)["spawned"] == 0, "Hidden mode spawned an interaction")
	manager.resume()
	_check(manager._chart_loop_index == 1, "Psychological resume lost the loop transition")
	manager.stop()
	(context["layer"] as Control).queue_free()
	(context["anchor"] as Control).queue_free()
	(context["timer"] as Timer).queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
