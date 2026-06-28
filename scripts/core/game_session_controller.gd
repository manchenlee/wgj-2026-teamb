@tool
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const UiThemeScaler := preload("res://scripts/ui/ui_theme_scaler.gd")
const PhaseLibraryClass := preload("res://data/phases/phase_library.gd")
const ArousalModelClass := preload("res://scripts/gameplay/arousal_model.gd")
const DirectionSequenceControllerClass := preload("res://scripts/gameplay/direction_sequence_controller.gd")
const DialogueChoiceControllerClass := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const EndingEvaluatorClass := preload("res://scripts/gameplay/ending_evaluator.gd")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")
const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const TITLE_SCENE := preload("res://scenes/screens/TitleScreen.tscn")

signal ending_requested(ending_type: String)

@export var show_layout_debug_bounds: bool = false
@export var show_phase2_editor_reference: bool = true
@export var debug_start_phase_id: String = ""
@export var safe_word: String = Config.SAFE_WORD_DEFAULT

@onready var background_placeholder: TextureRect = $BackgroundAnchor/BackgroundPlaceholder
@onready var overlay_animator = $BackgroundAnchor/OverlayAnimator
@onready var breathing_controller = $BackgroundAnchor/BreathingController
@onready var phase_2_background_layer: TextureRect = $BackgroundAnchor/Phase2BackgroundLayer
@onready var phase_2_flush_layer: TextureRect = $BackgroundAnchor/Phase2FlushLayer
@onready var phase_2_face_layer: TextureRect = $BackgroundAnchor/Phase2FaceLayer
@onready var phase_2_gameover_overlay: TextureRect = $BackgroundAnchor/Phase2GameoverOverlay
@onready var main_character_area: Control = $MainCharacterArea
@onready var character_area = $MainCharacterArea/CharacterArea
@onready var character_prompt_region: Control = $MainCharacterArea/CharacterPromptRegion
@onready var arousal_visualization = $MainCharacterArea/CentralArousalVisualization
@onready var dialogue_panel = $ConversationViewport
@onready var status_hud = $BottomHUD
@onready var phase_debug_label: Label = $PhaseDebugLabel
@onready var phase_skip_button: Button = $Phase2SkipButton
@onready var layout_debug_regions := [
	$MainCharacterArea/DebugRegionTint,
	$ConversationViewport/DebugRegionTint,
	$BottomHUD/DebugRegionTint,
	$BottomHUD/ChoiceArea/DebugRegionTint
]
@onready var feedback_timer: Timer = $FeedbackTimer
@onready var prompt_spawn_timer: Timer = $PromptSpawnTimer
@onready var active_prompt_timer: Timer = $ActivePromptTimer
@onready var choice_timeout_timer: Timer = $ChoiceTimeoutTimer
@onready var phase_transition_overlay: ColorRect = $PhaseTransitionOverlay

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
var character_layer_textures: Dictionary = {}
var character_visual_warnings_printed: Dictionary = {}
var overlay_motion_set: Dictionary = {}
var ending_transition_started: bool = false
var has_left_overall_init_visual: bool = false
var phase_transition_in_progress: bool = false
var phase_sequence: Array = []
var active_phase_index: int = 0
var active_phase_config: PhaseConfig = null
var active_character_profile = null

func _ready() -> void:
	if not Engine.is_editor_hint():
		UiThemeScaler.apply_to_tree(self)

	_build_phase_sequence()
	_apply_phase_by_index(_get_initial_phase_index(), false)
	_update_character_visual_state()
	_apply_overlay_motion_set()
	_bind_breathing_targets()
	_update_layout_debug_regions()

	if Engine.is_editor_hint():
		set_process(false)
		set_process_unhandled_input(false)
		return

	feedback_rng.randomize()
	set_process_unhandled_input(true)
	dialogue_panel.choice_selected.connect(_on_choice_selected)
	phase_skip_button.pressed.connect(_on_phase_2_skip_pressed)
	feedback_timer.timeout.connect(_on_feedback_timer_timeout)
	prompt_spawn_timer.timeout.connect(_on_prompt_spawn_timer_timeout)
	active_prompt_timer.timeout.connect(_on_active_prompt_timer_timeout)
	choice_timeout_timer.timeout.connect(_on_choice_timeout)
	reset_run()
	if breathing_controller != null and breathing_controller.has_method("is_debug_breathing_enabled") and breathing_controller.is_debug_breathing_enabled():
		_capture_debug_breathing_frames()

@export var character_background: Texture2D:
	set(value):
		character_background = value
		if is_inside_tree():
			_apply_character_background()
			_update_character_visual_state()

func _build_phase_sequence() -> void:
	phase_sequence = PhaseLibraryClass.build_default_sequence()
	if phase_sequence.is_empty():
		push_error("GameSessionController: phase sequence is empty.")

func _get_initial_phase_index() -> int:
	if debug_start_phase_id.is_empty():
		return 0
	for index in range(phase_sequence.size()):
		if String(phase_sequence[index].phase_id) == debug_start_phase_id:
			return index
	push_warning("Unknown debug_start_phase_id '%s'; falling back to Phase 1." % debug_start_phase_id)
	return 0

func _apply_character_background() -> void:
	if background_placeholder == null:
		return
	background_placeholder.texture = character_background

func _apply_phase_by_index(phase_index: int, announce_phase: bool) -> void:
	if phase_index < 0 or phase_index >= phase_sequence.size():
		push_error("GameSessionController: invalid phase index %d." % phase_index)
		return

	active_phase_index = phase_index
	active_phase_config = phase_sequence[phase_index]
	active_character_profile = active_phase_config.character_profile
	arousal_model.set_phase_config(active_phase_config)
	sequence_controller.set_phase_config(active_phase_config)
	dialogue_controller.set_phase_config(active_phase_config)
	dialogue_controller.set_safe_word(safe_word)
	_cache_character_visual_textures()
	overlay_motion_set = _build_overlay_motion_set()
	_apply_phase_visual_profile()
	_sync_prompt_anchor_layout()
	if announce_phase and not Engine.is_editor_hint():
		dialogue_panel.append_history(active_phase_config.transition_feedback_text, "system")
	_update_phase_debug_label()

func _apply_phase_visual_profile() -> void:
	if active_character_profile == null:
		return
	_apply_character_background()
	_update_prompt_anchor_layout_from_profile()
	_apply_breathing_profile()
	_update_character_visual_state()
	_apply_overlay_motion_set()
	_bind_breathing_targets()

func _apply_breathing_profile() -> void:
	if breathing_controller == null or active_character_profile == null:
		return
	breathing_controller.set("chest_region_rect", active_character_profile.breathing_region_rect)

func _cache_character_visual_textures() -> void:
	character_visual_textures.clear()
	character_layer_textures.clear()
	if active_character_profile == null:
		return
	var texture_paths: Dictionary = active_character_profile.get_all_texture_paths()
	_cache_texture_paths_into_cache(texture_paths, character_visual_textures, "Character visual")
	_cache_texture_paths_into_cache(active_character_profile.get_layer_texture_paths(), character_layer_textures, "Character layer")
	_cache_texture_paths_into_cache(active_character_profile.get_face_texture_paths(), character_layer_textures, "Character face")

	if not character_visual_textures.has("draft") and character_background != null:
		character_visual_textures["draft"] = character_background

func _cache_texture_paths_into_cache(texture_paths: Dictionary, cache: Dictionary, label: String) -> void:
	for state_name_variant in texture_paths.keys():
		var state_name := String(state_name_variant)
		var asset_path := String(texture_paths[state_name])
		var texture := _load_texture_from_asset_path(asset_path)
		if texture == null:
			_warn_character_visual_once(
				"load_failed:%s" % asset_path,
				"%s asset failed to load: %s" % [label, asset_path]
			)
			continue
		cache[state_name] = texture

func _load_texture_from_asset_path(asset_path: String) -> Texture2D:
	if ResourceLoader.exists(asset_path):
		var resource_texture := load(asset_path) as Texture2D
		if resource_texture != null:
			return resource_texture

	var absolute_asset_path := ProjectSettings.globalize_path(asset_path)
	if not FileAccess.file_exists(absolute_asset_path):
		return null

	var image := Image.load_from_file(absolute_asset_path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _build_overlay_motion_set() -> Dictionary:
	var motion_set: Dictionary = {}
	if active_phase_config == null:
		return motion_set
	for motion_id_variant in active_phase_config.overlay_animation_set.keys():
		var motion_id := String(motion_id_variant)
		var frame_paths_variant = active_phase_config.overlay_animation_set[motion_id]
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
			var frame_texture := _load_texture_from_asset_path(frame_path)
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
	if Engine.is_editor_hint():
		return
	if overlay_animator == null:
		return
	overlay_animator.apply_playback_profile(
		active_character_profile.get_overlay_idle_playback_config() if active_character_profile != null else {}
	)
	overlay_animator.set_motion_set(overlay_motion_set)
	_apply_phase2_extended_overlay_profile()
	_bind_breathing_targets()

func _apply_phase2_extended_overlay_profile() -> void:
	if overlay_animator == null or active_character_profile == null:
		return
	var raw_config: Dictionary = active_character_profile.get_phase2_overlay_profile_config()
	if raw_config.is_empty():
		# Phase 1 or any profile without a Phase 2 extended config — clear any leftover
		overlay_animator.apply_phase2_overlay_profile({})
		return

	# Resolve texture paths to Texture2D objects before passing to the animator.
	var resolved: Dictionary = {}

	# Static overlays
	var raw_statics = raw_config.get("static_overlays", [])
	var resolved_statics: Array = []
	for entry_variant in raw_statics:
		var entry: Dictionary = entry_variant
		var tex_path := String(entry.get("texture_path", ""))
		if tex_path.is_empty():
			continue
		var tex := _load_texture_from_asset_path(tex_path)
		if tex == null:
			_warn_character_visual_once(
				"static_overlay_load_failed:%s" % tex_path,
				"Phase2 static overlay failed to load: %s" % tex_path
			)
			continue
		resolved_statics.append({
			"texture": tex,
			"z_index": int(entry.get("z_index", 0))
		})
	if not resolved_statics.is_empty():
		resolved["static_overlays"] = resolved_statics

	# Companion overlay
	var raw_companion = raw_config.get("companion", {})
	if not raw_companion.is_empty():
		var resolved_companion: Dictionary = {}
		resolved_companion["linked_motion_id"] = String(raw_companion.get("linked_motion_id", ""))
		resolved_companion["z_index"] = int(raw_companion.get("z_index", 6))

		# frame_1_idle: null means transparent (no texture)
		var f1_idle_path = raw_companion.get("frame_1_idle_path", null)
		if f1_idle_path != null and not String(f1_idle_path).is_empty():
			resolved_companion["frame_1_idle"] = _load_texture_from_asset_path(String(f1_idle_path))
		else:
			resolved_companion["frame_1_idle"] = null

		# frame_2_idle
		var f2_idle_path := String(raw_companion.get("frame_2_idle_path", ""))
		if not f2_idle_path.is_empty():
			var tex := _load_texture_from_asset_path(f2_idle_path)
			if tex == null:
				_warn_character_visual_once(
					"companion_load_failed:%s" % f2_idle_path,
					"Phase2 companion frame_2_idle failed to load: %s" % f2_idle_path
				)
			resolved_companion["frame_2_idle"] = tex

		# frame_1_active: null means transparent
		var f1_active_path = raw_companion.get("frame_1_active_path", null)
		if f1_active_path != null and not String(f1_active_path).is_empty():
			var tex := _load_texture_from_asset_path(String(f1_active_path))
			if tex == null:
				_warn_character_visual_once(
					"companion_load_failed:%s" % String(f1_active_path),
					"Phase2 companion frame_1_active failed to load: %s" % String(f1_active_path)
				)
			resolved_companion["frame_1_active"] = tex
		else:
			resolved_companion["frame_1_active"] = null

		# frame_2_active
		var f2_active_path := String(raw_companion.get("frame_2_active_path", ""))
		if not f2_active_path.is_empty():
			var tex := _load_texture_from_asset_path(f2_active_path)
			if tex == null:
				_warn_character_visual_once(
					"companion_load_failed:%s" % f2_active_path,
					"Phase2 companion frame_2_active failed to load: %s" % f2_active_path
				)
			resolved_companion["frame_2_active"] = tex

		resolved["companion"] = resolved_companion

	overlay_animator.apply_phase2_overlay_profile(resolved)

func _warn_character_visual_once(warning_key: String, message: String) -> void:
	if character_visual_warnings_printed.has(warning_key):
		return
	character_visual_warnings_printed[warning_key] = true
	push_warning(message)

func _update_character_visual_state(forced_ending_type: String = "") -> void:
	if background_placeholder == null:
		return

	var visual_state := _get_character_visual_state_key(forced_ending_type)
	_update_phase_specific_visual_layers(forced_ending_type)
	var next_texture := _get_character_visual_texture(visual_state)
	if next_texture == null:
		return
	if visual_state != "overall_init":
		has_left_overall_init_visual = true
	if background_placeholder.texture == next_texture:
		return
	background_placeholder.texture = next_texture

func _bind_breathing_targets() -> void:
	if Engine.is_editor_hint():
		return
	if breathing_controller == null or background_placeholder == null:
		return
	if breathing_controller.has_method("bind_targets"):
		var base_target := background_placeholder
		var overlay_targets: Array = overlay_animator.get_overlay_layers()
		if active_character_profile != null and active_character_profile.get_breathing_target_layer_id() == "phase_2_background":
			base_target = phase_2_background_layer
			overlay_targets = []
		breathing_controller.bind_targets(base_target, overlay_targets)

func _update_phase_specific_visual_layers(forced_ending_type: String = "") -> void:
	if not _is_phase_2_visual_profile_active():
		_apply_phase_layer_texture(phase_2_background_layer, null)
		_apply_phase_layer_texture(phase_2_flush_layer, null)
		_apply_phase_layer_texture(phase_2_face_layer, null)
		_apply_phase_layer_texture(phase_2_gameover_overlay, null)
		return

	_apply_phase_layer_texture(phase_2_background_layer, _get_phase_layer_texture("phase_2_background"))
	_apply_phase_layer_texture(phase_2_flush_layer, _get_phase_layer_texture("phase_2_flush"))
	_apply_phase_layer_texture(phase_2_face_layer, _get_phase_2_face_texture())

	var show_gameover_overlay := not forced_ending_type.is_empty() and forced_ending_type != Config.SUCCESS_ENDING
	var gameover_texture := _get_phase_2_gameover_texture() if show_gameover_overlay else null
	_apply_phase_layer_texture(phase_2_gameover_overlay, gameover_texture)

func _apply_phase_layer_texture(layer: TextureRect, next_texture: Texture2D) -> void:
	if layer == null:
		return
	layer.texture = next_texture
	layer.visible = next_texture != null

func _is_phase_2_visual_profile_active() -> bool:
	if active_character_profile == null:
		return false
	return not active_character_profile.get_face_texture_paths().is_empty()

func _get_phase_layer_texture(layer_key: String) -> Texture2D:
	if character_layer_textures.has(layer_key):
		return character_layer_textures[layer_key] as Texture2D
	return null

func _get_phase_2_face_texture() -> Texture2D:
	if active_character_profile == null:
		return null
	var face_state: String = active_character_profile.get_face_state_key(
		arousal_model.peak,
		float(_get_phase_value("overall_medium_threshold", 20.0)),
		float(_get_phase_value("overall_high_threshold", 60.0))
	)
	if face_state.is_empty():
		return null
	return _get_phase_layer_texture(face_state)

func _get_phase_2_gameover_texture() -> Texture2D:
	return _get_phase_layer_texture("phase_2_gameover_overlay")

func _get_character_visual_state_key(forced_ending_type: String = "") -> String:
	if forced_ending_type == Config.PHYSICAL_IMBALANCE_FAILURE_ENDING:
		return "physic_high_mental_low_gameover"
	if forced_ending_type == Config.EMOTIONAL_IMBALANCE_FAILURE_ENDING:
		return "physic_low_mental_high_gameover"

	var mismatch_low_threshold: float = float(_get_phase_value("minimum_active_threshold", 20.0))
	var mismatch_high_threshold: float = float(_get_phase_value("feedback_emotional_high_threshold", 60.0))
	if arousal_model.physical >= mismatch_high_threshold and arousal_model.emotional < mismatch_low_threshold:
		return "physic_high_mental_low"
	if arousal_model.emotional >= mismatch_high_threshold and arousal_model.physical < mismatch_low_threshold:
		return "physic_low_mental_high"
	if arousal_model.peak >= _get_phase_value("overall_high_threshold", 60.0):
		return "overall_high"
	if arousal_model.peak >= _get_phase_value("overall_medium_threshold", 20.0):
		return "overall_medium"
	if has_left_overall_init_visual:
		return "overall_low"
	return "overall_init"

func _get_character_visual_texture(visual_state: String) -> Texture2D:
	if character_visual_textures.has(visual_state):
		return character_visual_textures[visual_state] as Texture2D

	var missing_path := ""
	if active_character_profile != null:
		missing_path = active_character_profile.get_texture_path(visual_state)
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
	elif what == NOTIFICATION_PREDELETE:
		if not Engine.is_editor_hint() and overlay_animator != null:
			overlay_animator.stop()
		if not Engine.is_editor_hint() and breathing_controller != null and breathing_controller.has_method("stop_breathing"):
			breathing_controller.stop_breathing()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not run_active:
		_update_phase_debug_label()
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
	_reset_run_for_phase_index(_get_initial_phase_index())

func start_direct_in_phase_2() -> void:
	_reset_run_for_phase_id("phase_2")

func start_in_phase_for_debug(phase_id: String) -> void:
	_reset_run_for_phase_id(phase_id)

func _reset_run_for_phase_id(phase_id: String) -> void:
	for index in range(phase_sequence.size()):
		if String(phase_sequence[index].phase_id) == phase_id:
			_reset_run_for_phase_index(index)
			return
	push_warning("Unknown phase id '%s' for debug start." % phase_id)
	_reset_run_for_phase_index(0)

func _reset_run_for_phase_index(phase_index: int) -> void:
	phase_transition_in_progress = false
	run_active = true
	ending_transition_started = false
	has_left_overall_init_visual = false
	combo = 0
	current_prompt = {}
	pending_prompt_action = ""
	waiting_for_choice = false
	prompt_expiration_times.clear()
	_stop_runtime_timers()
	sequence_controller.clear_sequence()
	character_area.clear_direction_prompts()
	dialogue_panel.clear_history()
	_apply_phase_by_index(phase_index, false)
	arousal_model.reset()
	dialogue_controller.reset()
	if overlay_animator != null:
		overlay_animator.play_idle()
	if breathing_controller != null and breathing_controller.has_method("start_breathing"):
		breathing_controller.start_breathing()
	_push_next_dialogue_event()
	_start_new_sequence()
	_update_presentation()

func apply_debug_values(value: float) -> void:
	arousal_model.physical = value
	arousal_model.emotional = value
	arousal_model.peak = value
	_update_presentation()

func force_ending(ending_type: String) -> void:
	if ending_type == Config.SUCCESS_ENDING and _has_next_phase():
		_begin_phase_transition()
		return
	_begin_ending_transition(ending_type)

func get_debug_state() -> Dictionary:
	return {
		"screen": Config.SCREEN_GAME,
		"phase": _get_active_phase_id(),
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

func _on_direction_pressed(direction: String) -> void:
	if not run_active:
		return
	var result: Dictionary = sequence_controller.submit_input(direction)
	match str(result.get("result", "")):
		"correct":
			combo += 1
			arousal_model.apply_physical(float(active_phase_config.direction_reward_values.get("correct_input", 1.0)))
			arousal_model.refresh_physical_activity()
			character_area.show_success_note_burst(int(result.get("consumed_prompt_id", -1)))
			_remove_prompt(int(result.get("consumed_prompt_id", -1)))
			var auto_revealed_prompt: Dictionary = result.get("auto_revealed_prompt", {})
			if not auto_revealed_prompt.is_empty():
				_show_visible_prompt(auto_revealed_prompt)
			character_area.show_prompt_feedback(
				"Correct +%d" % int(round(float(active_phase_config.direction_reward_values.get("correct_input", 1.0)))),
				Color(0.45, 0.87, 0.56, 1.0),
				Config.CORRECT_FEEDBACK_DISPLAY_DURATION
			)
			character_area.show_correct_reaction()
			_activate_current_prompt()
			_schedule_extra_prompt_reveal()
		"sequence_complete":
			combo += 1
			arousal_model.apply_physical(float(active_phase_config.direction_reward_values.get("correct_input", 1.0)))
			arousal_model.apply_physical(float(active_phase_config.direction_reward_values.get("sequence_complete_bonus", 5.0)))
			arousal_model.refresh_physical_activity()
			character_area.show_success_note_burst(int(result.get("consumed_prompt_id", -1)))
			_remove_prompt(int(result.get("consumed_prompt_id", -1)))
			character_area.show_prompt_feedback(
				"Sequence Complete +%d" % int(round(float(active_phase_config.direction_reward_values.get("sequence_complete_bonus", 5.0)))),
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
	var ending_type := str(outcome.get("ending_type", ""))
	arousal_model.refresh_emotional_activity()
	var reply_text := str(outcome.get("reply", ""))
	if not reply_text.is_empty():
		dialogue_panel.append_history(reply_text, "companion")
	character_area.show_choice_reaction(choice_quality)
	if not ending_type.is_empty():
		_begin_ending_transition(ending_type)
		return
	_schedule_next_feedback_message()
	_update_presentation()

func _handle_wrong_input() -> void:
	combo = 0
	active_prompt_timer.stop()
	arousal_model.apply_physical(-float(active_phase_config.direction_penalty_values.get("wrong_input", 2.0)))
	arousal_model.refresh_physical_activity()
	sequence_controller.clear_sequence()
	prompt_expiration_times.clear()
	character_area.clear_direction_prompts()
	character_area.show_prompt_feedback(
		"Wrong -%d" % int(round(float(active_phase_config.direction_penalty_values.get("wrong_input", 2.0)))),
		Color(0.95, 0.35, 0.35, 1.0),
		Config.WRONG_FEEDBACK_DISPLAY_DURATION
	)
	character_area.show_mistake_reaction()
	_schedule_new_sequence()

func _check_ending() -> void:
	if ending_transition_started or phase_transition_in_progress:
		return
	var ending_type := EndingEvaluatorClass.evaluate(arousal_model, active_phase_config)
	if ending_type.is_empty():
		return
	if ending_type == Config.SUCCESS_ENDING and _has_next_phase():
		_begin_phase_transition()
		return
	_begin_ending_transition(ending_type)

func _begin_phase_transition() -> void:
	if phase_transition_in_progress:
		return
	phase_transition_in_progress = true
	run_active = false
	_stop_runtime_timers()
	waiting_for_choice = false
	current_prompt = {}
	prompt_expiration_times.clear()
	sequence_controller.clear_sequence()
	character_area.clear_direction_prompts()
	dialogue_panel.hide_prompt()
	dialogue_panel.hide_choices()
	var transition_text := active_phase_config.transition_feedback_text
	if not transition_text.is_empty():
		dialogue_panel.append_history(transition_text, "system")
	_play_phase_transition_fade(Color(1, 1, 1, 0), true)

func _complete_phase_transition() -> void:
	if not is_inside_tree():
		return
	_reset_run_for_phase_index(active_phase_index + 1)

func _begin_ending_transition(ending_type: String) -> void:
	if ending_transition_started:
		return
	ending_transition_started = true
	_stop_runtime_timers()
	run_active = false
	_update_character_visual_state(ending_type)
	_play_phase_transition_fade(Color(0, 0, 0, 0), false, ending_type)

func _complete_ending_transition_after_frame(ending_type: String) -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_request_ending_transition(ending_type)

## Plays a full-screen colour fade: 2s fade out → 1s hold → 1s fade in.
## overlay_start_color — the starting (transparent) colour of the overlay (black or white, alpha 0).
## is_phase_transition — if true, calls _complete_phase_transition() after the hold;
##                       if false, triggers the ending request (passes ending_type).
func _play_phase_transition_fade(overlay_start_color: Color, is_phase_transition: bool, ending_type: String = "") -> void:
	if phase_transition_overlay == null:
		# Fallback: no overlay node, just proceed immediately.
		if is_phase_transition:
			_complete_phase_transition()
		else:
			_request_ending_transition(ending_type)
		return

	var opaque_color := Color(overlay_start_color.r, overlay_start_color.g, overlay_start_color.b, 1.0)
	phase_transition_overlay.color = overlay_start_color
	phase_transition_overlay.visible = true

	var tween := create_tween()
	# 1 s fade to opaque
	tween.tween_property(phase_transition_overlay, "color", opaque_color, 1.0)
	# 1 s hold (fully opaque)
	tween.tween_interval(1.0)

	if is_phase_transition:
		# Kick off next phase reset while still opaque, then fade back in
		tween.tween_callback(_complete_phase_transition)
		# 1 s fade back to transparent
		tween.tween_property(phase_transition_overlay, "color", overlay_start_color, 1.0)
		tween.tween_callback(func() -> void: phase_transition_overlay.visible = false)
	else:
		# For ending: request transition while screen is black, then let the new screen handle its own reveal.
		tween.tween_callback(func() -> void: _request_ending_transition(ending_type))

func _update_presentation() -> void:
	if Engine.is_editor_hint():
		return
	_update_character_visual_state()
	character_area.update_emotion_state(arousal_model.get_emotion_state())
	arousal_visualization.set_values(arousal_model.physical, arousal_model.emotional, arousal_model.peak)
	status_hud.update_values(arousal_model.physical, arousal_model.emotional, arousal_model.peak)
	status_hud.update_combo(combo)
	_update_phase_debug_label()
	if debug_overlay != null:
		debug_overlay.sync_live_readout(get_debug_state())

func _update_phase_debug_label() -> void:
	if phase_debug_label == null:
		return
	phase_debug_label.text = "Phase: %s" % _get_active_phase_id()
	phase_debug_label.visible = debug_overlay != null and debug_overlay.visible
	if phase_skip_button != null:
		var can_skip_to_phase_2 := _get_active_phase_id() != "phase_2" and not phase_transition_in_progress
		phase_skip_button.visible = debug_overlay != null and debug_overlay.visible and can_skip_to_phase_2
		phase_skip_button.disabled = not can_skip_to_phase_2

func _update_layout_debug_regions() -> void:
	var debug_visible := show_layout_debug_bounds
	for region in layout_debug_regions:
		region.visible = debug_visible
	for child in character_prompt_region.get_children():
		if child is Control:
			child.visible = debug_visible

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
	if breathing_controller != null and breathing_controller.has_method("stop_breathing"):
		breathing_controller.stop_breathing()

func _schedule_next_feedback_message() -> void:
	var wait_time := feedback_rng.randf_range(
		float(active_phase_config.feedback_message_interval_min),
		float(active_phase_config.feedback_message_interval_max)
	)
	feedback_timer.start(wait_time)

func _push_next_dialogue_event() -> void:
	var should_force_safe_word := dialogue_controller.has_safe_word_event() and feedback_rng.randf() < Config.SAFE_WORD_EVENT_CHANCE
	current_prompt = dialogue_controller.next_event(arousal_model.physical, arousal_model.emotional, should_force_safe_word)
	if current_prompt.is_empty():
		return
	if current_prompt.has("choices"):
		waiting_for_choice = true
		dialogue_panel.hide_prompt()
		dialogue_panel.append_history(str(current_prompt.get("text", Config.FEEDBACK_MESSAGE_TEXT)), "companion")
		dialogue_panel.show_choices(current_prompt.get("choices", {}))
		feedback_timer.stop()
		choice_timeout_timer.start(float(active_phase_config.choice_timeout_seconds))
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
		float(active_phase_config.prompt_spawn_delay_min),
		float(active_phase_config.prompt_spawn_delay_max)
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
	var prompt_time_limit := float(active_phase_config.direction_prompt_time_limit)
	for prompt_id_variant in prompt_expiration_times.keys():
		var prompt_id := int(prompt_id_variant)
		var remaining_time := float(prompt_expiration_times[prompt_id]) - now
		progress_by_prompt_id[prompt_id] = clampf(remaining_time / prompt_time_limit, 0.0, 1.0)
	character_area.set_prompt_time_progresses(progress_by_prompt_id)

func _update_choice_timer_visual() -> void:
	if waiting_for_choice and not choice_timeout_timer.is_stopped():
		var progress := choice_timeout_timer.time_left / float(active_phase_config.choice_timeout_seconds)
		dialogue_panel.set_choice_timeout_progress(progress)
		return
	dialogue_panel.set_choice_timeout_progress(0.0)

func _show_visible_prompt(prompt: Dictionary) -> void:
	var prompt_id := int(prompt.get("prompt_id", -1))
	var anchor_id := str(prompt.get("anchor_id", "Chest"))
	prompt_expiration_times[prompt_id] = _get_now_seconds() + float(active_phase_config.direction_prompt_time_limit)
	character_area.show_direction_prompt(
		prompt_id,
		str(prompt.get("direction", "")),
		_get_prompt_anchor_center_in_character_area(anchor_id)
	)

func _activate_current_prompt() -> void:
	var prompt := sequence_controller.get_current_prompt()
	if prompt.is_empty():
		active_prompt_timer.stop()
		return
	character_area.set_current_prompt(int(prompt.get("step_index", -1)))
	active_prompt_timer.start(float(active_phase_config.direction_prompt_time_limit))
	_update_prompt_timer_visual()

func _schedule_extra_prompt_reveal() -> void:
	if not sequence_controller.has_more_hidden_prompts():
		return
	if pending_prompt_action == "new_sequence":
		return
	pending_prompt_action = "reveal_extra"
	var wait_time := feedback_rng.randf_range(
		float(active_phase_config.next_prompt_reveal_delay),
		float(active_phase_config.prompt_spawn_delay_max)
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
	if Engine.is_editor_hint():
		return
	var region_rect := _get_prompt_region_rect_in_character_area()
	character_area.set_prompt_bounds(region_rect)
	sequence_controller.set_prompt_anchor_ids(_get_prompt_anchor_ids())

func _get_prompt_region_rect_in_character_area() -> Rect2:
	var global_rect := character_prompt_region.get_global_rect()
	var local_position: Vector2 = character_area.get_global_transform_with_canvas().affine_inverse() * global_rect.position
	return Rect2(local_position, global_rect.size)

func _get_prompt_anchor_ids() -> Array[String]:
	var anchor_ids: Array[String] = []
	for child in character_prompt_region.get_children():
		if child is Control and child.name != "Phase2AnchorPreviewLayer":
			anchor_ids.append(String(child.name))
	anchor_ids.sort()
	return anchor_ids

func _get_prompt_anchor_center_in_character_area(anchor_id: String) -> Vector2:
	var anchor_node := character_prompt_region.get_node_or_null(anchor_id) as Control
	if anchor_node == null:
		push_warning("Missing prompt anchor '%s' in active phase profile." % anchor_id)
		return character_area.size * 0.5
	var inverse: Transform2D = character_area.get_global_transform_with_canvas().affine_inverse()
	return inverse * anchor_node.get_global_rect().get_center()

func _update_prompt_anchor_layout_from_profile() -> void:
	if active_character_profile == null:
		return
	for child in character_prompt_region.get_children():
		if child is Control:
			child.visible = false

	for anchor_id_variant in active_character_profile.prompt_anchor_layout.keys():
		var anchor_id := String(anchor_id_variant)
		var anchor_rect := active_character_profile.prompt_anchor_layout[anchor_id] as Rect2
		var anchor_node := character_prompt_region.get_node_or_null(anchor_id) as Control
		if anchor_node == null:
			push_warning("Prompt anchor node '%s' is missing from GameScreen." % anchor_id)
			continue
		anchor_node.position = anchor_rect.position
		anchor_node.size = anchor_rect.size
		anchor_node.visible = show_layout_debug_bounds

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
	_handle_wrong_input()
	_update_presentation()
	return true

func _remove_prompt(prompt_id: int) -> void:
	prompt_expiration_times.erase(prompt_id)
	character_area.remove_direction_prompt(prompt_id)

func _get_now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _capture_debug_breathing_frames() -> void:
	call_deferred("_capture_debug_breathing_frames_async")

func _capture_debug_breathing_frames_async() -> void:
	await get_tree().process_frame
	var capture_delays := [0.15, 0.55, 0.95]
	for index in range(capture_delays.size()):
		await get_tree().create_timer(capture_delays[index]).timeout
		var image := get_viewport().get_texture().get_image()
		if image == null:
			continue
		var save_path := "C:/tmp/godot_breathing_debug_%d.png" % [index + 1]
		var save_result := image.save_png(save_path)
		if save_result != OK:
			push_warning("Failed to save breathing debug capture: %s (%s)" % [save_path, error_string(save_result)])

func _get_phase_value(property_name: String, fallback: Variant) -> Variant:
	if active_phase_config != null:
		return active_phase_config.get(property_name)
	return fallback

func _get_active_phase_id() -> String:
	if active_phase_config == null:
		return "phase_unknown"
	return String(active_phase_config.phase_id)

func _has_next_phase() -> bool:
	return active_phase_index + 1 < phase_sequence.size()

func _on_phase_2_skip_pressed() -> void:
	if _get_active_phase_id() == "phase_2" or phase_transition_in_progress:
		return
	_reset_run_for_phase_id("phase_2")
