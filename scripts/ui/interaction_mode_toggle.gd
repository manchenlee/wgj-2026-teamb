class_name InteractionModeToggle
extends Control

signal toggle_requested()

const PSYCHOLOGICAL_MODE := 0
const PHYSIOLOGICAL_MODE := 1
const PANEL_COLOR := Color(0.18, 0.08, 0.13, 0.92)
const PANEL_HOVER_COLOR := Color(0.27, 0.11, 0.18, 0.96)
const BORDER_COLOR := Color(0.78, 0.58, 0.3, 0.95)
const ICON_COLOR := Color(0.96, 0.86, 0.62, 1.0)
const WARNING_PHYSICAL_COLOR := Color(1.0, 0.22, 0.16, 0.95)
const WARNING_PSYCHOLOGICAL_COLOR := Color(1.0, 0.7, 0.14, 0.95)
const WARNING_PULSE_SPEED: float = 4.0

@onready var toggle_button: Button = $ToggleButton
@onready var mode_label: Label = $ModeLabel

var _interaction_mode: int = PSYCHOLOGICAL_MODE
var _hovered: bool = false
var _imbalance_warning_active: bool = false
var _lower_score_mode: int = -1
var _warning_pulse_time: float = 0.0


func _ready() -> void:
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	toggle_button.mouse_entered.connect(_on_toggle_button_mouse_entered)
	toggle_button.mouse_exited.connect(_on_toggle_button_mouse_exited)
	_sync_presentation()
	set_process(false)


func _process(delta: float) -> void:
	_warning_pulse_time += delta
	queue_redraw()


func set_interaction_mode(mode: int) -> void:
	if mode != PSYCHOLOGICAL_MODE and mode != PHYSIOLOGICAL_MODE:
		push_warning("InteractionModeToggle received unsupported mode: %d" % mode)
		return
	_interaction_mode = mode
	_sync_presentation()


func get_interaction_mode() -> int:
	return _interaction_mode


func set_imbalance_warning(active: bool, lower_mode: int) -> void:
	if active and lower_mode != PSYCHOLOGICAL_MODE and lower_mode != PHYSIOLOGICAL_MODE:
		push_warning("InteractionModeToggle received unsupported lower mode: %d" % lower_mode)
		return
	var normalized_lower_mode := lower_mode if active else -1
	if _imbalance_warning_active == active and _lower_score_mode == normalized_lower_mode:
		return
	_imbalance_warning_active = active
	_lower_score_mode = normalized_lower_mode
	_warning_pulse_time = 0.0
	set_process(active)
	queue_redraw()


func is_imbalance_warning_active() -> bool:
	return _imbalance_warning_active


func get_lower_score_mode() -> int:
	return _lower_score_mode


func _on_toggle_button_pressed() -> void:
	toggle_requested.emit()


func _on_toggle_button_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_toggle_button_mouse_exited() -> void:
	_hovered = false
	queue_redraw()


func _sync_presentation() -> void:
	if mode_label != null:
		mode_label.text = "調音" if _interaction_mode == PHYSIOLOGICAL_MODE else "對話"
	if toggle_button != null:
		toggle_button.tooltip_text = (
			"切換至對話模式（Q）"
			if _interaction_mode == PHYSIOLOGICAL_MODE
			else "切換至調音模式（Q）"
		)
	queue_redraw()


func _draw() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_HOVER_COLOR if _hovered else PANEL_COLOR
	panel_style.border_color = _get_panel_border_color()
	panel_style.set_border_width_all(4 if _imbalance_warning_active else 2)
	panel_style.set_corner_radius_all(14)
	draw_style_box(panel_style, Rect2(Vector2.ZERO, size))

	if _interaction_mode == PHYSIOLOGICAL_MODE:
		_draw_tuning_icon()
	else:
		_draw_dialogue_icon()


func _get_panel_border_color() -> Color:
	if not _imbalance_warning_active:
		return BORDER_COLOR
	var warning_color := WARNING_PHYSICAL_COLOR \
			if _lower_score_mode == PHYSIOLOGICAL_MODE else WARNING_PSYCHOLOGICAL_COLOR
	var pulse_ratio := (sin(_warning_pulse_time * WARNING_PULSE_SPEED) + 1.0) * 0.5
	return warning_color.lerp(Color.WHITE, pulse_ratio * 0.45)


func _draw_dialogue_icon() -> void:
	var bubble_rect := Rect2(20.0, 23.0, 40.0, 28.0)
	draw_rect(bubble_rect, ICON_COLOR, false, 3.0, true)
	draw_polyline(
		PackedVector2Array([
			Vector2(31.0, 51.0),
			Vector2(27.0, 60.0),
			Vector2(40.0, 51.0),
		]),
		ICON_COLOR,
		3.0,
		true
	)
	for line_y in [32.0, 41.0]:
		draw_line(Vector2(28.0, line_y), Vector2(52.0, line_y), ICON_COLOR, 2.0, true)


func _draw_tuning_icon() -> void:
	var line_starts := [Vector2(21.0, 28.0), Vector2(21.0, 41.0), Vector2(21.0, 54.0)]
	var knob_x_values := [35.0, 49.0, 29.0]
	for index in range(line_starts.size()):
		var start: Vector2 = line_starts[index]
		draw_line(start, Vector2(59.0, start.y), ICON_COLOR, 3.0, true)
		draw_circle(Vector2(knob_x_values[index], start.y), 5.0, ICON_COLOR)
