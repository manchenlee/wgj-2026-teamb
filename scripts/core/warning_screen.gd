extends Control

signal continue_pressed

func _ready() -> void:
	var leave := $WarningPanel/ContentContainer/VBoxContainer/ButtonRow/LeaveButton as Button
	var cont := $WarningPanel/ContentContainer/VBoxContainer/ButtonRow/ContinueButton as Button

	# 灰色按鈕樣式
	var grey := StyleBoxFlat.new()
	grey.bg_color = Color(0.55, 0.55, 0.55, 1)
	grey.set_corner_radius_all(8)
	grey.content_margin_left = 24
	grey.content_margin_right = 24
	grey.content_margin_top = 12
	grey.content_margin_bottom = 12
	leave.add_theme_stylebox_override("normal", grey)
	leave.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	# 粉紅色按鈕樣式
	var pink := StyleBoxFlat.new()
	pink.bg_color = Color(0.95, 0.55, 0.65, 1)
	pink.set_corner_radius_all(8)
	pink.content_margin_left = 24
	pink.content_margin_right = 24
	pink.content_margin_top = 12
	pink.content_margin_bottom = 12
	cont.add_theme_stylebox_override("normal", pink)
	cont.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	cont.pressed.connect(func() -> void: continue_pressed.emit())
	leave.pressed.connect(func() -> void: OS.shell_open("https://youtu.be/hP_dIGLADis?si=CXMait50siCZVQG1"))
