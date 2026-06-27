class_name TwoFrameOverlayAnimator
extends TextureRect

signal burst_finished

@export var idle_frame_1_duration: float = 1.2
@export var idle_frame_2_duration: float = 0.4
@export var burst_frame_duration: float = 0.15
@export var burst_cycle_count: int = 3

var _rng := RandomNumberGenerator.new()
var _motions: Dictionary = {}
var _motion_ids: Array[String] = []
var _tracks: Dictionary = {}
var _idle_ratio_min: int = 2
var _idle_ratio_max: int = 6
var _idle_initial_delay_max: float = 0.4
var _pending_burst_track_count: int = 0
var _default_idle_frame_1_duration: float = 1.2
var _default_idle_frame_2_duration: float = 0.4
var _default_burst_frame_duration: float = 0.15
var _default_burst_cycle_count: int = 3
var _default_idle_ratio_min: int = 2
var _default_idle_ratio_max: int = 6
var _default_idle_initial_delay_max: float = 0.4

# --- Static overlay support ---
# List of { "layer": TextureRect, "z_index": int } — never animated, always visible.
var _static_layers: Array = []

# --- Companion overlay support (e.g. hole tied to tentacle10) ---
# Config set via apply_phase2_overlay_profile:
#   "companion_linked_motion_id" : String   — which animated motion triggers the active state
#   "companion_frame_1_idle"     : Texture2D or null  — shown during frame-1 of companion cycle (null = transparent)
#   "companion_frame_2_idle"     : Texture2D          — shown during frame-2 of companion cycle
#   "companion_frame_1_active"   : Texture2D          — replaces frame-1 during burst/active state
#   "companion_frame_2_active"   : Texture2D          — frame-2 during burst/active state
#   "companion_z_index"          : int                — z_index of the companion layer node
var _companion_config: Dictionary = {}
var _companion_layer: TextureRect = null
var _companion_timer: Timer = null
var _companion_mode: String = "stopped"   # "stopped" / "idle" / "active"
var _companion_frame_index: int = 0       # 0 = frame-1, 1 = frame-2


func _ready() -> void:
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = null
	_default_idle_frame_1_duration = idle_frame_1_duration
	_default_idle_frame_2_duration = idle_frame_2_duration
	_default_burst_frame_duration = burst_frame_duration
	_default_burst_cycle_count = burst_cycle_count
	_default_idle_ratio_min = _idle_ratio_min
	_default_idle_ratio_max = _idle_ratio_max
	_default_idle_initial_delay_max = idle_frame_2_duration
	_idle_initial_delay_max = _default_idle_initial_delay_max


# ---------------------------------------------------------------------------
# Public API: motion set (unchanged Phase 1 behaviour)
# ---------------------------------------------------------------------------

func set_motion_set(motions: Dictionary) -> void:
	stop()
	_clear_tracks()
	_motions.clear()
	_motion_ids.clear()
	for motion_id_variant in motions.keys():
		var motion_id := String(motion_id_variant)
		var motion_frames = motions[motion_id]
		if typeof(motion_frames) != TYPE_ARRAY:
			push_warning("TwoFrameOverlayAnimator: motion '%s' is malformed; expected an array with 2 textures." % motion_id)
			continue
		var frames: Array = motion_frames
		if frames.size() != 2:
			push_warning("TwoFrameOverlayAnimator: motion '%s' is malformed; expected exactly 2 frames." % motion_id)
			continue
		var frame_1 := frames[0] as Texture2D
		var frame_2 := frames[1] as Texture2D
		if frame_1 == null or frame_2 == null:
			push_warning("TwoFrameOverlayAnimator: motion '%s' has missing frame textures and will be skipped." % motion_id)
			continue
		_motions[motion_id] = [frame_1, frame_2]
		_motion_ids.append(motion_id)
		_create_track(motion_id, frame_1, frame_2)

	if _motion_ids.is_empty():
		push_warning("TwoFrameOverlayAnimator: no valid two-frame motions were provided.")


# ---------------------------------------------------------------------------
# Public API: Phase 2 extended overlay profile
#
# config keys:
#   "static_overlays" : Array of { "texture": Texture2D, "z_index": int }
#
#   "companion" : Dictionary with keys:
#     "linked_motion_id"   : String
#     "frame_1_idle"       : Texture2D or null   (null = transparent/hidden)
#     "frame_2_idle"       : Texture2D
#     "frame_1_active"     : Texture2D or null   (null = transparent/hidden during burst frame-1)
#     "frame_2_active"     : Texture2D
#     "z_index"            : int
# ---------------------------------------------------------------------------

func apply_phase2_overlay_profile(config: Dictionary) -> void:
	_clear_static_overlays()
	_clear_companion()

	# --- Static overlays ---
	var static_list = config.get("static_overlays", [])
	for entry_variant in static_list:
		var entry: Dictionary = entry_variant as Dictionary
		if entry == null:
			continue
		var tex := entry.get("texture") as Texture2D
		if tex == null:
			continue
		var z_idx := int(entry.get("z_index", 0))
		_create_static_layer(tex, z_idx)

	# --- Companion overlay ---
	var companion_dict = config.get("companion", {})
	if not companion_dict.is_empty():
		_companion_config = companion_dict.duplicate()
		_create_companion_layer()


# ---------------------------------------------------------------------------
# Public API: playback
# ---------------------------------------------------------------------------

func play_idle() -> void:
	if _motion_ids.is_empty() and _companion_layer == null:
		stop()
		return
	_pending_burst_track_count = 0
	for motion_id in _motion_ids:
		_start_idle_cycle(motion_id, _rng.randf_range(0.0, _idle_initial_delay_max))
	_start_companion_idle()


func play_burst_random() -> void:
	if _motion_ids.is_empty():
		stop()
		return
	_pending_burst_track_count = _motion_ids.size()
	for motion_id in _motion_ids:
		_start_burst_cycle(motion_id)
	_start_companion_active()


func stop() -> void:
	_pending_burst_track_count = 0
	for motion_id_variant in _tracks.keys():
		var motion_id := String(motion_id_variant)
		var track: Dictionary = _tracks[motion_id]
		track["mode"] = "stopped"
		track["displayed_frame_index"] = 0
		track["burst_cycles_remaining"] = 0
		var timer := track.get("timer") as Timer
		if timer != null:
			timer.stop()
		var layer := track.get("layer") as TextureRect
		if layer != null:
			layer.visible = false
			layer.texture = null
		_tracks[motion_id] = track
	texture = null
	_stop_companion()


func apply_playback_profile(config: Dictionary = {}) -> void:
	idle_frame_1_duration = float(config.get("frame_1_duration", _default_idle_frame_1_duration))
	idle_frame_2_duration = float(config.get("frame_2_duration", _default_idle_frame_2_duration))
	burst_frame_duration = float(config.get("burst_frame_duration", _default_burst_frame_duration))
	burst_cycle_count = int(config.get("burst_cycle_count", _default_burst_cycle_count))
	_idle_ratio_min = int(config.get("idle_ratio_min", _default_idle_ratio_min))
	_idle_ratio_max = int(config.get("idle_ratio_max", _default_idle_ratio_max))
	_idle_initial_delay_max = float(config.get("initial_delay_max", idle_frame_2_duration))
	if _idle_ratio_min > _idle_ratio_max:
		var swapped_min := _idle_ratio_max
		_idle_ratio_max = _idle_ratio_min
		_idle_ratio_min = swapped_min


# ---------------------------------------------------------------------------
# get_overlay_layers — used by breathing controller; returns animated layers
# (excludes static overlays and companion because they must not receive
# the breathing shader)
# ---------------------------------------------------------------------------

func get_overlay_layers() -> Array[TextureRect]:
	var overlay_layers: Array[TextureRect] = []
	for motion_id_variant in _tracks.keys():
		var motion_id := String(motion_id_variant)
		var track: Dictionary = _tracks[motion_id]
		var layer := track.get("layer") as TextureRect
		if layer != null:
			overlay_layers.append(layer)
	return overlay_layers


# ---------------------------------------------------------------------------
# Internal: tracks (animated two-frame motions)
# ---------------------------------------------------------------------------

func _clear_tracks() -> void:
	for track_variant in _tracks.values():
		var track: Dictionary = track_variant
		var timer := track.get("timer") as Timer
		if timer != null:
			timer.queue_free()
		var layer := track.get("layer") as TextureRect
		if layer != null:
			layer.queue_free()
	_tracks.clear()


func _create_track(motion_id: String, frame_1: Texture2D, frame_2: Texture2D) -> void:
	var layer := TextureRect.new()
	layer.name = "%sOverlay" % motion_id
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.expand_mode = expand_mode
	layer.stretch_mode = stretch_mode
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture = null
	layer.visible = false
	add_child(layer)

	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_track_timer_timeout.bind(motion_id))
	add_child(timer)

	_tracks[motion_id] = {
		"frames": [frame_1, frame_2],
		"layer": layer,
		"timer": timer,
		"displayed_frame_index": 0,
		"burst_cycles_remaining": 0,
		"mode": "stopped"
	}


func _start_idle_cycle(motion_id: String, initial_delay: float = 0.0) -> void:
	if not _tracks.has(motion_id):
		return
	var track: Dictionary = _tracks[motion_id]
	var timer := track.get("timer") as Timer
	if timer != null:
		timer.stop()
	track["mode"] = "idle"
	track["displayed_frame_index"] = 0
	track["burst_cycles_remaining"] = 0
	_tracks[motion_id] = track
	_show_track_frame(motion_id)
	_schedule_track_next_frame(motion_id, _roll_idle_frame_1_duration() + initial_delay)


func _start_burst_cycle(motion_id: String) -> void:
	if not _tracks.has(motion_id):
		return
	var track: Dictionary = _tracks[motion_id]
	var timer := track.get("timer") as Timer
	if timer != null:
		timer.stop()
	track["mode"] = "burst"
	track["displayed_frame_index"] = 0
	track["burst_cycles_remaining"] = burst_cycle_count
	_tracks[motion_id] = track
	_show_track_frame(motion_id)
	_schedule_track_next_frame(motion_id, burst_frame_duration + _rng.randf_range(0.0, burst_frame_duration))


func _roll_idle_frame_1_duration() -> float:
	var idle_ratio := _rng.randi_range(_idle_ratio_min, _idle_ratio_max)
	idle_frame_1_duration = idle_frame_2_duration * float(idle_ratio)
	return idle_frame_1_duration


func _show_track_frame(motion_id: String) -> void:
	if not _tracks.has(motion_id):
		return
	var track: Dictionary = _tracks[motion_id]
	var frames: Array = track.get("frames", [])
	var layer := track.get("layer") as TextureRect
	if layer == null:
		return
	if frames.size() != 2:
		layer.texture = null
		layer.visible = false
		return
	var displayed_frame_index := int(track.get("displayed_frame_index", 0))
	layer.texture = frames[displayed_frame_index] as Texture2D
	layer.visible = layer.texture != null


func _schedule_track_next_frame(motion_id: String, duration: float) -> void:
	if not _tracks.has(motion_id):
		return
	var track: Dictionary = _tracks[motion_id]
	var timer := track.get("timer") as Timer
	if timer == null:
		return
	timer.start(maxf(duration, 0.01))


func _on_track_timer_timeout(motion_id: String) -> void:
	if not _tracks.has(motion_id):
		return
	var track: Dictionary = _tracks[motion_id]
	match str(track.get("mode", "stopped")):
		"idle":
			_advance_idle(motion_id)
		"burst":
			_advance_burst(motion_id)


func _advance_idle(motion_id: String) -> void:
	if not _tracks.has(motion_id):
		return
	var track: Dictionary = _tracks[motion_id]
	if int(track.get("displayed_frame_index", 0)) == 0:
		track["displayed_frame_index"] = 1
		_tracks[motion_id] = track
		_show_track_frame(motion_id)
		_schedule_track_next_frame(motion_id, idle_frame_2_duration)
		return
	_start_idle_cycle(motion_id)


func _advance_burst(motion_id: String) -> void:
	if not _tracks.has(motion_id):
		return
	var track: Dictionary = _tracks[motion_id]
	if int(track.get("displayed_frame_index", 0)) == 0:
		track["displayed_frame_index"] = 1
		_tracks[motion_id] = track
		_show_track_frame(motion_id)
		_schedule_track_next_frame(motion_id, burst_frame_duration)
		return

	track["burst_cycles_remaining"] = int(track.get("burst_cycles_remaining", 0)) - 1
	if int(track.get("burst_cycles_remaining", 0)) <= 0:
		_tracks[motion_id] = track
		_pending_burst_track_count = max(_pending_burst_track_count - 1, 0)
		_start_idle_cycle(motion_id, _rng.randf_range(0.0, _idle_initial_delay_max))
		if _pending_burst_track_count <= 0:
			# All animated tracks finished burst — restore companion to idle too
			_start_companion_idle()
			burst_finished.emit()
		return

	track["displayed_frame_index"] = 0
	_tracks[motion_id] = track
	_show_track_frame(motion_id)
	_schedule_track_next_frame(motion_id, burst_frame_duration)


# ---------------------------------------------------------------------------
# Internal: static overlays
# ---------------------------------------------------------------------------

func _clear_static_overlays() -> void:
	for entry_variant in _static_layers:
		var entry: Dictionary = entry_variant
		var layer := entry.get("layer") as TextureRect
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
	_static_layers.clear()


func _create_static_layer(tex: Texture2D, z_idx: int) -> void:
	var layer := TextureRect.new()
	layer.name = "StaticOverlay_%d" % z_idx
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.expand_mode = expand_mode
	layer.stretch_mode = stretch_mode
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture = tex
	layer.visible = true
	layer.z_index = z_idx
	layer.z_as_relative = false
	add_child(layer)
	_static_layers.append({"layer": layer, "z_index": z_idx})


# ---------------------------------------------------------------------------
# Internal: companion overlay (hole animation tied to tentacle10)
#
# Cycle behaviour:
#   idle mode  — frame-1 duration : frame-2 duration = 1:2  (inverted ratio vs tentacle idle
#                so frame-2 (hole_idle) is *longer*)
#   active mode — same 1:2 timing, but frame-1 = hole_using, frame-2 = active frame-2
#
# Per-spec timing: frame1 : frame2 = 1 : 2
# We reuse idle_frame_2_duration as the base unit.
#   frame-1 visible time = idle_frame_2_duration * 1
#   frame-2 visible time = idle_frame_2_duration * 2
# ---------------------------------------------------------------------------

func _create_companion_layer() -> void:
	if _companion_config.is_empty():
		return
	var z_idx := int(_companion_config.get("z_index", 10))
	var layer := TextureRect.new()
	layer.name = "CompanionHoleOverlay"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.expand_mode = expand_mode
	layer.stretch_mode = stretch_mode
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.texture = null
	layer.visible = false
	layer.z_index = z_idx
	layer.z_as_relative = false
	add_child(layer)
	_companion_layer = layer

	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(_on_companion_timer_timeout)
	add_child(timer)
	_companion_timer = timer


func _clear_companion() -> void:
	_companion_mode = "stopped"
	_companion_frame_index = 0
	if _companion_timer != null and is_instance_valid(_companion_timer):
		_companion_timer.stop()
		_companion_timer.queue_free()
	_companion_timer = null
	if _companion_layer != null and is_instance_valid(_companion_layer):
		_companion_layer.queue_free()
	_companion_layer = null
	_companion_config = {}


func _start_companion_idle() -> void:
	if _companion_layer == null:
		return
	if _companion_timer != null:
		_companion_timer.stop()
	_companion_mode = "idle"
	_companion_frame_index = 0
	_show_companion_frame()
	_schedule_companion_next_frame(_companion_frame_1_duration())


func _start_companion_active() -> void:
	if _companion_layer == null:
		return
	if _companion_timer != null:
		_companion_timer.stop()
	_companion_mode = "active"
	_companion_frame_index = 0
	_show_companion_frame()
	_schedule_companion_next_frame(_companion_frame_1_duration())


func _stop_companion() -> void:
	_companion_mode = "stopped"
	_companion_frame_index = 0
	if _companion_timer != null and is_instance_valid(_companion_timer):
		_companion_timer.stop()
	if _companion_layer != null and is_instance_valid(_companion_layer):
		_companion_layer.visible = false
		_companion_layer.texture = null


func _show_companion_frame() -> void:
	if _companion_layer == null:
		return
	var tex: Texture2D = null
	if _companion_mode == "idle":
		if _companion_frame_index == 0:
			tex = _companion_config.get("frame_1_idle") as Texture2D   # null = transparent
		else:
			tex = _companion_config.get("frame_2_idle") as Texture2D
	elif _companion_mode == "active":
		if _companion_frame_index == 0:
			tex = _companion_config.get("frame_1_active") as Texture2D  # null = transparent
		else:
			tex = _companion_config.get("frame_2_active") as Texture2D
	_companion_layer.texture = tex
	_companion_layer.visible = (_companion_mode != "stopped")


func _schedule_companion_next_frame(duration: float) -> void:
	if _companion_timer == null or not is_instance_valid(_companion_timer):
		return
	_companion_timer.start(maxf(duration, 0.01))


func _companion_frame_1_duration() -> float:
	# spec: frame1 : frame2 = 1 : 2   →  frame1 = frame2_duration * 1
	return idle_frame_2_duration * 1.0


func _companion_frame_2_duration() -> float:
	# spec: frame1 : frame2 = 1 : 2   →  frame2 = frame2_duration * 2
	return idle_frame_2_duration * 2.0


func _on_companion_timer_timeout() -> void:
	if _companion_layer == null or _companion_mode == "stopped":
		return
	if _companion_frame_index == 0:
		_companion_frame_index = 1
		_show_companion_frame()
		_schedule_companion_next_frame(_companion_frame_2_duration())
	else:
		_companion_frame_index = 0
		_show_companion_frame()
		_schedule_companion_next_frame(_companion_frame_1_duration())
