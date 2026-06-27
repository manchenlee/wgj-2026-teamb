extends Control

signal continue_pressed

func _ready() -> void:
	$BookPanel/ContentContainer/VBoxContainer/ContinueButton.pressed.connect(func() -> void: continue_pressed.emit())

