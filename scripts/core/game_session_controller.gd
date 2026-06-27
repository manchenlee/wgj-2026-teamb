@tool
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const ArousalModelClass := preload("res://scripts/gameplay/arousal_model.gd")
const DirectionSequenceControllerClass := preload("res://scripts/gameplay/direction_sequence_controller.gd")
const DialogueChoiceControllerClass := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const EndingEvaluatorClass := preload("res://scripts/gameplay/ending_evaluator.gd")

signal ending_requested(ending_type: String)

@onready var upper_layout: BoxContainer = $MarginContainer/ResponsiveLayout/UpperLayout
@onready var background_placeholder: TextureRect = $BackgroundAnchor/BackgroundPlaceholder
@onready var character_area = $MarginContainer/ResponsiveLayout/UpperLayout/CenterColumn/CenterStage/CharacterArea
@onready var arousal_visualization = $MarginContainer/ResponsiveLayout/UpperLayout/CenterColumn/CenterStage/CentralArousalVisualization
@onready var dialogue_panel = $MarginContainer/ResponsiveLayout/UpperLayout/RightSideDialoguePanel
@onready var status_hud = $MarginContainer/ResponsiveLayout/BottomHUD
@onready var feedback_timer: Timer = $FeedbackTimer
@onready var prompt_spawn_timer: Timer = $PromptSpawnTimer
@onready var active_prompt_timer: Timer = $ActivePromptTimer
@onready var choice_timeout_timer: Timer = $ChoiceTimeoutTimer

var arousal_model = ArousalModelClass.new()
var sequence_controller = DirectionSequenceControllerClass.new()
var dialogue_controller = DialogueChoiceControllerClass.new()
var feedback_rng := RandomNumberGenerator.new()
var combo: int = 0
var current_prompt: Dictionary = {}
var debug_overlay
var run_active: bool = true
var waiting_for_choice: bool = false
var pending_prompt_action: String = ""

func _ready() -> void:
	_apply_character_background()

	# In editor, only apply the preview texture.
	# Do not start gameplay timers, input handling, or runtime logic.
	if Engine.is_editor_hint():
		return

	feedback_rng.randomize()
	set_process_unhandled_input(true)
	dialogue_panel.choice_selected.connect(_on_choice_selected)
	feedback_timer.timeout.connect(_on_feedback_timer_timeout)
	prompt_spawn_timer.timeout.connect(_on_prompt_spawn_timer_timeout)
	active_prompt_timer.timeout.connect(_on_active_prompt_timer_timeout)
	choice_timeout_timer.timeout.connect(_on_choice_timeout)
	reset_run()

@export var character_background: Texture2D:
	set(value):
		character_background = value
		if is_inside_tree():
			_apply_character_background()

func _apply_character_background() -> void:
	if background_placeholder == null:
		return

	background_placeholder.texture = character_background

func _process(delta: float) -> void:
	if not run_active:
		return

	arousal_model.apply_decay(delta)
	arousal_model.update_peak(delta)
	_update_prompt_timer_visual()
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
	active_prompt_timer.stop()
	choice_timeout_timer.stop()
	pending_prompt_action = ""
	sequence_controller.clear_sequence()
	arousal_model.reset()
	dialogue_controller.reset()
	dialogue_panel.clear_history()
	character_area.clear_direction_prompts()
	waiting_for_choice = false
	_push_next_dialogue_event()
	_start_new_sequence()
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
			active_prompt_timer.stop()
			arousal_model.apply_physical(Config.PHYSICAL_GAIN_ON_CORRECT_INPUT)
			arousal_model.refresh_physical_activity()
			character_area.remove_direction_prompt(int(result.get("consumed_prompt_id", -1)))
			var auto_revealed_prompt: Dictionary = result.get("auto_revealed_prompt", {})
			if not auto_revealed_prompt.is_empty():
				_show_visible_prompt(auto_revealed_prompt)
			character_area.show_prompt_feedback(
				"Correct +%d" % int(round(Config.PHYSICAL_GAIN_ON_CORRECT_INPUT)),
				Color(0.45, 0.87, 0.56, 1.0),
				Config.CORRECT_FEEDBACK_DISPLAY_DURATION
			)
			character_area.show_correct_reaction()
			_activate_current_prompt()
			_schedule_extra_prompt_reveal()
		"sequence_complete":
			combo += 1
			active_prompt_timer.stop()
			arousal_model.apply_physical(Config.PHYSICAL_GAIN_ON_CORRECT_INPUT)
			arousal_model.apply_physical(Config.PHYSICAL_SEQUENCE_COMPLETE_BONUS)
			arousal_model.refresh_physical_activity()
			character_area.remove_direction_prompt(int(result.get("consumed_prompt_id", -1)))
			character_area.show_prompt_feedback(
				"Sequence Complete +%d" % int(round(Config.PHYSICAL_SEQUENCE_COMPLETE_BONUS)),
				Color(0.62, 0.95, 0.56, 1.0),
				Config.CORRECT_FEEDBACK_DISPLAY_DURATION + 0.1
			)
			character_area.show_correct_reaction()
			_schedule_new_sequence()
		"wrong":
			_handle_wrong_input()
	_update_presentation()

func _on_choice_selected(choice_quality: String, choice_text: String) -> void:
	choice_timeout_timer.stop()
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
	active_prompt_timer.stop()
	arousal_model.apply_physical(-Config.PHYSICAL_PENALTY_ON_WRONG_INPUT)
	arousal_model.refresh_physical_activity()
	sequence_controller.clear_sequence()
	character_area.clear_direction_prompts()
	character_area.show_prompt_feedback(
		"Wrong -%d" % int(round(Config.PHYSICAL_PENALTY_ON_WRONG_INPUT)),
		Color(0.95, 0.35, 0.35, 1.0),
		Config.WRONG_FEEDBACK_DISPLAY_DURATION
	)
	character_area.show_mistake_reaction()
	_schedule_new_sequence()

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
	active_prompt_timer.stop()
	choice_timeout_timer.stop()

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
		choice_timeout_timer.start(Config.CHOICE_TIMEOUT_SECONDS)
	else:
		waiting_for_choice = false
		dialogue_panel.hide_prompt()
		dialogue_panel.append_history(str(current_prompt.get("text", Config.FEEDBACK_MESSAGE_TEXT)), "companion")
		dialogue_panel.hide_choices()
		choice_timeout_timer.stop()
		_schedule_next_feedback_message()

func _start_new_sequence() -> void:
	prompt_spawn_timer.stop()
	character_area.clear_direction_prompts()
	var first_prompt := sequence_controller.start_sequence()
	if not first_prompt.is_empty():
		_show_visible_prompt(first_prompt)
	_activate_current_prompt()
	_schedule_extra_prompt_reveal()

func _schedule_new_sequence() -> void:
	pending_prompt_action = "new_sequence"
	var wait_time := feedback_rng.randf_range(
		Config.PROMPT_SPAWN_DELAY_MIN,
		Config.PROMPT_SPAWN_DELAY_MAX
	)
	prompt_spawn_timer.start(wait_time)

func _on_prompt_spawn_timer_timeout() -> void:
	var action := pending_prompt_action
	pending_prompt_action = ""
	match action:
		"reveal_extra":
			var prompt := sequence_controller.reveal_next_prompt()
			if not prompt.is_empty():
				_show_visible_prompt(prompt)
			_schedule_extra_prompt_reveal()
		"new_sequence":
			_start_new_sequence()
	_update_presentation()

func _on_active_prompt_timer_timeout() -> void:
	if not run_active:
		return
	_handle_wrong_input()
	_update_presentation()

func _update_prompt_timer_visual() -> void:
	if active_prompt_timer.is_stopped():
		return
	var progress := active_prompt_timer.time_left / Config.DIRECTION_PROMPT_TIME_LIMIT
	character_area.set_prompt_time_progress(progress)

func _show_visible_prompt(prompt: Dictionary) -> void:
	character_area.show_direction_prompt(
		int(prompt.get("prompt_id", -1)),
		str(prompt.get("direction", "")),
		prompt.get("anchor_offset", Vector2.ZERO)
	)
	print_debug("prompt spawn: %s" % sequence_controller.get_prompt_debug_state())

func _activate_current_prompt() -> void:
	var prompt := sequence_controller.get_current_prompt()
	if prompt.is_empty():
		active_prompt_timer.stop()
		return
	character_area.set_current_prompt(int(prompt.get("step_index", -1)))
	character_area.set_prompt_time_progress(1.0)
	active_prompt_timer.start(Config.DIRECTION_PROMPT_TIME_LIMIT)

func _schedule_extra_prompt_reveal() -> void:
	if not sequence_controller.has_more_hidden_prompts():
		return
	if pending_prompt_action == "new_sequence":
		return
	pending_prompt_action = "reveal_extra"
	var wait_time := feedback_rng.randf_range(
		Config.NEXT_PROMPT_REVEAL_DELAY,
		Config.PROMPT_SPAWN_DELAY_MAX
	)
	prompt_spawn_timer.start(wait_time)

func _on_choice_timeout() -> void:
	if not run_active or not waiting_for_choice:
		return
	waiting_for_choice = false
	dialogue_panel.hide_prompt()
	dialogue_panel.hide_choices()
	character_area.show_ignored_reaction()
	dialogue_panel.append_history(Config.FEEDBACK_MESSAGE_TEXT, "companion")
	_schedule_next_feedback_message()
	_update_presentation()
