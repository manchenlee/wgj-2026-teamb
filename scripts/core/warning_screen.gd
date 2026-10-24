extends Control

signal continue_pressed

@onready var leave_button: Button = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/ButtonRow/LeaveButton
@onready var continue_button: Button = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/ButtonRow/ContinueButton

func _ready() -> void:
	continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	leave_button.pressed.connect(func() -> void: OS.shell_open("https://youtu.be/hP_dIGLADis?si=CXMait50siCZVQG1"))
