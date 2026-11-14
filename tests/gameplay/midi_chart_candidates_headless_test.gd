extends SceneTree

const MANAGER_SCRIPT := preload("res://scripts/gameplay/interaction_spot_manager.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for name in ["moderate", "high"]:
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
	if _failures.is_empty():
		print("MIDI candidate chart runtime-schema tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)
