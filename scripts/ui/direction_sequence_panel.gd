class_name DirectionSequencePanel
extends PanelContainer

@onready var sequence_label: RichTextLabel = $MarginContainer/VBoxContainer/SequenceLabel

func set_sequence_text(text_value: String) -> void:
	sequence_label.text = text_value
