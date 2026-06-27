@tool
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const ArousalModelClass := preload("res://scripts/gameplay/arousal_model.gd")
const DirectionSequenceControllerClass := preload("res://scripts/gameplay/direction_sequence_controller.gd")
const DialogueChoiceControllerClass := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const EndingEvaluatorClass := preload("res://scripts/gameplay/ending_evaluator.gd")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")
const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const TITLE_SCENE := preload("res://scenes/screens/TitleScreen.tscn")
const CHARACTER_VISUAL_PATHS := {
	"draft": "res://assets/art/character/draft.png",
	"overall_init": "res://assets/art/character/phase1/overall_init.png",
	"overall_medium": "res://assets/art/character/phase1/overall_medium.png",
	"overall_high": "res://assets/art/character/phase1/overall_high.png",
	"physic_high_mental_low": "res://assets/art/character/phase1/physic_high_mental_low.png.png",
	"physic_high_mental_low_gameover": "res://assets/art/character/phase1/physic_high_mental_low_gameover.png",
	"physic_low_mental_high": "res://assets/art/character/phase1/physic_low_mental_high.png",
	"physic_low_mental_high_gameover": "res://assets/art/character/phase1/physic_low_mental_high_gameover.png"
}
const OVERLAY_MOTION_ASSET_PATHS := {
	"tentacle1": [
		"res://assets/art/character/phase1/tentacle1_1.png",
		"res://assets/art/character/phase1/tentacle1_2.png"
	],
	"tentacle2": [
		"res://assets/art/character/phase1/tentacle2_1.png",
		"res://assets/art/character/phase1/tentacle2_2.png"
	],
	"tentacle3": [
		"res://assets/art/character/phase1/tentacle3_1.png",
		"res://assets/art/character/phase1/tentacle3_2.png"
	],
	"tentacle4": [
		"res://assets/art/character/phase1/tentacle4_1.png",
		"res://assets/art/character/phase1/tentacle4_2.png"
	]
}

signal ending_requested(ending_type: String)

@export var show_layout_debug_bounds: bool = false

@onready var background_placeholder: TextureRect = $BackgroundAnchor/BackgroundPlaceholder
@onready var overlay_animator = $BackgroundAnchor/OverlayAnimator
@onready var main_character_area: Control = $MainCharacterArea
@onready var character_area = $MainCharacterArea/CharacterArea
@onready var character_prompt_region: Control = $MainCharacterArea/CharacterPromptRegion
@onready var arousal_visualization = $MainCharacterArea/CentralArousalVisualization
@onready var dialogue_panel = $RightSideDialoguePanel
@onready var status_hud = $BottomHUD
@onready var layout_debug_regions := [
	$MainCharacterArea/DebugRegionTint,
	$RightSideDialoguePanel/DebugRegionTint,
	$BottomHUD/DebugRegionTint
]
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
var prompt_expiration_times: Dictionary = {}
var character_visual_textures: Dictionary = {}
var character_visual_warnings_printed: Dictionary = {}
var overlay_motion_set: Dictionary = {}
var ending_transition_started: bool = false

func _ready() -> void:
	_cache_character_visual_textures()
	overlay_motion_set = _build_overlay_motion_set()
	_apply_character_background()
	_update_character_visual_state()
	_apply_overlay_motion_set()
	_update_layout_debug_regions()

	# In editor, only apply the preview texture.
	# Do not start gameplay timers, input handling, or runtime logic.
	if Engine.is_editor_hint():
		set_process(false)
		set_process_unhandled_input(false)
		return

	feedback_rng.randomize()
	set_process_unhandled_input(true)
	_sync_prompt_anchor_layout()
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
			_update_character_visual_state()

func _apply_character_background() -> void:
	if background_placeholder == null:
		return

	background_placeholder.texture = character_background

func _cache_character_visual_textures() -> void:
	character_visual_textures.clear()
	for state_name_variant in CHARACTER_VISUAL_PATHS.keys():
		var state_name := String(state_name_variant)
		var asset_path := String(CHARACTER_VISUAL_PATHS[state_name])
		if not ResourceLoader.exists(asset_path):
			_warn_character_visual_once(
				"missing:%s" % asset_path,
				"Character visual asset missing: %s" % asset_path
			)
			continue
		var texture := load(asset_path) as Texture2D
		if texture == null:
			_warn_character_visual_once(
				"load_failed:%s" % asset_path,
				"Character visual asset failed to load: %s" % asset_path
			)
			continue
		character_visual_textures[state_name] = texture

	if not character_visual_textures.has("draft") and character_background != null:
		character_visual_textures["draft"] = character_background

func _build_overlay_motion_set() -> Dictionary:
	var motion_set: Dictionary = {}
	for motion_id_variant in OVERLAY_MOTION_ASSET_PATHS.keys():
		var motion_id := String(motion_id_variant)
		var frame_paths_variant = OVERLAY_MOTION_ASSET_PATHS[motion_id]
		if typeof(frame_paths_variant) != TYPE_ARRAY:
			_warn_character_visual_once(
				"overlay_malformed:%s" % motion_id,
				"Overlay motion '%s' is malformed; expected 2 frame paths." % motion_id
			)
			continue
		var frame_paths: Array = frame_paths_variant
		if frame_paths.size() != 2:
			_warn_character_visual_once(
				"overlay_bad_count:%s" % motion_id,
				"Overlay motion '%s' must contain exactly 2 frame paths." % motion_id
			)
			continue
		var frames: Array[Texture2D] = []
		var missing_frame := false
		for frame_path_variant in frame_paths:
			var frame_path := String(frame_path_variant)
			if not ResourceLoader.exists(frame_path):
				_warn_character_visual_once(
					"overlay_missing:%s" % frame_path,
					"Overlay motion asset missing: %s" % frame_path
				)
				missing_frame = true
				break
			var frame_texture := load(frame_path) as Texture2D
			if frame_texture == null:
				_warn_character_visual_once(
					"overlay_load_failed:%s" % frame_path,
					"Overlay motion asset failed to load: %s" % frame_path
				)
				missing_frame = true
				break
			frames.append(frame_texture)
		if missing_frame:
			continue
		motion_set[motion_id] = frames
	return motion_set

func _apply_overlay_motion_set() -> void:
	if overlay_animator == null:
		return
	overlay_animator.set_motion_set(overlay_motion_set)

func _warn_character_visual_once(warning_key: String, message: String) -> void:
	if character_visual_warnings_printed.has(warning_key):
		return
	character_visual_warnings_printed[warning_key] = true
	push_warning(message)

func _update_character_visual_state(forced_ending_type: String = "") -> void:
	if background_placeholder == null:
		return

	var visual_state := _get_character_visual_state_key(forced_ending_type)
	var next_texture := _get_character_visual_texture(visual_state)
	if next_texture == null:
		return
	if background_placeholder.texture == next_texture:
		return
	background_placeholder.texture = next_texture

func _get_character_visual_state_key(forced_ending_type: String = "") -> String:
	if forced_ending_type == Config.PHYSICAL_IMBALANCE_FAILURE_ENDING:
		return "physic_high_mental_low_gameover"
	if forced_ending_type == Config.EMOTIONAL_IMBALANCE_FAILURE_ENDING:
		return "physic_low_mental_high_gameover"

	var mismatch_low_threshold := Config.MINIMUM_ACTIVE_THRESHOLD
	var mismatch_high_threshold := Config.FEEDBACK_EMOTIONAL_HIGH_THRESHOLD
	if arousal_model.physical >= mismatch_high_threshold and arousal_model.emotional < mismatch_low_threshold:
		return "physic_high_mental_low"
	if arousal_model.emotional >= mismatch_high_threshold and arousal_model.physical < mismatch_low_threshold:
		return "physic_low_mental_high"
	if arousal_model.peak >= mismatch_high_threshold:
		return "overall_high"
	if arousal_model.peak >= mismatch_low_threshold:
		return "overall_medium"
	return "overall_init"

func _get_character_visual_texture(visual_state: String) -> Texture2D:
	if character_visual_textures.has(visual_state):
		return character_visual_textures[visual_state] as Texture2D

	var missing_path := String(CHARACTER_VISUAL_PATHS.get(visual_state, "unknown"))
	_warn_character_visual_once(
		"fallback:%s" % visual_state,
		"Character visual state '%s' missing, falling back. Expected asset: %s" % [visual_state, missing_path]
	)
	if visual_state != "overall_init" and character_visual_textures.has("overall_init"):
		return character_visual_textures["overall_init"] as Texture2D
	if character_visual_textures.has("draft"):
		return character_visual_textures["draft"] as Texture2D
	return character_background

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and not Engine.is_editor_hint():
		_sync_prompt_anchor_layout()
	elif what == NOTIFICATION_PREDELETE and overlay_animator != null:
		overlay_animator.stop()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not run_active:
		return

	arousal_model.apply_decay(delta)
	arousal_model.update_peak(delta)
	if _check_prompt_timeouts():
		return
	_update_prompt_timer_visual()
	_update_choice_timer_visual()
	_update_presentation()
	_check_ending()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
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
	ending_transition_started = false
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
	prompt_expiration_times.clear()
	character_area.clear_direction_prompts()
	waiting_for_choice = false
	_apply_overlay_motion_set()
	if overlay_animator != null:
		overlay_animator.play_idle()
	_push_next_dialogue_event()
	_start_new_sequence()
	_update_presentation()

func apply_debug_values(value: float) -> void:
	arousal_model.physical = value
	arousal_model.emotional = value
	arousal_model.peak = value
	_update_presentation()

func force_ending(ending_type: String) -> void:
	_begin_ending_transition(ending_type)

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
			arousal_model.apply_physical(Config.PHYSICAL_GAIN_ON_CORRECT_INPUT)
			arousal_model.refresh_physical_activity()
			_remove_prompt(int(result.get("consumed_prompt_id", -1)))
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
			arousal_model.apply_physical(Config.PHYSICAL_GAIN_ON_CORRECT_INPUT)
			arousal_model.apply_physical(Config.PHYSICAL_SEQUENCE_COMPLETE_BONUS)
			arousal_model.refresh_physical_activity()
			_remove_prompt(int(result.get("consumed_prompt_id", -1)))
			character_area.show_prompt_feedback(
				"Sequence Complete +%d" % int(round(Config.PHYSICAL_SEQUENCE_COMPLETE_BONUS)),
				Color(0.62, 0.95, 0.56, 1.0),
				Config.CORRECT_FEEDBACK_DISPLAY_DURATION + 0.1
			)
			character_area.show_correct_reaction()
			if overlay_animator != null:
				overlay_animator.play_burst_random()
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
	prompt_expiration_times.clear()
	character_area.clear_direction_prompts()
	character_area.show_prompt_feedback(
		"Wrong -%d" % int(round(Config.PHYSICAL_PENALTY_ON_WRONG_INPUT)),
		Color(0.95, 0.35, 0.35, 1.0),
		Config.WRONG_FEEDBACK_DISPLAY_DURATION
	)
	character_area.show_mistake_reaction()
	_schedule_new_sequence()

func _check_ending() -> void:
	if ending_transition_started:
		return
	var ending_type := EndingEvaluatorClass.evaluate(arousal_model)
	if ending_type.is_empty():
		return
	print_debug("ending: %s" % ending_type)
	_begin_ending_transition(ending_type)

func _begin_ending_transition(ending_type: String) -> void:
	if ending_transition_started:
		return
	ending_transition_started = true
	_stop_runtime_timers()
	run_active = false
	_update_character_visual_state(ending_type)
	_complete_ending_transition_after_frame(ending_type)

func _complete_ending_transition_after_frame(ending_type: String) -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_request_ending_transition(ending_type)

func _update_presentation() -> void:
	if Engine.is_editor_hint():
		return
	_update_character_visual_state()
	character_area.update_emotion_state(arousal_model.get_emotion_state())
	arousal_visualization.set_values(arousal_model.physical, arousal_model.emotional, arousal_model.peak)
	status_hud.update_values(arousal_model.physical, arousal_model.emotional, arousal_model.peak)
	status_hud.update_combo(combo)
	if debug_overlay != null:
		debug_overlay.sync_live_readout(get_debug_state())

func _update_layout_debug_regions() -> void:
	var debug_visible := show_layout_debug_bounds
	for region in layout_debug_regions:
		region.visible = debug_visible

func _request_ending_transition(ending_type: String) -> void:
	if ending_requested.get_connections().size() > 0:
		ending_requested.emit(ending_type)
		return
	call_deferred("_show_standalone_ending", ending_type)

func _show_standalone_ending(ending_type: String) -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent == null:
		return
	var ending_screen := ENDING_SCENE.instantiate()
	ending_screen.set_result(ending_type)
	ending_screen.restart_pressed.connect(_restart_standalone_run)
	ending_screen.back_to_title_pressed.connect(_return_to_title_standalone)
	var sibling_index := get_index()
	parent.add_child(ending_screen)
	parent.move_child(ending_screen, sibling_index)
	queue_free()

func _restart_standalone_run() -> void:
	var current_screen := get_tree().current_scene
	if current_screen != null and current_screen.scene_file_path == GAME_SCENE.resource_path:
		get_tree().reload_current_scene()
		return
	get_tree().change_scene_to_packed(GAME_SCENE)

func _return_to_title_standalone() -> void:
	get_tree().change_scene_to_packed(TITLE_SCENE)

func _stop_runtime_timers() -> void:
	feedback_timer.stop()
	prompt_spawn_timer.stop()
	active_prompt_timer.stop()
	choice_timeout_timer.stop()
	if overlay_animator != null:
		overlay_animator.stop()

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
		dialogue_panel.hide_prompt()
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
	prompt_expiration_times.clear()
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
	var progress_by_prompt_id: Dictionary = {}
	var now := _get_now_seconds()
	for prompt_id_variant in prompt_expiration_times.keys():
		var prompt_id := int(prompt_id_variant)
		var remaining_time := float(prompt_expiration_times[prompt_id]) - now
		progress_by_prompt_id[prompt_id] = clampf(remaining_time / Config.DIRECTION_PROMPT_TIME_LIMIT, 0.0, 1.0)
	character_area.set_prompt_time_progresses(progress_by_prompt_id)

func _update_choice_timer_visual() -> void:
	if waiting_for_choice and not choice_timeout_timer.is_stopped():
		var progress := choice_timeout_timer.time_left / Config.CHOICE_TIMEOUT_SECONDS
		dialogue_panel.set_choice_timeout_progress(progress)
		return
	dialogue_panel.set_choice_timeout_progress(0.0)

func _show_visible_prompt(prompt: Dictionary) -> void:
	var prompt_id := int(prompt.get("prompt_id", -1))
	prompt_expiration_times[prompt_id] = _get_now_seconds() + Config.DIRECTION_PROMPT_TIME_LIMIT
	character_area.show_direction_prompt(
		prompt_id,
		str(prompt.get("direction", "")),
		prompt.get("anchor_position", Vector2.ZERO)
	)
	print_debug("prompt spawn: %s" % sequence_controller.get_prompt_debug_state())

func _activate_current_prompt() -> void:
	var prompt := sequence_controller.get_current_prompt()
	if prompt.is_empty():
		active_prompt_timer.stop()
		return
	character_area.set_current_prompt(int(prompt.get("step_index", -1)))
	_update_prompt_timer_visual()

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
	dialogue_panel.append_history(dialogue_controller.get_timeout_reply(), "companion")
	_schedule_next_feedback_message()
	_update_presentation()

func _sync_prompt_anchor_layout() -> void:
	var region_rect := _get_prompt_region_rect_in_character_area()
	character_area.set_prompt_bounds(region_rect)
	sequence_controller.set_prompt_anchor_positions(_get_prompt_anchor_centers_in_character_area())

func _get_prompt_region_rect_in_character_area() -> Rect2:
	var global_rect := character_prompt_region.get_global_rect()
	var local_position: Vector2 = character_area.get_global_transform_with_canvas().affine_inverse() * global_rect.position
	return Rect2(local_position, global_rect.size)

func _get_prompt_anchor_centers_in_character_area() -> Array[Vector2]:
	var anchor_nodes: Array[Control] = []
	for child in character_prompt_region.get_children():
		if child is Control:
			anchor_nodes.append(child)
	anchor_nodes.sort_custom(func(a: Control, b: Control) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)

	var inverse: Transform2D = character_area.get_global_transform_with_canvas().affine_inverse()
	var centers: Array[Vector2] = []
	for anchor_node in anchor_nodes:
		centers.append(inverse * anchor_node.get_global_rect().get_center())
	return centers

func _check_prompt_timeouts() -> bool:
	if prompt_expiration_times.is_empty():
		return false
	var now := _get_now_seconds()
	var expired_prompt_id := -1
	for prompt_id_variant in prompt_expiration_times.keys():
		var prompt_id := int(prompt_id_variant)
		if now >= float(prompt_expiration_times[prompt_id]):
			expired_prompt_id = prompt_id
			break
	if expired_prompt_id < 0:
		return false
	print_debug("prompt timeout: id=%d state=%s" % [expired_prompt_id, sequence_controller.get_prompt_debug_state()])
	_handle_wrong_input()
	_update_presentation()
	return true

func _remove_prompt(prompt_id: int) -> void:
	prompt_expiration_times.erase(prompt_id)
	character_area.remove_direction_prompt(prompt_id)

func _get_now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
