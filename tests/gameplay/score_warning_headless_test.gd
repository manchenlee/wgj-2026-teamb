extends SceneTree

const GAME_SCREEN_SCENE := preload("res://scenes/screens/GameScreen.tscn")

const PSYCHOLOGICAL_MODE := 0
const PHYSIOLOGICAL_MODE := 1

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_SCREEN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)

	var event_counts := {"low": 0, "imbalance": 0}
	game.score_warning_changed.connect(
		func(_physical_low: bool, _emotional_low: bool) -> void: event_counts.low += 1
	)
	game.score_imbalance_changed.connect(
		func(_active: bool, _lower_mode: int) -> void: event_counts.imbalance += 1
	)

	_set_scores_and_sync(game, 21.0, 21.0)
	_assert(not game.physical_low_warning_active, "Physical 21 incorrectly activated a low warning.")
	_assert(not game.emotional_low_warning_active, "Emotional 21 incorrectly activated a low warning.")

	_set_scores_and_sync(game, 20.0, 21.0)
	_assert(game.physical_low_warning_active, "Physical 20 did not activate its low warning.")
	_assert(not game.emotional_low_warning_active, "Physical-low entry affected the emotional warning.")
	var physical_entry_events: int = event_counts.low
	_set_scores_and_sync(game, 18.0, 21.0)
	_assert(event_counts.low == physical_entry_events, "Remaining physically low repeated the entry event.")
	_set_scores_and_sync(game, 23.0, 21.0)
	_assert(not game.physical_low_warning_active, "Physical recovery above 20 did not clear its warning.")

	_set_scores_and_sync(game, 23.0, 20.0)
	_assert(game.emotional_low_warning_active, "Emotional 20 did not activate its low warning.")
	_assert(not game.physical_low_warning_active, "Emotional-low entry affected the physical warning.")
	var emotional_entry_events: int = event_counts.low
	_set_scores_and_sync(game, 23.0, 18.0)
	_assert(event_counts.low == emotional_entry_events, "Remaining emotionally low repeated the entry event.")
	_set_scores_and_sync(game, 23.0, 22.0)
	_assert(not game.emotional_low_warning_active, "Emotional recovery above 20 did not clear its warning.")

	_set_scores_and_sync(game, 20.0, 20.0)
	_assert(
		game.physical_low_warning_active and game.emotional_low_warning_active,
		"Both scores at 20 did not report both low warnings."
	)
	_set_scores_and_sync(game, 50.0, 31.0)
	_assert(not game.imbalance_warning_active, "Difference 19 incorrectly activated imbalance.")

	_set_scores_and_sync(game, 50.0, 30.0)
	_assert(game.imbalance_warning_active, "Difference 20 did not activate imbalance.")
	_assert(game.lower_score_mode == PSYCHOLOGICAL_MODE, "Emotional-lower imbalance did not identify PSYCHOLOGICAL.")
	var imbalance_entry_events: int = event_counts.imbalance
	_set_scores_and_sync(game, 55.0, 30.0)
	_assert(event_counts.imbalance == imbalance_entry_events, "Persistent imbalance repeated the entry event.")

	_set_scores_and_sync(game, 29.0, 50.0)
	_assert(game.imbalance_warning_active, "Cross-side imbalance unexpectedly cleared.")
	_assert(game.lower_score_mode == PHYSIOLOGICAL_MODE, "Physical-lower imbalance did not identify PHYSIOLOGICAL.")
	_assert(event_counts.imbalance == imbalance_entry_events + 1, "Changing the lower side did not emit exactly one state update.")

	_set_scores_and_sync(game, 40.0, 40.0)
	_assert(not game.imbalance_warning_active, "Equal scores produced an imbalance warning.")
	_assert(game.lower_score_mode == -1, "Cleared imbalance retained a lower-mode state.")
	_set_scores_and_sync(game, 50.0, 30.0)
	_assert(game.imbalance_warning_active, "Imbalance did not re-enter for the clear-boundary test.")
	_set_scores_and_sync(game, 49.0, 30.0)
	_assert(not game.imbalance_warning_active, "Returning to difference 19 did not clear imbalance.")

	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("Score warning policy headless tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _set_scores_and_sync(game, physical: float, emotional: float) -> void:
	game.arousal_model.physical = physical
	game.arousal_model.emotional = emotional
	game._update_score_warning_state()


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
