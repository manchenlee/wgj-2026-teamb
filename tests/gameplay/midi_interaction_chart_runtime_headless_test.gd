extends SceneTree

const MANAGER_SCRIPT := preload("res://scripts/gameplay/interaction_spot_manager.gd")
const PHASE_SCRIPT := preload("res://data/phases/phase_config.gd")
const AUDIO_SCRIPT := preload("res://scripts/gameplay/violin_sample_player.gd")
const MAIN_SCENE := preload("res://scenes/Main.tscn")

var _failures: Array[String] = []
var _pitch_queries: int = 0


class FakeArousal:
	extends RefCounted
	var physical: float = 40.0
	func apply_physical(delta: float) -> void:
		physical += delta
	func refresh_physical_activity() -> void:
		pass


class FakeAnchor:
	extends Control
	func get_interaction_spot_global_rect(_id: StringName, _fallback: Vector2) -> Rect2:
		return Rect2(Vector2(200, 200), Vector2(2400, 2400))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shipped_chart_load()
	await _test_chart_sequence_and_loop()
	await _test_psychological_skip_and_resume()
	await _test_active_cap_and_placement_skip()
	await _test_slide_sizes_and_bound_audio()
	await _test_click_and_rub_pitch_routes()
	await _test_router_clock_connection()
	if _failures.is_empty():
		print("MIDI interaction chart runtime headless tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_shipped_chart_load() -> void:
	var manager := MANAGER_SCRIPT.new() as InteractionSpotManager
	_check(manager.load_chart_file("res://data/violin_interaction_chart.json"), "Stage 1 chart failed runtime validation")
	_check(manager._chart_events.size() == 73, "Unexpected Stage 1 chart event count")


func _event(id: String, kind: String, spawn: float, pitches: Array[int]) -> Dictionary:
	var checkpoints: Array[Dictionary] = []
	for i in pitches.size():
		checkpoints.append({"note_index": i, "time": spawn + 0.8 + i * 0.25, "pitch": pitches[i]})
	return {
		"id": id, "type": kind, "spawn_time": spawn,
		"pitch": pitches[0], "checkpoints": checkpoints if kind == "slide" else [],
	}


func _make_manager(events: Array, anchor_ids: Array[String] = ["a", "b", "c", "d"]) -> Dictionary:
	var layer := Control.new()
	layer.size = Vector2(3000, 3000)
	root.add_child(layer)
	var anchor := FakeAnchor.new()
	anchor.size = layer.size
	root.add_child(anchor)
	var timer := Timer.new()
	root.add_child(timer)
	var arousal := FakeArousal.new()
	var manager := MANAGER_SCRIPT.new() as InteractionSpotManager
	manager.setup(arousal, null, layer, anchor, timer)
	manager.set_phase_config(PHASE_SCRIPT.new({"click_note_lifetime": 30.0}))
	manager.set_available_anchor_ids(anchor_ids)
	manager.set_bounds_rect(Rect2(Vector2.ZERO, layer.size))
	_check(manager.set_chart_data({"schema_version": 1, "loop_duration_seconds": 10.0, "events": events}), "Synthetic chart rejected")
	return {"manager": manager, "layer": layer, "anchor": anchor, "timer": timer, "arousal": arousal}


func _dispose(context: Dictionary) -> void:
	(context["manager"] as InteractionSpotManager).stop()
	(context["layer"] as Control).queue_free()
	(context["anchor"] as Control).queue_free()
	(context["timer"] as Timer).queue_free()


func _test_chart_sequence_and_loop() -> void:
	var context := _make_manager([
		_event("first", "click", 0.5, [60]),
		_event("second", "click", 1.6, [62]),
	])
	var manager := context["manager"] as InteractionSpotManager
	var skipped: Array[String] = []
	manager.chart_event_skipped.connect(func(id: String, reason: String) -> void: skipped.append(id + ":" + reason))
	manager.start()
	_check(manager._spawn_timer.is_stopped(), "Chart mode started the random spawn timer")
	manager.advance_chart(0.0)
	manager.advance_chart(0.5)
	manager.advance_chart(0.5)
	_check(manager._active_spots.size() == 1, "One chart event spawned twice in one loop")
	manager.stop()
	manager.start()
	manager.advance_chart(0.5)
	_check(manager._active_spots.is_empty() and manager.get_chart_debug_state()["next_index"] == 1, "Run restart replayed a consumed event")
	manager.advance_chart(9.9)
	_check(skipped.has("second:missed_time"), "Crossed event was not skipped as missed")
	manager.advance_chart(0.0)
	manager.advance_chart(0.5)
	_check(manager._active_spots.size() == 1, "Loop wrap did not spawn the event once in the new loop")
	_check(manager.get_chart_debug_state()["loop"] == 1, "Loop counter did not advance")
	_dispose(context)

	var late := _make_manager([
		_event("elapsed", "click", 0.5, [60]),
		_event("upcoming", "click", 2.7, [62]),
	])
	var late_manager := late["manager"] as InteractionSpotManager
	late_manager.start()
	late_manager.advance_chart(1.0)
	_check(late_manager._active_spots.is_empty(), "Scene entry replayed an elapsed chart event")
	_check(late_manager.get_chart_debug_state()["skip_counts"].get("late_attach", 0) == 1, "Late scene attach was not recorded")
	late_manager.advance_chart(2.7)
	_check(late_manager._active_spots.size() == 1, "Scene entry did not continue at the next event")
	_dispose(late)

	var boundary := _make_manager([_event("end", "click", 9.8, [60])])
	var boundary_manager := boundary["manager"] as InteractionSpotManager
	boundary_manager.start()
	boundary_manager.advance_chart(0.0)
	boundary_manager.advance_chart(9.7)
	boundary_manager.advance_chart(0.1)
	_check(boundary_manager.get_chart_debug_state()["skip_counts"].get("loop_wrap_missed", 0) == 1, "Loop wrap did not record an unvisited ending event")
	boundary_manager.advance_chart(9.8)
	_check(boundary_manager._active_spots.size() == 1, "Ending event did not spawn in the next loop")
	_dispose(boundary)


func _test_psychological_skip_and_resume() -> void:
	var context := _make_manager([
		_event("keep", "click", 0.5, [60]),
		_event("hidden", "click", 1.6, [62]),
		_event("after", "click", 2.7, [64]),
	])
	var manager := context["manager"] as InteractionSpotManager
	var arousal := context["arousal"] as FakeArousal
	var failures := {"count": 0}
	manager.physiological_spot_failed.connect(func(_ratio: float, _penalty: float) -> void: failures["count"] += 1)
	manager.start()
	manager.advance_chart(0.0)
	manager.advance_chart(0.5)
	var retained := manager._active_spots[0]
	manager.suspend()
	manager.advance_chart(1.6)
	_check(manager._active_spots.size() == 1 and manager._active_spots[0] == retained, "Psychological mode removed a live spot")
	_check(manager.get_chart_debug_state()["skip_counts"].get("psychological_mode", 0) == 1, "Hidden chart event was not skipped")
	manager.resume()
	manager.advance_chart(2.7)
	_check(manager._active_spots.size() == 2, "Physiological mode did not retain old and spawn new spots")
	_check(is_equal_approx(arousal.physical, 40.0), "A skipped chart event changed score")
	_check(failures["count"] == 0, "A skipped chart event emitted a gameplay failure")
	_dispose(context)

	var resumed := _make_manager([
		_event("retained", "click", 0.5, [60]),
		_event("crossed", "click", 1.6, [62]),
	])
	var resumed_manager := resumed["manager"] as InteractionSpotManager
	var clock := {"position": 0.5}
	resumed_manager.bgm_position_provider = func() -> float: return float(clock["position"])
	resumed_manager.start()
	resumed_manager.advance_chart(0.0)
	resumed_manager.advance_chart(0.5)
	resumed_manager.suspend()
	clock["position"] = 1.6
	resumed_manager.resume()
	_check(resumed_manager._active_spots.size() == 1, "Resume spawned an event crossed while hidden")
	_check(resumed_manager.get_chart_debug_state()["skip_counts"].get("psychological_mode", 0) == 1, "Resume did not mark crossed event as psychological skip")
	_check(resumed_manager.get_chart_loop_stats()["skip_reasons"].get("psychological_mode", 0) == 1, "Loop statistics missed the psychological skip")
	_dispose(resumed)


func _test_active_cap_and_placement_skip() -> void:
	var events := [
		_event("a", "click", 0.5, [60]),
		_event("b", "click", 1.6, [62]),
		_event("c", "click", 2.7, [64]),
		_event("d", "click", 3.8, [65]),
	]
	var context := _make_manager(events)
	var manager := context["manager"] as InteractionSpotManager
	manager.start()
	manager.advance_chart(0.0)
	for position in [0.5, 1.6, 2.7, 3.8]:
		manager.advance_chart(position)
	_check(manager._active_spots.size() == 3, "Chart spawning exceeded the three-spot cap")
	_check(manager.get_chart_debug_state()["skip_counts"].get("active_cap", 0) == 1, "Active-cap skip reason was not recorded")
	for i in manager._active_spots.size():
		for j in range(i + 1, manager._active_spots.size()):
			var first: Rect2 = manager._active_spots[i].get_meta("placement_rect")
			var second: Rect2 = manager._active_spots[j].get_meta("placement_rect")
			_check(not first.intersects(second, true), "Chart spots overlapped")
	_dispose(context)

	var no_anchor := _make_manager([_event("blocked", "click", 0.5, [60])], [])
	var blocked := no_anchor["manager"] as InteractionSpotManager
	blocked.start()
	blocked.advance_chart(0.0)
	blocked.advance_chart(0.5)
	_check(blocked._active_spots.is_empty(), "Event spawned without an anchor")
	_check(blocked.get_chart_debug_state()["skip_counts"].get("no_anchors", 0) == 1, "Placement skip reason was not recorded")
	_dispose(no_anchor)

	var masked := _make_manager([_event("masked", "click", 0.5, [60])])
	var masked_manager := masked["manager"] as InteractionSpotManager
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	masked_manager.set_interaction_mask(ImageTexture.create_from_image(image), masked["layer"])
	masked_manager.start()
	masked_manager.advance_chart(0.0)
	masked_manager.advance_chart(0.5)
	_check(masked_manager._active_spots.is_empty(), "Event spawned outside the allowed mask")
	_check(masked_manager.get_chart_debug_state()["skip_counts"].get("unsafe_placement", 0) == 1, "Unsafe placement skip was not recorded")
	_dispose(masked)


func _test_slide_sizes_and_bound_audio() -> void:
	for pitches_variant in [[60, 62, 64], [60, 62, 64, 65, 67, 69]]:
		var pitches: Array[int] = []
		for pitch in pitches_variant:
			pitches.append(int(pitch))
		var context := _make_manager([_event("slide", "slide", 0.5, pitches)])
		var manager := context["manager"] as InteractionSpotManager
		var heard: Array[int] = []
		manager.slide_audio_requested.connect(func(pitch: int) -> void: heard.append(pitch))
		manager.start()
		manager.advance_chart(0.0)
		manager.advance_chart(0.5)
		_check(manager._active_spots.size() == 1, "Slide placement failed for %d points" % pitches.size())
		if manager._active_spots.size() == 1:
			var slide := manager._active_spots[0] as SlideNote
			_check(slide.checkpoints.size() == pitches.size(), "Slide checkpoint count differs from chart")
			_check(is_equal_approx(slide.spot_lifetime, 2.0), "Slide checkpoint timeout changed")
			_check(slide.get_meta("checkpoint_pitches") == PackedInt32Array(pitches), "Slide checkpoint pitches were not bound")
			slide._start_drag(slide.checkpoints[0], -1)
			for checkpoint_index in range(1, slide.checkpoints.size()):
				slide._process_pointer_move(slide.checkpoints[checkpoint_index])
			_check(heard == pitches, "Slide reached checkpoints with incorrect bound pitches")
		_dispose(context)

	var audio := AUDIO_SCRIPT.new() as ViolinSamplePlayer
	audio.pitch_provider = Callable(self, "_fallback_pitch")
	root.add_child(audio)
	audio.play_click(72)
	_check(_pitch_queries == 0, "Bound Click queried live MIDI")
	_check(is_equal_approx(audio._voices[0].pitch_scale, pow(2.0, 3.0 / 12.0)), "Bound Click played wrong pitch")
	audio.play_slide_checkpoint(76)
	_check(_pitch_queries == 0, "Bound Slide queried live MIDI")
	audio.rub_motion(42, 67)
	var rub_pitch := audio._rub_player.pitch_scale
	audio.rub_motion(42, 79)
	_check(is_equal_approx(audio._rub_player.pitch_scale, rub_pitch), "Continuous Rub did not lock its pitch")
	_check(_pitch_queries == 0, "Bound Rub queried live MIDI")
	audio.stop_all()
	audio.queue_free()


func _test_click_and_rub_pitch_routes() -> void:
	var click_context := _make_manager([_event("click", "click", 0.5, [73])])
	var click_manager := click_context["manager"] as InteractionSpotManager
	var clicks: Array[int] = []
	click_manager.click_audio_requested.connect(func(pitch: int) -> void: clicks.append(pitch))
	click_manager.start()
	click_manager.advance_chart(0.0)
	click_manager.advance_chart(0.5)
	var click := click_manager._active_spots[0] as ClickNote
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click.target_center
	click._gui_input(press)
	_check(clicks == [73], "Click did not emit its chart pitch")
	_dispose(click_context)

	var rub_context := _make_manager([_event("rub", "rub", 0.5, [67])])
	var rub_manager := rub_context["manager"] as InteractionSpotManager
	var rub_pitches: Array[int] = []
	rub_manager.rub_audio_motion.connect(func(_id: int, pitch: int) -> void: rub_pitches.append(pitch))
	rub_manager.start()
	rub_manager.advance_chart(0.0)
	rub_manager.advance_chart(0.5)
	var rub := rub_manager._active_spots[0] as RubNote
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = rub.target_center
	rub._gui_input(press)
	rub._process_pointer_move(rub.target_center + Vector2(20, 0))
	_check(rub_pitches == [67], "Rub did not emit its chart pitch")
	_dispose(rub_context)


func _test_router_clock_connection() -> void:
	var router := MAIN_SCENE.instantiate()
	root.add_child(router)
	router._show_game()
	await process_frame
	var game: Variant = router.current_screen
	_check(game != null and game.bgm_position_provider.is_valid(), "Game did not receive the router BGM clock")
	_check(game.spot_manager._chart_enabled and game.spot_manager._chart_events.size() > 0, "Game did not load a chart")
	var requested_mode := OS.get_environment("VIOLIN_CHART_MODE").strip_edges().to_lower()
	var expected_mode := requested_mode.capitalize() if requested_mode in ["production", "moderate", "high"] else "Moderate"
	_check(game.spot_manager.get_chart_debug_state()["mode"] == expected_mode, "Debug game selected the wrong chart mode")
	_check(game.spot_spawn_timer.is_stopped(), "Gameplay started random spot scheduling")
	_check(router.current_bgm_key == "gameplay", "Gameplay changed the piano BGM route")
	_check(router.get_gameplay_bgm_position() >= 0.0, "Router did not expose the playing piano position")
	router.queue_free()
	await process_frame


func _fallback_pitch() -> int:
	_pitch_queries += 1
	return 69


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
