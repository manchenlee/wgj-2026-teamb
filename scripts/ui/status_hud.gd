class_name StatusHUD
extends PanelContainer

@onready var physical_value_display: Label = $MarginContainer/LayoutRow/LeftStats/PhysicalValueDisplay
@onready var emotional_value_display: Label = $MarginContainer/LayoutRow/RightStats/EmotionalValueDisplay
@onready var peak_value_display: Label = $MarginContainer/LayoutRow/LeftStats/PeakValueDisplay
@onready var combo_label: Label = $MarginContainer/LayoutRow/LeftStats/ComboLabel

func update_values(physical: float, emotional: float, peak: float) -> void:
	physical_value_display.text = "Physical: %d" % int(round(physical))
	emotional_value_display.text = "Emotional: %d" % int(round(emotional))
	peak_value_display.text = "Peak: %d" % int(round(peak))

func update_combo(combo: int) -> void:
	combo_label.text = "Combo: %d" % combo
