extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const ArousalModelClass := preload("res://scripts/gameplay/arousal_model.gd")
const DirectionSequenceControllerClass := preload("res://scripts/gameplay/direction_sequence_controller.gd")
const DialogueChoiceControllerClass := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const EndingEvaluatorClass := preload("res://scripts/gameplay/ending_evaluator.gd")

signal ending_requested(ending_type: String)

@onready var upper_layout: BoxContainer = $MarginContainer/ResponsiveLayout/UpperLayout
@onready var character_area = $MarginContainer/ResponsiveLayout/UpperLayout/CenterColumn/CenterStage/CharacterArea
@onready var arousal_visualization = $MarginContainer/ResponsiveLayout/UpperLayout/CenterColumn/CenterStage/CentralArousalVisualization
@onready var dialogue_panel = $MarginContainer/ResponsiveLayout/UpperLayout/RightSideDialoguePanel
@onready var status_hud = $MarginContainer/ResponsiveLayout/BottomHUD
@onready var feedback_timer: Timer = $FeedbackTimer
@onready var round_restart_timer: Timer = $RoundRestartTimer

var arousal_model = ArousalModelClass.new()
var sequence_controller = DirectionSequenceControllerClass.new()
var dialogue_controller = DialogueChoiceControllerClass.new()
var feedback_rng := RandomNumberGenerator.new()
var combo: int = 0
var current_prompt: Dictionary = {}
var debug_overlay
var run_active: bool = true

func _ready() -> void:
	feedback_rng.randomize()
	status_hud.direction_pressed.connect(_on_direction_pressed)
	dialogue_panel.choice_selected.connect(_on_choice_selected)
	feedback_timer.timeout.connect(_on_feedback_timer_timeout)
	round_restart_timer.timeout.connect(_start_round)
	reset_run()

func _process(delta: float) -> void:
	if not run_active:
		return

	arousal_model.apply_decay(delta)
	arousal_model.update_peak(delta)

	if sequence_controller.tick(delta):
		print_debug("round timeout")
		_handle_round_failure()

	_update_presentation()
	_check_ending()

func _input(event: InputEvent) -> void:
	if not run_active:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var direction := ""
		match event.keycode:
			KEY_LEFT, KEY_A:
				direction = "Left"
			KEY_RIGHT, KEY_D:
				direction = "Right"
			KEY_UP, KEY_W:
				direction = "Up"
			KEY_DOWN, KEY_S:
				direction = "Down"
		if not direction.is_empty():
			_on_direction_pressed(direction)

func reset_run() -> void:
	print_debug("reset run")
	run_active = true
	combo = 0
	round_restart_timer.stop()
	arousal_model.reset()
	dialogue_panel.clear_history()
	current_prompt = dialogue_controller.next_prompt(arousal_model.physical, arousal_model.emotional)
	dialogue_panel.set_prompt(current_prompt)
	dialogue_panel.append_history(Config.TEST_FEEDBACK_TEXT)
	_schedule_next_feedback_message()
	_start_round()
	_update_presentation()

func apply_debug_values(value: float) -> void:
	arousal_model.physical = value
	arousal_model.emotional = value
	arousal_model.peak = value
	_update_presentation()

func force_ending(ending_type: String) -> void:
	_stop_runtime_timers()
	run_active = false
	ending_requested.emit(ending_type)

func get_debug_state() -> Dictionary:
	return {
		"screen": Config.SCREEN_GAME,
		"physical": int(round(arousal_model.physical)),
		"emotional": int(round(arousal_model.emotional)),
		"peak": int(round(arousal_model.peak)),
		"combo": combo,
		"round": "active" if sequence_controller.round_active else "waiting",
		"sequence": sequence_controller.get_sequence_text()
	}

func _start_round() -> void:
	sequence_controller.start_round()
	print_debug("round start: %s" % [str(sequence_controller.current_sequence)])
	_update_presentation()

func _on_feedback_timer_timeout() -> void:
	if not run_active:
		return
	dialogue_panel.append_history(Config.TEST_FEEDBACK_TEXT)
	print_debug("feedback message")
	_schedule_next_feedback_message()

func _on_direction_pressed(direction: String) -> void:
	if not run_active:
		return
	var result: Dictionary = sequence_controller.submit_input(direction)
	match str(result.get("result", "")):
		"correct":
			combo += 1
			arousal_model.apply_physical(Config.PHYSICAL_GAIN_PER_CORRECT_INPUT)
			character_area.show_correct_reaction()
		"round_success":
			combo += 1
			arousal_model.apply_physical(Config.PHYSICAL_GAIN_PER_CORRECT_INPUT)
			character_area.show_correct_reaction()
			print_debug("round success")
			_schedule_next_round()
		"wrong":
			_handle_wrong_input()
		"round_failure":
			print_debug("round failure")
			_handle_round_failure()
	_update_presentation()

func _on_choice_selected(choice_quality: String) -> void:
	var outcome := dialogue_controller.apply_choice(choice_quality, arousal_model)
	dialogue_panel.append_history(str(outcome.get("reply", "Companion: ...")))
	character_area.show_choice_reaction(choice_quality)
	current_prompt = dialogue_controller.next_prompt(arousal_model.physical, arousal_model.emotional)
	dialogue_panel.set_prompt(current_prompt)
	_update_presentation()

func _handle_wrong_input() -> void:
	combo = 0
	arousal_model.apply_physical(-Config.PHYSICAL_PENALTY_PER_WRONG_INPUT)
	character_area.show_mistake_reaction()

func _handle_round_failure() -> void:
	_handle_wrong_input()
	_schedule_next_round()

func _schedule_next_round() -> void:
	round_restart_timer.start(Config.ROUND_RESTART_DELAY)

func _check_ending() -> void:
	var ending_type := EndingEvaluatorClass.evaluate(arousal_model)
	if ending_type.is_empty():
		return
	print_debug("ending: %s" % ending_type)
	_stop_runtime_timers()
	run_active = false
	ending_requested.emit(ending_type)

func _update_presentation() -> void:
	character_area.update_emotion_state(arousal_model.get_emotion_state())
	arousal_visualization.set_values(arousal_model.physical, arousal_model.emotional, arousal_model.peak)
	status_hud.update_values(arousal_model.physical, arousal_model.emotional, arousal_model.peak)
	status_hud.update_combo(combo)
	status_hud.update_timer(sequence_controller.time_left)
	status_hud.update_sequence_text(sequence_controller.get_sequence_text())
	_update_layout_mode()
	if debug_overlay != null:
		debug_overlay.sync_live_readout(get_debug_state())

func _update_layout_mode() -> void:
	upper_layout.vertical = size.x < Config.DESKTOP_BREAKPOINT

func _stop_runtime_timers() -> void:
	feedback_timer.stop()
	round_restart_timer.stop()

func _schedule_next_feedback_message() -> void:
	var wait_time := feedback_rng.randf_range(
		Config.FEEDBACK_MESSAGE_INTERVAL_MIN,
		Config.FEEDBACK_MESSAGE_INTERVAL_MAX
	)
	feedback_timer.start(wait_time)
