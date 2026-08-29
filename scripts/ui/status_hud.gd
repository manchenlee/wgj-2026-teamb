class_name StatusHUD
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const WARNING_OUTLINE_COLOR := Color(1.0, 0.18, 0.12, 0.95)
const WARNING_MODULATE_MIN := Color(1.0, 0.72, 0.68, 1.0)
const WARNING_MODULATE_MAX := Color(1.0, 1.0, 1.0, 1.0)
const WARNING_PULSE_SPEED: float = 4.0

@onready var heart_value_label: Label = $ArousalMeter/HeartValueLabel
@onready var arousal_fill_bar: TextureRect = $ArousalMeter/ArousalFillBar
@onready var treble_clef: TextureRect = $ArousalMeter/TrebleClef
@onready var fill_start_marker: Control = $ArousalMeter/FillStartMarker
@onready var fill_end_marker: Control = $ArousalMeter/FillEndMarker
@onready var note_center_guide: Control = $ArousalMeter/NoteCenterGuide
@onready var legacy_arousal_meter: Control = $ArousalMeter
@onready var physical_value_label: Label = $NumericScores/PhysicalScore/Value
@onready var emotional_value_label: Label = $NumericScores/EmotionalScore/Value
@onready var combo_label: Label = $ComboLabel

@export var show_legacy_meter: bool = false

var _peak_value: float = 0.0
var _physical_low_warning_active: bool = false
var _emotional_low_warning_active: bool = false
var _warning_pulse_time: float = 0.0
var _combo_pulse_tween: Tween = null

func _ready() -> void:
	legacy_arousal_meter.visible = show_legacy_meter
	_apply_meter_fill(_peak_value)
	set_process(false)
	_apply_score_warning_presentation()
	update_combo(0)


func _process(delta: float) -> void:
	_warning_pulse_time += delta
	_apply_score_warning_presentation()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_meter_fill(_peak_value)

func update_values(physical: float, emotional: float, peak: float) -> void:
	physical_value_label.text = str(int(round(Config.clamp_value(physical))))
	emotional_value_label.text = str(int(round(Config.clamp_value(emotional))))
	_peak_value = Config.clamp_value(peak)
	heart_value_label.text = str(int(round(_peak_value)))
	_apply_meter_fill(_peak_value)


func update_combo(combo: int, pulse: bool = false) -> void:
	_cancel_combo_pulse()
	combo_label.text = "%d COMBO" % combo
	combo_label.visible = combo >= 2
	combo_label.pivot_offset = combo_label.size * 0.5
	if not combo_label.visible or not pulse:
		return
	_combo_pulse_tween = create_tween()
	_combo_pulse_tween.tween_property(combo_label, "scale", Vector2(1.16, 1.16), 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_pulse_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func set_score_warnings(physical_low: bool, emotional_low: bool) -> void:
	if (
		_physical_low_warning_active == physical_low
		and _emotional_low_warning_active == emotional_low
	):
		return
	_physical_low_warning_active = physical_low
	_emotional_low_warning_active = emotional_low
	_warning_pulse_time = 0.0
	set_process(physical_low or emotional_low)
	_apply_score_warning_presentation()


func _cancel_combo_pulse() -> void:
	if _combo_pulse_tween != null and _combo_pulse_tween.is_valid():
		_combo_pulse_tween.kill()
	_combo_pulse_tween = null
	combo_label.scale = Vector2.ONE


func is_physical_low_warning_active() -> bool:
	return _physical_low_warning_active


func is_emotional_low_warning_active() -> bool:
	return _emotional_low_warning_active


func set_legacy_meter_visible(legacy_visible: bool) -> void:
	show_legacy_meter = legacy_visible
	if is_node_ready():
		legacy_arousal_meter.visible = legacy_visible

func _apply_meter_fill(peak: float) -> void:
	if not is_node_ready():
		return
	var fill_ratio := Config.clamp_value(peak) / Config.MAX_VALUE
	var fill_start := fill_start_marker.position
	var fill_end := fill_end_marker.position
	var fill_width := maxf(fill_end.x - fill_start.x, 0.0)
	var note_center_x := fill_start.x + (fill_width * fill_ratio)

	arousal_fill_bar.position = fill_start
	arousal_fill_bar.size.x = maxf(note_center_x - fill_start.x, 0.0)
	treble_clef.position.x = note_center_x - treble_clef.pivot_offset.x


func _apply_score_warning_presentation() -> void:
	_apply_label_warning(physical_value_label, _physical_low_warning_active)
	_apply_label_warning(emotional_value_label, _emotional_low_warning_active)


func _apply_label_warning(label: Label, warning_active: bool) -> void:
	if label == null:
		return
	if not warning_active:
		label.remove_theme_color_override("font_outline_color")
		label.remove_theme_constant_override("outline_size")
		label.modulate = Color.WHITE
		return
	var pulse_ratio := (sin(_warning_pulse_time * WARNING_PULSE_SPEED) + 1.0) * 0.5
	label.add_theme_color_override("font_outline_color", WARNING_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", 5)
	label.modulate = WARNING_MODULATE_MIN.lerp(WARNING_MODULATE_MAX, pulse_ratio)
