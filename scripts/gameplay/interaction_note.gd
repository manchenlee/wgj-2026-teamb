class_name InteractionNote
extends Control

signal interaction_started()
signal interaction_ended()
signal progressed(progress_delta: float)
signal completed()
signal expired(progress_ratio: float)

var spot_lifetime: float = 7.0
var approach_start_scale: float = 2.0

var _resolved: bool = false
var _suspended: bool = false
var _interaction_active: bool = false

@onready var lifetime_timer: Timer = $LifetimeTimer


func _ready() -> void:
	_set_note_input_enabled(true)
	lifetime_timer.wait_time = spot_lifetime
	lifetime_timer.one_shot = true
	lifetime_timer.timeout.connect(_on_lifetime_timer_timeout)
	lifetime_timer.start()
	_start_idle_visual_tween()
	queue_redraw()


func setup(config: Dictionary) -> void:
	spot_lifetime = float(config.get("spot_lifetime", 7.0))
	approach_start_scale = float(config.get("approach_start_scale", 2.0))


func set_suspended(suspended: bool) -> void:
	if _suspended == suspended:
		return
	_suspended = suspended
	if suspended:
		_end_interaction()
		_on_suspended()
	else:
		_on_resumed()
	visible = not suspended
	_set_note_input_enabled(not suspended)
	set_process(not suspended)
	if lifetime_timer != null:
		lifetime_timer.set_paused(suspended)


func force_complete() -> void:
	_resolve_completed()


func force_expire() -> void:
	_resolve_expired()


func get_progress_ratio() -> float:
	return 0.0


func _restart_lifetime() -> void:
	if _resolved or lifetime_timer == null:
		return
	lifetime_timer.start(spot_lifetime)
	queue_redraw()


func _process(_delta: float) -> void:
	# Lifetime feedback is timer-driven, but must redraw while its time_left changes.
	queue_redraw()


func _draw_approach_circle() -> void:
	if lifetime_timer == null or lifetime_timer.is_stopped():
		return
	var target_radius := _get_approach_target_radius()
	if target_radius <= 0.0:
		return
	var remaining_ratio := clampf(lifetime_timer.time_left / maxf(spot_lifetime, 0.001), 0.0, 1.0)
	var approach_radius := _calculate_approach_radius(remaining_ratio)
	var center := _get_approach_center()
	var mask_width := maxf(approach_radius - target_radius, 0.0)
	if mask_width > 0.5:
		# A translucent white annulus separates the shrinking timing ring from
		# the solid note, matching the UI reference instead of leaving a clear gap.
		draw_arc(
			center,
			target_radius + mask_width * 0.5,
			0.0,
			TAU,
			64,
			Color(1.0, 1.0, 1.0, 0.14),
			mask_width,
			true
		)
	var approach_color := _get_approach_color()
	draw_arc(
		center,
		approach_radius,
		0.0,
		TAU,
		48,
		approach_color,
		3.0,
		true
	)


func _draw_note_circle(center: Vector2, radius: float, fill_color: Color) -> void:
	# The bloom inherits the note color; only the fine rim remains white.
	_draw_continuous_ring_glow(center, radius, 14.0, fill_color, 0.38)
	draw_circle(center, radius, fill_color)
	draw_arc(center, radius, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.96), 2.5, true)


func _draw_continuous_ring_glow(
	center: Vector2,
	radius: float,
	glow_width: float,
	color: Color,
	peak_alpha: float
) -> void:
	if radius <= 0.0 or glow_width <= 0.0 or peak_alpha <= 0.0:
		return
	var segment_count := 96
	var inner_radius := maxf(0.0, radius - glow_width)
	var outer_radius := radius + glow_width
	var transparent := Color(color.r, color.g, color.b, 0.0)
	var peak := Color(color.r, color.g, color.b, peak_alpha)
	for index in range(segment_count):
		var angle_a := TAU * float(index) / float(segment_count)
		var angle_b := TAU * float(index + 1) / float(segment_count)
		var direction_a := Vector2.from_angle(angle_a)
		var direction_b := Vector2.from_angle(angle_b)
		# Two radial strips meet at the ring. Vertex colors are interpolated by
		# the renderer, producing one smooth bloom instead of stacked bands.
		draw_polygon(
			PackedVector2Array([
				center + direction_a * inner_radius,
				center + direction_a * radius,
				center + direction_b * radius,
				center + direction_b * inner_radius,
			]),
			PackedColorArray([transparent, peak, peak, transparent])
		)
		draw_polygon(
			PackedVector2Array([
				center + direction_a * radius,
				center + direction_a * outer_radius,
				center + direction_b * outer_radius,
				center + direction_b * radius,
			]),
			PackedColorArray([peak, transparent, transparent, peak])
		)


func _calculate_approach_radius(remaining_ratio: float) -> float:
	var target_radius := _get_approach_target_radius()
	return lerpf(
		target_radius,
		target_radius * approach_start_scale,
		clampf(remaining_ratio, 0.0, 1.0)
	)


func _get_approach_center() -> Vector2:
	return Vector2.ZERO


func _get_approach_target_radius() -> float:
	return 0.0


func _get_approach_color() -> Color:
	return Color(1.0, 0.32, 0.36, 0.96)


func _begin_interaction() -> void:
	if _interaction_active:
		return
	_interaction_active = true
	interaction_started.emit()


func _end_interaction() -> void:
	if not _interaction_active:
		return
	_interaction_active = false
	interaction_ended.emit()


func _resolve_completed() -> void:
	if _resolved:
		return
	_resolved = true
	_end_interaction()
	_set_note_input_enabled(false)
	if lifetime_timer != null:
		lifetime_timer.stop()
	completed.emit()
	_play_success_visual()


func _resolve_expired() -> void:
	if _resolved:
		return
	_resolved = true
	_end_interaction()
	_set_note_input_enabled(false)
	if lifetime_timer != null:
		lifetime_timer.stop()
	expired.emit(get_progress_ratio())
	_play_expiry_visual()


func _on_lifetime_timer_timeout() -> void:
	_resolve_expired()


func _set_note_input_enabled(_enabled: bool) -> void:
	pass


func _on_suspended() -> void:
	pass


func _on_resumed() -> void:
	pass


func _start_idle_visual_tween() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "modulate:a", 0.78, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_success_visual() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.12, 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


func _play_expiry_visual() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.82, 0.82), 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
