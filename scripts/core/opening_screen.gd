extends Control

signal continue_pressed

func _ready() -> void:
	$MarginContainer/VBoxContainer/ContinueButton.pressed.connect(func() -> void: continue_pressed.emit())

