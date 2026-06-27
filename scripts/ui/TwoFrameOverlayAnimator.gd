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

func play_idle() -> void:
	if _motion_ids.is_empty():
		stop()
		return
	_pending_burst_track_count = 0
	for motion_id in _motion_ids:
		_start_idle_cycle(motion_id, _rng.randf_range(0.0, _idle_initial_delay_max))

func play_burst_random() -> void:
	if _motion_ids.is_empty():
		stop()
		return
	_pending_burst_track_count = _motion_ids.size()
	for motion_id in _motion_ids:
		_start_burst_cycle(motion_id)

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

func get_overlay_layers() -> Array[TextureRect]:
	var overlay_layers: Array[TextureRect] = []
	for motion_id_variant in _tracks.keys():
		var motion_id := String(motion_id_variant)
		var track: Dictionary = _tracks[motion_id]
		var layer := track.get("layer") as TextureRect
		if layer != null:
			overlay_layers.append(layer)
	return overlay_layers

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
			burst_finished.emit()
		return

	track["displayed_frame_index"] = 0
	_tracks[motion_id] = track
	_show_track_frame(motion_id)
	_schedule_track_next_frame(motion_id, burst_frame_duration)
