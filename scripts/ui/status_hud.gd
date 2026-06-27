class_name StatusHUD
extends PanelContainer

const Config := preload("res://scripts/gameplay/GameConfig.gd")

signal direction_pressed(direction: String)

@onready var physical_value_display: Label = $MarginContainer/VBoxContainer/StatsRow/PhysicalValueDisplay
@onready var emotional_value_display: Label = $MarginContainer/VBoxContainer/StatsRow/EmotionalValueDisplay
@onready var peak_value_display: Label = $MarginContainer/VBoxContainer/StatsRow/PeakValueDisplay
@onready var combo_label: Label = $MarginContainer/VBoxContainer/MetaRow/ComboLabel
@onready var timer_bar: ProgressBar = $MarginContainer/VBoxContainer/MetaRow/TimerBar
@onready var direction_panel = $MarginContainer/VBoxContainer/DirectionSequencePanel
@onready var left_button: Button = $MarginContainer/VBoxContainer/MobileDirectionButtons/LeftButton
@onready var up_button: Button = $MarginContainer/VBoxContainer/MobileDirectionButtons/UpButton
@onready var down_button: Button = $MarginContainer/VBoxContainer/MobileDirectionButtons/DownButton
@onready var right_button: Button = $MarginContainer/VBoxContainer/MobileDirectionButtons/RightButton

func _ready() -> void:
	left_button.focus_mode = Control.FOCUS_NONE
	up_button.focus_mode = Control.FOCUS_NONE
	down_button.focus_mode = Control.FOCUS_NONE
	right_button.focus_mode = Control.FOCUS_NONE
	left_button.pressed.connect(func() -> void: direction_pressed.emit("Left"))
	up_button.pressed.connect(func() -> void: direction_pressed.emit("Up"))
	down_button.pressed.connect(func() -> void: direction_pressed.emit("Down"))
	right_button.pressed.connect(func() -> void: direction_pressed.emit("Right"))

func update_values(physical: float, emotional: float, peak: float) -> void:
	physical_value_display.text = "Physical: %d" % int(round(physical))
	emotional_value_display.text = "Emotional: %d" % int(round(emotional))
	peak_value_display.text = "Peak: %d" % int(round(peak))

func update_combo(combo: int) -> void:
	combo_label.text = "Combo: %d" % combo

func update_timer(time_left: float) -> void:
	timer_bar.max_value = Config.DIRECTION_SEQUENCE_TIME_LIMIT
	timer_bar.value = time_left

func update_sequence_text(text_value: String) -> void:
	direction_panel.set_sequence_text(text_value)

func show_sequence_feedback(text_value: String, color: Color) -> void:
	direction_panel.show_feedback(text_value, color)
