extends Control

signal continue_pressed(safe_word: String)

@onready var continue_button: Button = $BookPanel/ContentContainer/VBoxContainer/SafeWordRow/ContinueButton
@onready var safe_word_input: LineEdit = $BookPanel/ContentContainer/VBoxContainer/SafeWordRow/SafeWordInput

func _ready() -> void:
	if safe_word_input != null:
		safe_word_input.text_submitted.connect(_on_safe_word_submitted)
	continue_button.pressed.connect(
		_on_continue_pressed
	)

func _on_continue_pressed() -> void:
	continue_pressed.emit(_get_safe_word())

func _on_safe_word_submitted(_submitted_text: String) -> void:
	_on_continue_pressed()

func _get_safe_word() -> String:
	if safe_word_input == null:
		return "紅色"
	var safe_word := safe_word_input.text.strip_edges()
	if safe_word.is_empty():
		return "紅色"
	return safe_word
