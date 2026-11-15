extends SceneTree

const CONTROLLER := preload("res://scripts/core/game_session_controller.gd")
const MANAGER := preload("res://scripts/gameplay/interaction_spot_manager.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(OS.get_environment("VIOLIN_CHART_MODE").is_empty(), "Chart mode environment override must be absent")
	_check(OS.get_environment("VIOLIN_CHART_SEED").is_empty(), "Chart seed environment override must be absent")
	for path in [
		"res://data/violin_interaction_chart_moderate_gap_fill_variants.json",
		"res://data/violin_interaction_chart_moderate_variants.json",
		"res://data/violin_interaction_chart_moderate.json",
	]:
		_check(FileAccess.file_exists(path), "Export is missing %s" % path)
	var controller := CONTROLLER.new()
	var manager := MANAGER.new() as InteractionSpotManager
	controller._load_interaction_chart(manager)
	_check(manager.get_chart_debug_state()["mode"] == "Moderate_Gap_Fill", "Fresh launch did not select Gap Fill")
	_check(manager.get_chart_loop_stats()["scheduled_gap_fill_clicks"] == 10, "Default loop has wrong Gap Fill density")
	var first_ids: Array[String] = []
	for event: Dictionary in manager._chart_events:
		if String(event.get("origin", "")) == "gap_fill":
			first_ids.append(String(event["id"]))
	manager._chart_loop_index = 1
	manager._select_chart_variant(1)
	_check(manager.get_chart_debug_state()["variant_index"] == 1, "BGM loop index did not select variant 1")
	var next_ids: Array[String] = []
	for event: Dictionary in manager._chart_events:
		if String(event.get("origin", "")) == "gap_fill":
			next_ids.append(String(event["id"]))
	_check(next_ids.size() == 10 and first_ids != next_ids, "Consecutive loops did not vary deterministically")
	var fallback := MANAGER.new() as InteractionSpotManager
	controller._load_interaction_chart(fallback, "res://data/missing_gap_fill_bank.json")
	_check(fallback.get_chart_debug_state()["mode"] == "Moderate", "Missing Gap Fill bank did not use Moderate fallback")
	controller.free()
	if _failures.is_empty():
		print("Gap Fill export runtime tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
