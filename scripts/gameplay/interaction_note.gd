class_name InteractionNote
extends Control

signal interaction_started()
signal interaction_ended()
signal progressed(progress_delta: float)
signal completed()
signal expired(progress_ratio: float)

var spot_lifetime: float = 7.0

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


func _process(_delta: float) -> void:
	# Lifetime feedback is timer-driven, but must redraw while its time_left changes.
	queue_redraw()


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
