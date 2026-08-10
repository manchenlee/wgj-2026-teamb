class_name InteractionSpot
extends Control

# ---------------------------------------------------------------------------
# InteractionSpot — scrub-input handler and lifetime keeper for one spot.
#
# Responsibilities:
#   - Accept pointer / touch input and accumulate valid scrub distance.
#   - Manage the spot's visible lifetime via a Timer node (gameplay authority).
#   - Drive visual transitions via Tweens (visual only — no gameplay outcomes).
#   - Emit signals; never modify ArousalModel directly.
#
# Signals consumed by InteractionSpotManager:
#   scrub_started()          — first valid drag inside the circle
#   scrub_ended()            — pointer released / left / spot freed
#   scrubbed(distance)       — valid movement credited this event
#   completed()              — required scrub distance reached
#   expired(progress_ratio)  — lifetime elapsed before completion
# ---------------------------------------------------------------------------

signal scrub_started()
signal scrub_ended()
signal scrubbed(distance: float)
signal completed()
signal expired(progress_ratio: float)

# Configuration — set by InteractionSpotManager before add_child().
var spot_lifetime: float = 7.0
var required_scrub_distance: float = 400.0
var valid_motion_threshold: float = 3.0
var max_delta_per_event: float = 24.0
var spot_radius: float = 52.0

# Runtime state
var _scrub_distance: float = 0.0
var _resolved: bool = false
var _scrub_active: bool = false  # true while pointer is held inside
var _suspended: bool = false

var _mouse_held: bool = false
var _touch_active: bool = false
var _touch_index: int = -1
var _last_pointer_pos: Vector2 = Vector2.INF

var _center: Vector2 = Vector2.ZERO

# Visual state
var _spot_color: Color = Color(1.0, 0.85, 0.1, 1.0)   # golden yellow start
var _spot_scale: float = 1.0
@onready var lifetime_timer: Timer = $LifetimeTimer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# _center is based on spot_radius set via setup(), not on Control.size,
	# because setup() is called before add_child() so size may not reflect
	# the final value yet. spot_radius is always correct.
	_center = Vector2(spot_radius, spot_radius)
	lifetime_timer.wait_time = spot_lifetime
	lifetime_timer.one_shot = true
	lifetime_timer.timeout.connect(_on_lifetime_timer_timeout)
	lifetime_timer.start()
	_start_idle_visual_tween()
	queue_redraw()


func setup(config: Dictionary) -> void:
	spot_lifetime = float(config.get("spot_lifetime", 7.0))
	required_scrub_distance = float(config.get("required_scrub_distance", 400.0))
	valid_motion_threshold = float(config.get("valid_motion_threshold", 3.0))
	max_delta_per_event = float(config.get("max_delta_per_event", 24.0))
	spot_radius = float(config.get("spot_radius", 52.0))


func set_suspended(suspended: bool) -> void:
	if _suspended == suspended:
		return
	_suspended = suspended
	if suspended:
		_end_scrub()
	mouse_filter = Control.MOUSE_FILTER_IGNORE if suspended else Control.MOUSE_FILTER_STOP
	visible = not suspended
	set_process(not suspended)
	if lifetime_timer != null:
		lifetime_timer.set_paused(suspended)


func _draw() -> void:
	var draw_radius := spot_radius * _spot_scale
	# Filled circle
	draw_circle(_center, draw_radius, Color(_spot_color.r, _spot_color.g, _spot_color.b, _spot_color.a * 0.55))
	# Outline ring
	var ring_points: PackedVector2Array = PackedVector2Array()
	var steps := 48
	for i in range(steps + 1):
		var angle := TAU * float(i) / float(steps)
		ring_points.append(_center + Vector2.RIGHT.rotated(angle) * draw_radius)
	draw_polyline(ring_points, Color(_spot_color.r, _spot_color.g, _spot_color.b, _spot_color.a), 3.0, true)
	# Progress arc
	if _scrub_distance > 0.0:
		var progress := clampf(_scrub_distance / required_scrub_distance, 0.0, 1.0)
		var arc_points: PackedVector2Array = PackedVector2Array()
		var arc_steps := 48
		var end_angle := -PI * 0.5 + TAU * progress
		for i in range(arc_steps + 1):
			var t := float(i) / float(arc_steps)
			var angle := lerpf(-PI * 0.5, end_angle, t)
			arc_points.append(_center + Vector2.RIGHT.rotated(angle) * (draw_radius + 6.0))
		draw_polyline(arc_points, Color(1.0, 1.0, 1.0, 0.9), 4.0, true)


func _process(_delta: float) -> void:
	# Safety net: if the mouse button was released outside this node
	# (no mouse-up event delivered), detect and clean up.
	if _mouse_held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_scrub()


func _gui_input(event: InputEvent) -> void:
	if _resolved or _suspended:
		return

	# --- Mouse button ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_held = true
			_last_pointer_pos = event.position
			_notify_scrub_started_if_inside(event.position)
		else:
			_end_scrub()
		get_viewport().set_input_as_handled()
		return

	# --- Mouse motion ---
	if event is InputEventMouseMotion and _mouse_held:
		_process_pointer_move(event.position)
		get_viewport().set_input_as_handled()
		return

	# --- Touch begin / end ---
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_active = true
			_touch_index = event.index
			_last_pointer_pos = event.position
			_notify_scrub_started_if_inside(event.position)
		else:
			if event.index == _touch_index:
				_end_scrub()
		get_viewport().set_input_as_handled()
		return

	# --- Touch drag ---
	if event is InputEventScreenDrag and _touch_active and event.index == _touch_index:
		_process_pointer_move(event.position)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		# Reset reference point so re-entry does not credit the off-spot gap.
		_last_pointer_pos = Vector2.INF
		# If mouse button was somehow lost while outside, clean up.
		if _mouse_held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_end_scrub()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _notify_scrub_started_if_inside(pos: Vector2) -> void:
	if pos.distance_to(_center) <= spot_radius and not _scrub_active:
		_scrub_active = true
		emit_signal("scrub_started")


func _process_pointer_move(new_pos: Vector2) -> void:
	if _last_pointer_pos == Vector2.INF:
		_last_pointer_pos = new_pos
		return

	var inside_now := new_pos.distance_to(_center) <= spot_radius
	var inside_before := _last_pointer_pos.distance_to(_center) <= spot_radius

	if not inside_now or not inside_before:
		# Either endpoint is outside the circle — reset without crediting.
		_last_pointer_pos = new_pos
		return

	_accumulate_scrub(new_pos)


func _accumulate_scrub(new_pos: Vector2) -> void:
	var raw := (new_pos - _last_pointer_pos).length()
	_last_pointer_pos = new_pos

	if raw < valid_motion_threshold:
		return  # too small — stationary hold, no credit

	var credited := minf(raw, max_delta_per_event)
	_scrub_distance += credited

	emit_signal("scrubbed", credited)
	_update_visual_for_progress()

	if _scrub_distance >= required_scrub_distance:
		_resolve_completed()


func _end_scrub() -> void:
	var was_active := _scrub_active
	_mouse_held = false
	_touch_active = false
	_touch_index = -1
	_last_pointer_pos = Vector2.INF
	_scrub_active = false
	if was_active:
		emit_signal("scrub_ended")


func _resolve_completed() -> void:
	if _resolved:
		return
	_resolved = true
	_end_scrub()
	lifetime_timer.stop()
	emit_signal("completed")
	_play_success_visual()


func _on_lifetime_timer_timeout() -> void:
	if _resolved:
		return
	_resolved = true
	_end_scrub()
	var ratio := clampf(_scrub_distance / required_scrub_distance, 0.0, 1.0)
	emit_signal("expired", ratio)
	_play_expiry_visual()


# ---------------------------------------------------------------------------
# Visuals — Tweens only, no gameplay outcomes
# ---------------------------------------------------------------------------

func _start_idle_visual_tween() -> void:
	# Gently pulse alpha over time to draw attention.
	var tween := create_tween().set_loops()
	tween.tween_property(self, "modulate:a", 0.7, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _update_visual_for_progress() -> void:
	var progress := clampf(_scrub_distance / required_scrub_distance, 0.0, 1.0)
	# Transition from golden yellow → orange-red as progress rises.
	_spot_color = Color(
		lerpf(1.0, 0.9, progress),
		lerpf(0.85, 0.25, progress),
		lerpf(0.1, 0.05, progress),
		lerpf(1.0, 0.75, progress)
	)
	_spot_scale = lerpf(1.0, 0.72, progress)
	queue_redraw()

	# Spawn a floating musical-note placeholder label.
	if fmod(_scrub_distance, 60.0) < max_delta_per_event:
		_spawn_note_particle()


func _spawn_note_particle() -> void:
	var note := Label.new()
	note.text = "♪"
	note.add_theme_font_size_override("font_size", 22)
	note.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4, 1.0))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Position relative to this spot's local space so it appears beside the circle.
	var offset_x := randf_range(-spot_radius * 0.5, spot_radius * 0.5)
	note.position = _center + Vector2(offset_x, -spot_radius * 0.4)
	add_child(note)

	var tween := note.create_tween().set_parallel(true)
	tween.tween_property(note, "position:y", note.position.y - 40.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(note, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(note.queue_free)


func _play_success_visual() -> void:
	# Brief scale-up then fade out.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


func _play_expiry_visual() -> void:
	# Shrink and fade out.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
