extends Control

signal continue_pressed(safe_word: String)

const Config := preload("res://scripts/gameplay/GameConfig.gd")

@onready var continue_button: Button = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/ButtonRow/ContinueButton
@onready var reset_button: Button = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/ButtonRow/ResetButton
@onready var skip_button: Button = $SkipButton
@onready var safe_word_input: LineEdit = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/SafeWordInput

func _ready() -> void:
	safe_word_input.text_submitted.connect(_on_safe_word_submitted)
	continue_button.pressed.connect(_on_continue_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	safe_word_input.grab_focus()

func _on_continue_pressed() -> void:
	continue_pressed.emit(_get_safe_word())

func _on_safe_word_submitted(_submitted_text: String) -> void:
	_on_continue_pressed()

func _on_reset_pressed() -> void:
	safe_word_input.clear()
	safe_word_input.grab_focus()

func _on_skip_pressed() -> void:
	continue_pressed.emit(Config.SAFE_WORD_DEFAULT)

func _get_safe_word() -> String:
	if safe_word_input == null:
		return Config.SAFE_WORD_DEFAULT
	var safe_word := safe_word_input.text.strip_edges()
	if safe_word.is_empty():
		return Config.SAFE_WORD_DEFAULT
	return safe_word
