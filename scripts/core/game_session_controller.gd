@tool
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const PhaseLibraryClass := preload("res://data/phases/phase_library.gd")
const ArousalModelClass := preload("res://scripts/gameplay/arousal_model.gd")
# LEGACY: DirectionSequenceControllerClass kept for rollback reference — NOT instantiated.
const DirectionSequenceControllerClass := preload("res://scripts/gameplay/direction_sequence_controller.gd")
const DialogueChoiceControllerClass := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const EndingEvaluatorClass := preload("res://scripts/gameplay/ending_evaluator.gd")
const InteractionSpotManagerClass := preload("res://scripts/gameplay/interaction_spot_manager.gd")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")
const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const TITLE_SCENE := preload("res://scenes/screens/TitleScreen.tscn")

signal ending_requested(ending_type: String)
signal bgm_requested(track_key: String, use_fade: bool)

@export var show_layout_debug_bounds: bool = false
@export var show_phase2_editor_reference: bool = true
@export var debug_start_phase_id: String = ""
@export var safe_word: String = Config.SAFE_WORD_DEFAULT
@export var shared_character_alignment_offset: Vector2 = Vector2.ZERO

@onready var character_alignment_root: Control = $CharacterAlignmentRoot
@onready var background_placeholder: TextureRect = $CharacterAlignmentRoot/BackgroundAnchor/BackgroundPlaceholder
@onready var overlay_animator = $CharacterAlignmentRoot/BackgroundAnchor/OverlayAnimator
@onready var breathing_controller = $CharacterAlignmentRoot/BackgroundAnchor/BreathingController
@onready var phase_2_background_layer: TextureRect = $CharacterAlignmentRoot/BackgroundAnchor/Phase2BackgroundLayer
@onready var phase_2_flush_layer: TextureRect = $CharacterAlignmentRoot/BackgroundAnchor/Phase2FlushLayer
@onready var phase_2_face_layer: TextureRect = $CharacterAlignmentRoot/BackgroundAnchor/Phase2FaceLayer
@onready var phase_2_gameover_overlay: TextureRect = $CharacterAlignmentRoot/BackgroundAnchor/Phase2GameoverOverlay
@onready var main_character_area: Control = $CharacterAlignmentRoot/MainCharacterArea
@onready var character_area = $CharacterAlignmentRoot/MainCharacterArea/CharacterArea
@onready var character_prompt_region = %CharacterPromptRegion
@onready var speech_bubble_anchor: Control = $CharacterAlignmentRoot/MainCharacterArea/SpeechBubbleAnchor
@onready var left_choice_anchor_root: Control = $CharacterAlignmentRoot/MainCharacterArea/ChoiceAnchorRegion/LeftChoiceAnchors
@onready var right_choice_anchor_root: Control = $CharacterAlignmentRoot/MainCharacterArea/ChoiceAnchorRegion/RightChoiceAnchors
@onready var arousal_visualization = $CharacterAlignmentRoot/MainCharacterArea/CentralArousalVisualization
@onready var dialogue_panel = $ConversationViewport
@onready var choice_panel: ChoicePanel = %ChoicePanel
@onready var status_hud: StatusHUD = %StatusHUD
@onready var phase_debug_label: Label = $PhaseDebugLabel
@onready var phase_skip_button: Button = $Phase2SkipButton
@onready var layout_debug_regions := [
	$CharacterAlignmentRoot/MainCharacterArea/DebugRegionTint,
	$ConversationViewport/DebugRegionTint,
	$HudLayer/TopHudCenter/StatusHUD/DebugRegionTint,
	$ChoiceLayer/ChoicePanel/DebugRegionTint
]
@onready var feedback_timer: Timer = $FeedbackTimer
@onready var spot_spawn_timer: Timer = $SpotSpawnTimer
@onready var choice_timeout_timer: Timer = $ChoiceTimeoutTimer
@onready var phase_transition_overlay: ColorRect = $PhaseTransitionOverlay

var arousal_model = ArousalModelClass.new()
var dialogue_controller = DialogueChoiceControllerClass.new()
var spot_manager: InteractionSpotManager = null
var feedback_rng := RandomNumberGenerator.new()
var current_prompt: Dictionary = {}
var debug_overlay = null
var run_active: bool = true
var waiting_for_choice: bool = false
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
var has_switched_to_game_bgm: bool = false
var last_requested_bgm_key: String = ""
var _resolved_character_alignment_offset: Vector2 = Vector2.ZERO

# Telemetry from spot manager for debug readout
var _last_spot_telemetry: Dictionary = {}

func _ready() -> void:
	_build_phase_sequence()
	_apply_phase_by_index(_get_initial_phase_index(), false)
	_update_character_visual_state()
	_apply_overlay_motion_set()
	_bind_breathing_targets()
	dialogue_panel.set_speech_bubble_anchor(speech_bubble_anchor)
	choice_panel.set_choice_anchor_groups(
		_get_choice_anchor_children(left_choice_anchor_root),
		_get_choice_anchor_children(right_choice_anchor_root)
	)
	_update_layout_debug_regions()

	if Engine.is_editor_hint():
		set_process(false)
		set_process_unhandled_input(false)
		return

	feedback_rng.randomize()
	set_process_unhandled_input(true)
	choice_panel.choice_selected.connect(_on_choice_selected)
	phase_skip_button.pressed.connect(_on_phase_2_skip_pressed)
	feedback_timer.timeout.connect(_on_feedback_timer_timeout)
	choice_timeout_timer.timeout.connect(_on_choice_timeout)
	_setup_spot_manager()
	reset_run()
	if breathing_controller != null and breathing_controller.has_method("is_debug_breathing_enabled") \
			and breathing_controller.is_debug_breathing_enabled():
		_capture_debug_breathing_frames()

@export var character_background: Texture2D:
	set(value):
		character_background = value
		if is_inside_tree():
			_apply_character_background()
			_update_character_visual_state()

# ---------------------------------------------------------------------------
# Spot manager setup
# ---------------------------------------------------------------------------

func _setup_spot_manager() -> void:
	spot_manager = InteractionSpotManagerClass.new()
	var prompt_layer := character_area.get_node_or_null("PromptLayer") as Control
	if prompt_layer == null:
		push_error("GameSessionController: PromptLayer not found in CharacterArea.")
		return
	if character_prompt_region == null:
		push_error("GameSessionController: CharacterPromptRegion not found.")
		return
	spot_manager.setup(arousal_model, character_area, prompt_layer, character_prompt_region, spot_spawn_timer)
	spot_manager.spot_scrub_started.connect(_on_spot_scrub_started)
	spot_manager.spot_scrub_ended.connect(_on_spot_scrub_ended)
	spot_manager.spot_telemetry_updated.connect(_on_spot_telemetry_updated)

# ---------------------------------------------------------------------------
# Phase management
# ---------------------------------------------------------------------------

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
	dialogue_controller.set_phase_config(active_phase_config)
	dialogue_controller.set_safe_word(safe_word)
	_cache_character_visual_textures()
	overlay_motion_set = _build_overlay_motion_set()
	_apply_phase_visual_profile()
	_apply_character_alignment()
	if dialogue_panel != null:
		dialogue_panel.refresh_active_dialogue_position()
	if choice_panel != null:
		choice_panel.refresh_choice_anchor_positions()
	if spot_manager != null:
		spot_manager.set_phase_config(active_phase_config)
		_sync_spot_anchor_layout()
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
		overlay_animator.apply_phase2_overlay_profile({})
		return
	var resolved: Dictionary = {}
	var raw_statics = raw_config.get("static_overlays", [])
	var resolved_statics: Array = []
	for entry_variant in raw_statics:
		var entry: Dictionary = entry_variant
		var tex_path := String(entry.get("texture_path", ""))
		if tex_path.is_empty():
			continue
		var tex := _load_texture_from_asset_path(tex_path)
		if tex == null:
			_warn_character_visual_once("static_overlay_load_failed:%s" % tex_path, "Phase2 static overlay failed to load: %s" % tex_path)
			continue
		resolved_statics.append({"texture": tex, "z_index": int(entry.get("z_index", 0))})
	if not resolved_statics.is_empty():
		resolved["static_overlays"] = resolved_statics
	var raw_companion = raw_config.get("companion", {})
	if not raw_companion.is_empty():
		var rc: Dictionary = {}
		rc["linked_motion_id"] = String(raw_companion.get("linked_motion_id", ""))
		rc["z_index"] = int(raw_companion.get("z_index", 6))
		var f1i = raw_companion.get("frame_1_idle_path", null)
		rc["frame_1_idle"] = _load_texture_from_asset_path(String(f1i)) if f1i != null and not String(f1i).is_empty() else null
		var f2i := String(raw_companion.get("frame_2_idle_path", ""))
		if not f2i.is_empty():
			rc["frame_2_idle"] = _load_texture_from_asset_path(f2i)
		var f1a = raw_companion.get("frame_1_active_path", null)
		rc["frame_1_active"] = _load_texture_from_asset_path(String(f1a)) if f1a != null and not String(f1a).is_empty() else null
		var f2a := String(raw_companion.get("frame_2_active_path", ""))
		if not f2a.is_empty():
			rc["frame_2_active"] = _load_texture_from_asset_path(f2a)
		resolved["companion"] = rc
	overlay_animator.apply_phase2_overlay_profile(resolved)

func _warn_character_visual_once(warning_key: String, message: String) -> void:
	if character_visual_warnings_printed.has(warning_key):
		return
	character_visual_warnings_printed[warning_key] = true
	push_warning(message)

# ---------------------------------------------------------------------------
# Character visual state
# ---------------------------------------------------------------------------

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
	var physical_low_threshold: float = float(_get_phase_value("feedback_physical_low_threshold", Config.FEEDBACK_PHYSICAL_LOW_THRESHOLD))
	var physical_high_threshold: float = float(_get_phase_value("feedback_physical_high_threshold", Config.FEEDBACK_PHYSICAL_HIGH_THRESHOLD))
	var emotional_low_threshold: float = float(_get_phase_value("feedback_emotional_low_threshold", Config.FEEDBACK_EMOTIONAL_LOW_THRESHOLD))
	var emotional_high_threshold: float = float(_get_phase_value("feedback_emotional_high_threshold", Config.FEEDBACK_EMOTIONAL_HIGH_THRESHOLD))
	if arousal_model.physical >= physical_high_threshold and arousal_model.emotional <= emotional_low_threshold:
		return "physic_high_mental_low"
	if arousal_model.emotional >= emotional_high_threshold and arousal_model.physical <= physical_low_threshold:
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
	_warn_character_visual_once("fallback:%s" % visual_state,
		"Character visual state '%s' missing, falling back. Expected: %s" % [visual_state, missing_path])
	if visual_state != "overall_init" and character_visual_textures.has("overall_init"):
		return character_visual_textures["overall_init"] as Texture2D
	if character_visual_textures.has("draft"):
		return character_visual_textures["draft"] as Texture2D
	return character_background

# ---------------------------------------------------------------------------
# Notifications, process, input
# ---------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_character_alignment()
		if dialogue_panel != null:
			dialogue_panel.refresh_active_dialogue_position()
		if choice_panel != null:
			choice_panel.refresh_choice_anchor_positions()
		if not Engine.is_editor_hint():
			_sync_spot_anchor_layout()
	elif what == NOTIFICATION_PREDELETE:
		if not Engine.is_editor_hint() and overlay_animator != null:
			overlay_animator.stop()
		if not Engine.is_editor_hint() and breathing_controller != null \
				and breathing_controller.has_method("stop_breathing"):
			breathing_controller.stop_breathing()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not run_active:
		_update_phase_debug_label()
		return
	arousal_model.apply_decay(delta)
	arousal_model.update_peak(delta)
	_update_choice_timer_visual()
	_update_presentation()
	_check_ending()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not run_active:
		return
	if event.is_action_pressed("dialogue_left"):
		get_viewport().set_input_as_handled()
		_on_dialogue_choice_input(0)
	elif event.is_action_pressed("dialogue_right"):
		get_viewport().set_input_as_handled()
		_on_dialogue_choice_input(1)

func _on_dialogue_choice_input(index: int) -> void:
	if not waiting_for_choice:
		return
	choice_panel.emit_choice_by_index(index)

# ---------------------------------------------------------------------------
# Run lifecycle
# ---------------------------------------------------------------------------

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
	has_switched_to_game_bgm = false
	last_requested_bgm_key = ""
	current_prompt = {}
	waiting_for_choice = false
	_last_spot_telemetry = {}
	_stop_runtime_timers()
	dialogue_panel.clear_history()
	_apply_phase_by_index(phase_index, false)
	arousal_model.reset()
	dialogue_controller.reset()
	if overlay_animator != null:
		overlay_animator.play_idle()
	if breathing_controller != null and breathing_controller.has_method("start_breathing"):
		breathing_controller.start_breathing()
	_push_next_dialogue_event()
	if spot_manager != null:
		spot_manager.start()
	_update_presentation()

# ---------------------------------------------------------------------------
# Debug helpers
# ---------------------------------------------------------------------------

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

func force_spawn_spot() -> void:
	if spot_manager != null:
		spot_manager.force_spawn_spot()

func force_complete_spot() -> void:
	if spot_manager != null:
		spot_manager.force_complete_spot()

func force_expire_spot() -> void:
	if spot_manager != null:
		spot_manager.force_expire_spot()

func get_debug_state() -> Dictionary:
	var spot_state := spot_manager.get_debug_spot_state() if spot_manager != null else "no_manager"
	var telemetry := _last_spot_telemetry
	return {
		"screen": Config.SCREEN_GAME,
		"phase": _get_active_phase_id(),
		"physical": int(round(arousal_model.physical)),
		"emotional": int(round(arousal_model.emotional)),
		"peak": int(round(arousal_model.peak)),
		"spot": spot_state,
		"spot_incr": "%.1f" % float(telemetry.get("incremental_gain", 0.0)),
		"spot_bonus": "%.1f" % float(telemetry.get("completion_bonus", 0.0)),
		"spot_penalty": "%.1f" % float(telemetry.get("penalty", 0.0)),
		"spot_net": "%.1f" % float(telemetry.get("net_physical_change", 0.0)),
		"alignment_x": "%.1f" % _resolved_character_alignment_offset.x
	}

# ---------------------------------------------------------------------------
# Spot manager signal handlers
# ---------------------------------------------------------------------------

func _on_spot_scrub_started() -> void:
	# Pause dialogue choice timer while player is actively scrubbing a spot.
	if waiting_for_choice and not choice_timeout_timer.is_stopped():
		choice_timeout_timer.set_paused(true)

func _on_spot_scrub_ended() -> void:
	# Resume dialogue choice timer when scrub ends.
	if waiting_for_choice:
		choice_timeout_timer.set_paused(false)

func _on_spot_telemetry_updated(telemetry: Dictionary) -> void:
	_last_spot_telemetry = telemetry
	if debug_overlay != null:
		debug_overlay.sync_live_readout(get_debug_state())

# ---------------------------------------------------------------------------
# Dialogue
# ---------------------------------------------------------------------------

func _on_feedback_timer_timeout() -> void:
	if not run_active or waiting_for_choice:
		return
	_push_next_dialogue_event()

func _on_choice_selected(choice_quality: String, choice_text: String) -> void:
	choice_timeout_timer.stop()
	dialogue_panel.append_history(choice_text, "player")
	dialogue_panel.hide_prompt()
	choice_panel.clear_choices()
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

func _on_choice_timeout() -> void:
	if not run_active or not waiting_for_choice:
		return
	waiting_for_choice = false
	dialogue_panel.hide_prompt()
	choice_panel.clear_choices()
	character_area.show_ignored_reaction()
	dialogue_panel.append_history(dialogue_controller.get_timeout_reply(), "companion")
	_schedule_next_feedback_message()
	_update_presentation()

func _push_next_dialogue_event() -> void:
	var should_force_safe_word := dialogue_controller.has_safe_word_event() and feedback_rng.randf() < Config.SAFE_WORD_EVENT_CHANCE
	current_prompt = dialogue_controller.next_event(arousal_model.physical, arousal_model.emotional, should_force_safe_word)
	if current_prompt.is_empty():
		return
	if current_prompt.has("choices"):
		waiting_for_choice = true
		dialogue_panel.hide_prompt()
		dialogue_panel.append_history(str(current_prompt.get("text", Config.FEEDBACK_MESSAGE_TEXT)), "companion")
		choice_panel.show_choices(current_prompt.get("choices", {}))
		feedback_timer.stop()
		choice_timeout_timer.start(float(active_phase_config.choice_timeout_seconds))
	else:
		waiting_for_choice = false
		dialogue_panel.hide_prompt()
		dialogue_panel.append_history(str(current_prompt.get("text", Config.FEEDBACK_MESSAGE_TEXT)), "companion")
		choice_panel.clear_choices()
		choice_timeout_timer.stop()
		_schedule_next_feedback_message()

func _schedule_next_feedback_message() -> void:
	var wait_time := feedback_rng.randf_range(
		float(active_phase_config.feedback_message_interval_min),
		float(active_phase_config.feedback_message_interval_max)
	)
	feedback_timer.start(wait_time)

# ---------------------------------------------------------------------------
# Ending and phase transitions
# ---------------------------------------------------------------------------

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
	dialogue_panel.hide_prompt()
	choice_panel.clear_choices()
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

func _play_phase_transition_fade(overlay_start_color: Color, is_phase_transition: bool, ending_type: String = "") -> void:
	if phase_transition_overlay == null:
		if is_phase_transition:
			_complete_phase_transition()
		else:
			_request_ending_transition(ending_type)
		return
	var opaque_color := Color(overlay_start_color.r, overlay_start_color.g, overlay_start_color.b, 1.0)
	phase_transition_overlay.color = overlay_start_color
	phase_transition_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(phase_transition_overlay, "color", opaque_color, 1.0)
	tween.tween_interval(1.0)
	if is_phase_transition:
		tween.tween_callback(_complete_phase_transition)
		tween.tween_property(phase_transition_overlay, "color", overlay_start_color, 1.0)
		tween.tween_callback(func() -> void: phase_transition_overlay.visible = false)
	else:
		tween.tween_callback(func() -> void: _request_ending_transition(ending_type))

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

# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------

func _update_presentation() -> void:
	if Engine.is_editor_hint():
		return
	_update_character_visual_state()
	_update_bgm_state()
	character_area.update_emotion_state(arousal_model.get_emotion_state())
	arousal_visualization.set_values(arousal_model.physical, arousal_model.emotional, arousal_model.peak)
	status_hud.update_values(arousal_model.physical, arousal_model.emotional, arousal_model.peak)
	_update_phase_debug_label()
	if debug_overlay != null:
		debug_overlay.sync_live_readout(get_debug_state())

func _update_choice_timer_visual() -> void:
	if waiting_for_choice and not choice_timeout_timer.is_stopped():
		var progress := choice_timeout_timer.time_left / float(active_phase_config.choice_timeout_seconds)
		dialogue_panel.set_choice_timeout_progress(progress)
		return
	dialogue_panel.set_choice_timeout_progress(0.0)

func _update_bgm_state() -> void:
	var next_track_key := "default"
	var use_fade := false

	if has_switched_to_game_bgm:
		next_track_key = "overall_low" if arousal_model.peak >= 50.0 else "overall_high"
		use_fade = true
	elif arousal_model.peak_has_activated:
		has_switched_to_game_bgm = true
		next_track_key = "overall_low" if arousal_model.peak >= 50.0 else "overall_high"
		use_fade = true

	if last_requested_bgm_key == next_track_key:
		return
	last_requested_bgm_key = next_track_key
	bgm_requested.emit(next_track_key, use_fade)

func _update_phase_debug_label() -> void:
	if phase_debug_label == null:
		return
	phase_debug_label.text = "Phase: %s" % _get_active_phase_id()
	phase_debug_label.visible = debug_overlay != null and debug_overlay.visible
	if phase_skip_button != null:
		var can_skip := _get_active_phase_id() != "phase_2" and not phase_transition_in_progress
		phase_skip_button.visible = debug_overlay != null and debug_overlay.visible and can_skip
		phase_skip_button.disabled = not can_skip

func _update_layout_debug_regions() -> void:
	var debug_visible := show_layout_debug_bounds
	for region in layout_debug_regions:
		region.visible = debug_visible
	if character_prompt_region != null:
		character_prompt_region.set_debug_bounds_visible(debug_visible)
	if speech_bubble_anchor != null:
		speech_bubble_anchor.visible = debug_visible
	_set_choice_anchor_debug_visible(left_choice_anchor_root, debug_visible)
	_set_choice_anchor_debug_visible(right_choice_anchor_root, debug_visible)

func _apply_character_alignment() -> void:
	if character_alignment_root == null:
		return
	var phase_alignment_offset := _resolve_active_phase_alignment_offset()
	_resolved_character_alignment_offset = Vector2(
		shared_character_alignment_offset.x + phase_alignment_offset.x,
		phase_alignment_offset.y
	)
	character_alignment_root.position = _resolved_character_alignment_offset

func _resolve_active_phase_alignment_offset() -> Vector2:
	if active_character_profile == null or character_alignment_root == null:
		return Vector2.ZERO
	var focus_layer := _get_character_alignment_focus_layer()
	if focus_layer == null or focus_layer.texture == null:
		return Vector2.ZERO
	var focus_position := _get_texture_normalized_position_in_alignment_root(
		focus_layer,
		active_character_profile.character_visual_focus_normalized
	)
	var texture_size: Vector2 = focus_layer.texture.get_size()
	var bottom_position := _get_texture_visible_normalized_position_in_alignment_root(
		focus_layer,
		Vector2(
			active_character_profile.character_visual_focus_normalized.x,
			active_character_profile.get_character_visual_bottom_normalized(texture_size)
		)
	)
	var target_x := character_alignment_root.size.x * 0.5
	var target_y := character_alignment_root.size.y
	return Vector2(target_x - focus_position.x, target_y - bottom_position.y)

func _get_character_alignment_focus_layer() -> TextureRect:
	if _is_phase_2_visual_profile_active() and phase_2_background_layer != null and phase_2_background_layer.texture != null:
		return phase_2_background_layer
	return background_placeholder

func _get_texture_normalized_position_in_alignment_root(texture_rect: TextureRect, normalized_position: Vector2) -> Vector2:
	var texture := texture_rect.texture
	if texture == null:
		return Vector2.ZERO
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ZERO
	var root_transform: Transform2D = character_alignment_root.get_global_transform_with_canvas()
	var texture_transform: Transform2D = texture_rect.get_global_transform_with_canvas()
	var root_to_texture: Transform2D = root_transform.affine_inverse() * texture_transform
	var content_rect: Rect2 = _get_texture_content_rect(texture_rect, texture_size)
	return root_to_texture.origin + content_rect.position + content_rect.size * normalized_position

func _get_texture_visible_normalized_position_in_alignment_root(texture_rect: TextureRect, normalized_position: Vector2) -> Vector2:
	var texture := texture_rect.texture
	if texture == null:
		return Vector2.ZERO
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ZERO
	var root_transform: Transform2D = character_alignment_root.get_global_transform_with_canvas()
	var texture_transform: Transform2D = texture_rect.get_global_transform_with_canvas()
	var root_to_texture: Transform2D = root_transform.affine_inverse() * texture_transform
	var content_rect: Rect2 = _get_texture_content_rect(texture_rect, texture_size)
	var unclipped_position := content_rect.position + content_rect.size * normalized_position
	var clipped_position := unclipped_position.clamp(Vector2.ZERO, texture_rect.size)
	return root_to_texture.origin + clipped_position

func _get_texture_content_rect(texture_rect: TextureRect, texture_size: Vector2) -> Rect2:
	var rect_size: Vector2 = texture_rect.size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	match texture_rect.stretch_mode:
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var centered_scale: float = min(rect_size.x / texture_size.x, rect_size.y / texture_size.y)
			var centered_size: Vector2 = texture_size * centered_scale
			return Rect2((rect_size - centered_size) * 0.5, centered_size)
		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			var covered_scale: float = max(rect_size.x / texture_size.x, rect_size.y / texture_size.y)
			var covered_size: Vector2 = texture_size * covered_scale
			return Rect2((rect_size - covered_size) * 0.5, covered_size)
		TextureRect.STRETCH_KEEP_CENTERED:
			return Rect2((rect_size - texture_size) * 0.5, texture_size)
		TextureRect.STRETCH_KEEP_ASPECT:
			var aspect_scale: float = min(rect_size.x / texture_size.x, rect_size.y / texture_size.y)
			return Rect2(Vector2.ZERO, texture_size * aspect_scale)
		TextureRect.STRETCH_KEEP:
			return Rect2(Vector2.ZERO, texture_size)
		_:
			return Rect2(Vector2.ZERO, rect_size)

# ---------------------------------------------------------------------------
# Timer helpers
# ---------------------------------------------------------------------------

func _stop_runtime_timers() -> void:
	feedback_timer.stop()
	spot_spawn_timer.stop()
	choice_timeout_timer.stop()
	if spot_manager != null:
		spot_manager.stop()
	if overlay_animator != null:
		overlay_animator.stop()
	if breathing_controller != null and breathing_controller.has_method("stop_breathing"):
		breathing_controller.stop_breathing()
	if choice_panel != null:
		choice_panel.clear_choices()

# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------

func _sync_spot_anchor_layout() -> void:
	if Engine.is_editor_hint() or spot_manager == null or character_prompt_region == null:
		return
	spot_manager.set_available_anchor_ids(character_prompt_region.get_interaction_spot_anchor_ids())
	spot_manager.set_bounds_rect(_get_prompt_region_rect_in_prompt_layer())

func _get_choice_anchor_children(anchor_root: Control) -> Array[Control]:
	var anchors: Array[Control] = []
	if anchor_root == null:
		return anchors
	for child in anchor_root.get_children():
		if child is Control:
			anchors.append(child as Control)
	return anchors

func _set_choice_anchor_debug_visible(anchor_root: Control, debug_visible: bool) -> void:
	if anchor_root == null:
		return
	for child in anchor_root.get_children():
		if child is Control:
			(child as Control).visible = debug_visible

func _get_prompt_region_rect_in_prompt_layer() -> Rect2:
	var prompt_layer := character_area.get_node_or_null("PromptLayer") as Control
	if prompt_layer == null or character_prompt_region == null:
		return Rect2()
	var global_rect: Rect2 = character_prompt_region.get_region_global_rect()
	var local_position: Vector2 = prompt_layer.get_global_transform_with_canvas().affine_inverse() * global_rect.position
	return Rect2(local_position, global_rect.size)

func _update_prompt_anchor_layout_from_profile() -> void:
	if active_character_profile == null or character_prompt_region == null:
		return
	character_prompt_region.apply_profile(active_character_profile)
	character_prompt_region.set_debug_bounds_visible(show_layout_debug_bounds)

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
