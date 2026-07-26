class_name StatusHUD
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")

@onready var heart_value_label: Label = $ArousalMeter/HeartValueLabel
@onready var arousal_fill_bar: TextureRect = $ArousalMeter/ArousalFillBar
@onready var treble_clef: TextureRect = $ArousalMeter/TrebleClef
@onready var fill_start_marker: Control = $ArousalMeter/FillStartMarker
@onready var fill_end_marker: Control = $ArousalMeter/FillEndMarker
@onready var note_center_guide: Control = $ArousalMeter/NoteCenterGuide

var _peak_value: float = 0.0

func _ready() -> void:
	_apply_meter_fill(_peak_value)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_meter_fill(_peak_value)

func update_values(_physical: float, _emotional: float, peak: float) -> void:
	_peak_value = Config.clamp_value(peak)
	heart_value_label.text = str(int(round(_peak_value)))
	_apply_meter_fill(_peak_value)

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
