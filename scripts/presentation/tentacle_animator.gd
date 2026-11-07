class_name TentacleAnimator
extends Control

const FRAME_SECONDS: float = 0.32

var _rng := RandomNumberGenerator.new()
var _tracks: Array[Dictionary] = []
var _tail_tracks: Array[Dictionary] = []
var _pose_name: String = "sitting"
var _tail_index: int = 0

func _ready() -> void:
	_rng.randomize()

func configure(profile: PoseCharacterProfile, texture_loader: Callable) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_tracks.clear()
	_tail_tracks.clear()
	_pose_name = profile.pose_name
	_tail_index = 0
	for paths in profile.get_tentacle_part_paths():
		_add_track(paths, texture_loader, _tracks)
	for paths in profile.get_tail_tentacle_paths():
		_add_track(paths, texture_loader, _tail_tracks)
	for index in range(_tracks.size()):
		# Offset frame changes while keeping every part visible at all times.
		_tracks[index]["time"] = 0.15 * index + _rng.randf_range(0.0, 0.08)
	for index in range(_tail_tracks.size()):
		_tail_tracks[index]["time"] = 0.11 * index + 0.07
	_update_textures()

func set_tail_index(index: int) -> void:
	_tail_index = clampi(index, 0, 2)
	_update_textures()

func advance(delta: float) -> void:
	for track in _tracks:
		_advance_track(track, delta)
	for track in _tail_tracks:
		_advance_track(track, delta)
	_update_textures()

func _add_track(paths: Array, texture_loader: Callable, destination: Array[Dictionary]) -> void:
	var frames: Array[Texture2D] = []
	for path in paths:
		var texture := texture_loader.call(path) as Texture2D
		if texture != null:
			frames.append(texture)
	if frames.size() != 3:
		push_warning("Tentacle track is missing frames: %s" % str(paths))
		return
	var layer := TextureRect.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(layer)
	destination.append({"layer": layer, "frames": frames, "time": 0.0,
		"frame_seconds": FRAME_SECONDS + _rng.randf_range(-0.06, 0.06)})

func _advance_track(track: Dictionary, delta: float) -> void:
	track["time"] = float(track["time"]) + delta

func _update_textures() -> void:
	for track in _tracks:
		_show_track(track, true)
	for index in range(_tail_tracks.size()):
		# Sitting: tail 1/2/3 are score stages. Standing: all three
		# tail attachments follow the corresponding base-tail frame.
		_show_track(_tail_tracks[index], _pose_name == "standing" or index == _tail_index)

func _show_track(track: Dictionary, selected: bool) -> void:
	var layer := track["layer"] as TextureRect
	var elapsed := float(track["time"])
	var frame := floori(elapsed / float(track["frame_seconds"])) % 3
	if _pose_name == "standing" and _tail_tracks.has(track):
		frame = _tail_index
	layer.texture = track["frames"][frame]
	layer.visible = selected
