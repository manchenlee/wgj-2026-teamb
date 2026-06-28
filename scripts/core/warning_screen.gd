extends Control

signal continue_pressed

func _ready() -> void:
	var leave := $WarningPanel/ContentContainer/VBoxContainer/ButtonRow/LeaveButton as Button
	var cont := $WarningPanel/ContentContainer/VBoxContainer/ButtonRow/ContinueButton as Button
	cont.pressed.connect(func() -> void: continue_pressed.emit())
	leave.pressed.connect(func() -> void: OS.shell_open("https://youtu.be/hP_dIGLADis?si=CXMait50siCZVQG1"))
