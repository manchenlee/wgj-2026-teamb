class_name PauseMenu
extends Control

signal restart_requested
signal exit_requested

@onready var _continue_button: Button = $Buttons/ContinueButton/Button
@onready var _restart_button: Button = $Buttons/RestartButton/Button
@onready var _exit_button: Button = $Buttons/ExitButton/Button

var _paused_audio: Array[AudioStreamPlayer] = []

func _ready() -> void:
	_continue_button.pressed.connect(close)
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_exit_button.pressed.connect(func() -> void: exit_requested.emit())

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.keycode == KEY_ESCAPE and event.is_pressed() and not event.is_echo()):
		return
	var router := get_parent()
	if visible:
		close()
	elif router != null and router.current_screen_id == "game":
		open()
	else:
		return
	get_viewport().set_input_as_handled()

func open() -> void:
	if visible:
		return
	visible = true
	_paused_audio.clear()
	_pause_audio_in(get_parent())
	get_tree().paused = true
	_continue_button.grab_focus()

func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	for player in _paused_audio:
		if is_instance_valid(player):
			player.stream_paused = false
	_paused_audio.clear()

func _pause_audio_in(node: Node) -> void:
	if node is AudioStreamPlayer and node.playing and not node.stream_paused:
		node.stream_paused = true
		_paused_audio.append(node)
	for child in node.get_children():
		if child != self:
			_pause_audio_in(child)
