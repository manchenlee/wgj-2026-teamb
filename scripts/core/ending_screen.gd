extends Control

const Config := preload("res://scripts/core/game_config.gd")

signal restart_pressed

@onready var result_label: Label = $MarginContainer/VBoxContainer/ResultSubtypeLabel
@onready var body_label: Label = $MarginContainer/VBoxContainer/EndingBody

func _ready() -> void:
	$MarginContainer/VBoxContainer/RestartButton.pressed.connect(func() -> void: restart_pressed.emit())

func set_result(result_type: String) -> void:
	result_label.text = "Result: %s" % result_type
	match result_type:
		Config.SUCCESS_ENDING:
			body_label.text = "Placeholder success ending. Replace with final narrative later."
		Config.PHYSICAL_FAILURE_ENDING:
			body_label.text = "Placeholder physical depletion failure. Replace later."
		Config.EMOTIONAL_FAILURE_ENDING:
			body_label.text = "Placeholder emotional depletion failure. Replace later."
		_:
			body_label.text = "Placeholder ending."
