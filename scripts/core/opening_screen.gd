extends Control

signal continue_pressed

func _ready() -> void:
	$BookPanel/OuterMargin/Layout/ContinueButton.pressed.connect(
		func() -> void: continue_pressed.emit()
	)
