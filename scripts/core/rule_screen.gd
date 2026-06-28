extends Control

signal continue_pressed

@onready var continue_button: Button = $BookPanel/ContentContainer/VBoxContainer/SafeWordRow/ContinueButton

func _ready() -> void:
	continue_button.pressed.connect(
		func() -> void: continue_pressed.emit()
	)
