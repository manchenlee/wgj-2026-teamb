class_name DirectionSequencePanel
extends PanelContainer

@onready var sequence_label: RichTextLabel = $MarginContainer/VBoxContainer/SequenceLabel
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/FeedbackLabel

func set_sequence_text(text_value: String) -> void:
	sequence_label.text = text_value

func show_feedback(text_value: String, color: Color) -> void:
	feedback_label.text = text_value
	feedback_label.modulate = Color(color.r, color.g, color.b, 0.0)
	feedback_label.position = Vector2(0.0, 10.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(feedback_label, "modulate:a", 1.0, 0.12)
	tween.tween_property(feedback_label, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.45)
	tween.set_parallel(true)
	tween.tween_property(feedback_label, "modulate:a", 0.0, 0.2)
	tween.tween_property(feedback_label, "position:y", -6.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
