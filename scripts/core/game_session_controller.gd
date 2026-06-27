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
@onready var prompt_spawn_timer: Timer = $PromptSpawnTimer

var arousal_model = ArousalModelClass.new()
var sequence_controller = DirectionSequenceControllerClass.new()
var dialogue_controller = DialogueChoiceControllerClass.new()
var feedback_rng := RandomNumberGenerator.new()
var combo: int = 0
var current_prompt: Dictionary = {}
var debug_overlay
var run_active: bool = true
var waiting_for_choice: bool = false

func _ready() -> void:
	feedback_rng.randomize()
	set_process_unhandled_input(true)
	dialogue_panel.choice_selected.connect(_on_choice_selected)
	feedback_timer.timeout.connect(_on_feedback_timer_timeout)
	prompt_spawn_timer.timeout.connect(_spawn_direction_prompt)
	reset_run()

func _process(delta: float) -> void:
	if not run_active:
		return

	arousal_model.apply_decay(delta)
	arousal_model.update_peak(delta)
	_update_presentation()
	_check_ending()

func _unhandled_input(event: InputEvent) -> void:
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
			get_viewport().set_input_as_handled()
			_on_direction_pressed(direction)

func reset_run() -> void:
	print_debug("reset run")
	run_active = true
	combo = 0
	prompt_spawn_timer.stop()
	feedback_timer.stop()
	sequence_controller.clear_prompt()
	arousal_model.reset()
	dialogue_controller.reset()
	dialogue_panel.clear_history()
	character_area.clear_direction_prompt()
	waiting_for_choice = false
	_push_next_dialogue_event()
	_spawn_direction_prompt()
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
		"prompt": sequence_controller.get_prompt_debug_state()
	}

func _spawn_direction_prompt() -> void:
	var prompt := sequence_controller.spawn_prompt()
	character_area.show_direction_prompt(
		str(prompt.get("direction", "")),
		prompt.get("anchor_offset", Vector2.ZERO)
	)
	print_debug("prompt spawn: %s" % sequence_controller.get_prompt_debug_state())
	_update_presentation()

func _on_feedback_timer_timeout() -> void:
	if not run_active or waiting_for_choice:
		return
	_push_next_dialogue_event()
	print_debug("feedback message")

func _on_direction_pressed(direction: String) -> void:
	if not run_active:
		return
	var result: Dictionary = sequence_controller.submit_input(direction)
	print_debug(
		"direction input: %s -> %s (combo=%d physical=%.1f prompt=%s)" % [
			direction,
			str(result.get("result", "unknown")),
			combo,
			arousal_model.physical,
			sequence_controller.get_prompt_debug_state()
		]
	)
	match str(result.get("result", "")):
		"correct":
			combo += 1
			arousal_model.apply_physical(Config.PHYSICAL_GAIN_ON_CORRECT_INPUT)
			arousal_model.refresh_physical_activity()
			character_area.clear_direction_prompt()
			character_area.show_prompt_feedback(
				"Correct +%d" % int(round(Config.PHYSICAL_GAIN_ON_CORRECT_INPUT)),
				Color(0.45, 0.87, 0.56, 1.0),
				Config.CORRECT_FEEDBACK_DISPLAY_DURATION
			)
			character_area.show_correct_reaction()
			_schedule_next_prompt()
		"wrong":
			_handle_wrong_input()
	_update_presentation()

func _on_choice_selected(choice_quality: String, choice_text: String) -> void:
	dialogue_panel.append_history(choice_text, "player")
	dialogue_panel.hide_prompt()
	dialogue_panel.hide_choices()
	waiting_for_choice = false
	var outcome := dialogue_controller.apply_choice(choice_quality, arousal_model)
	arousal_model.refresh_emotional_activity()
	dialogue_panel.append_history(str(outcome.get("reply", Config.FEEDBACK_MESSAGE_TEXT)), "companion")
	character_area.show_choice_reaction(choice_quality)
	_schedule_next_feedback_message()
	_update_presentation()

func _handle_wrong_input() -> void:
	combo = 0
	arousal_model.apply_physical(-Config.PHYSICAL_PENALTY_ON_WRONG_INPUT)
	arousal_model.refresh_physical_activity()
	sequence_controller.clear_prompt()
	character_area.clear_direction_prompt()
	character_area.show_prompt_feedback(
		"Wrong -%d" % int(round(Config.PHYSICAL_PENALTY_ON_WRONG_INPUT)),
		Color(0.95, 0.35, 0.35, 1.0),
		Config.WRONG_FEEDBACK_DISPLAY_DURATION
	)
	character_area.show_mistake_reaction()
	_schedule_next_prompt()

func _schedule_next_prompt() -> void:
	var wait_time := feedback_rng.randf_range(
		Config.PROMPT_SPAWN_DELAY_MIN,
		Config.PROMPT_SPAWN_DELAY_MAX
	)
	prompt_spawn_timer.start(wait_time)

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
	_update_layout_mode()
	if debug_overlay != null:
		debug_overlay.sync_live_readout(get_debug_state())

func _update_layout_mode() -> void:
	upper_layout.vertical = size.x < Config.DESKTOP_BREAKPOINT

func _stop_runtime_timers() -> void:
	feedback_timer.stop()
	prompt_spawn_timer.stop()

func _schedule_next_feedback_message() -> void:
	var wait_time := feedback_rng.randf_range(
		Config.FEEDBACK_MESSAGE_INTERVAL_MIN,
		Config.FEEDBACK_MESSAGE_INTERVAL_MAX
	)
	feedback_timer.start(wait_time)

func _push_next_dialogue_event() -> void:
	current_prompt = dialogue_controller.next_event(arousal_model.physical, arousal_model.emotional)
	if current_prompt.has("choices"):
		waiting_for_choice = true
		dialogue_panel.show_prompt(str(current_prompt.get("text", Config.CHOICE_PROMPT_TEXT)))
		dialogue_panel.show_choices(current_prompt.get("choices", {}))
		feedback_timer.stop()
	else:
		waiting_for_choice = false
		dialogue_panel.hide_prompt()
		dialogue_panel.append_history(str(current_prompt.get("text", Config.FEEDBACK_MESSAGE_TEXT)), "companion")
		dialogue_panel.hide_choices()
		_schedule_next_feedback_message()
