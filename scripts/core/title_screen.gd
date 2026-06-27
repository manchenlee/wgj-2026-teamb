extends Control

signal start_pressed
signal debug_requested

func _ready() -> void:
	$MarginContainer/VBoxContainer/StartButton.pressed.connect(func() -> void: start_pressed.emit())
	$DebugHotspot.pressed.connect(func() -> void: debug_requested.emit())

