class_name ClickNote
extends InteractionNote

var target_center: Vector2 = Vector2(84.0, 84.0)
var target_radius: float = 40.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	super._ready()


func setup(config: Dictionary) -> void:
	super.setup(config)
	target_center = config.get("target_center", Vector2(84.0, 84.0)) as Vector2
	target_radius = float(config.get("target_radius", 40.0))


func _gui_input(event: InputEvent) -> void:
	if _resolved or _suspended or not visible:
		return
	var press_position := Vector2.ZERO
	var is_primary_press := false
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		is_primary_press = mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed
		press_position = mouse_button.position
	elif event is InputEventScreenTouch:
		var screen_touch := event as InputEventScreenTouch
		is_primary_press = screen_touch.pressed
		press_position = screen_touch.position
	if not is_primary_press or press_position.distance_to(target_center) > target_radius:
		return
	accept_event()
	_begin_interaction()
	progressed.emit(1.0)
	_resolve_completed()


func _draw() -> void:
	draw_circle(target_center, target_radius, Color(1.0, 0.48, 0.1, 0.68))
	draw_arc(target_center, target_radius, 0.0, TAU, 40, Color(1.0, 0.9, 0.4, 1.0), 4.0, true)
	draw_circle(target_center, target_radius * 0.24, Color(1.0, 1.0, 1.0, 0.95))
	_draw_approach_circle()


func _get_approach_center() -> Vector2:
	return target_center


func _get_approach_target_radius() -> float:
	return target_radius


func _set_note_input_enabled(enabled: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
