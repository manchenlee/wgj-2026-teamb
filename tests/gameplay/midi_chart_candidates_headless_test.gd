extends SceneTree

const MANAGER_SCRIPT := preload("res://scripts/gameplay/interaction_spot_manager.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for name in ["moderate", "high", "moderate_gap_fill_candidate"]:
		var manager := MANAGER_SCRIPT.new() as InteractionSpotManager
		var path := "res://data/violin_interaction_chart_%s.json" % name
		if not manager.load_chart_file(path):
			_failures.append("%s candidate failed runtime schema validation" % name)
			continue
		if manager._chart_events.is_empty():
			_failures.append("%s candidate has no events" % name)
		for event: Dictionary in manager._chart_events:
			if String(event["type"]) == "slide":
				var count := (event["checkpoints"] as Array).size()
				if count < 3 or count > 6:
					_failures.append("%s Slide group has %d points" % [name, count])
				for checkpoint: Dictionary in event["checkpoints"]:
					if int(checkpoint["pitch"]) < 0 or int(checkpoint["pitch"]) > 127:
						_failures.append("%s checkpoint pitch invalid" % name)
		if name == "moderate_gap_fill_candidate":
			var approved := MANAGER_SCRIPT.new() as InteractionSpotManager
			if not approved.load_chart_file("res://data/violin_interaction_chart_moderate.json"):
				_failures.append("Approved Moderate unavailable")
			else:
				var added := 0
				for event: Dictionary in manager._chart_events:
					if String(event.get("origin", "")) == "gap_fill":
						added += 1
						var beat := roundf(float(event["source_start_time"]) / (60.0 / 155.0))
						if absf(float(event["source_start_time"]) - beat * (60.0 / 155.0)) > 0.000002:
							_failures.append("Gap Fill Click target is off quarter-note grid")
				if added < 2 or manager._chart_events.size() != approved._chart_events.size() + added:
					_failures.append("Gap Fill event count differs from offline report")
	if _failures.is_empty():
		print("MIDI candidate chart runtime-schema tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
