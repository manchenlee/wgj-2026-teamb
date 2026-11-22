extends Control

signal continue_pressed(safe_word: String)

const Config := preload("res://scripts/gameplay/GameConfig.gd")

@onready var continue_button: Button = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/ButtonRow/ContinueButton
@onready var reset_button: Button = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/ButtonRow/ResetButton
@onready var safe_word_input: LineEdit = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/SafeWordInput
@onready var character_counter: Label = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/SafeWordInput/CharacterCounter
@onready var limit_warning: Label = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/SafeWordInput/LimitWarning
@onready var warning_timer: Timer = $ModalCenter/PromptPanel/PanelLayout/ContentMargin/Content/SafeWordInput/WarningTimer

var _submitted := false
var _counter_color: Color

func _ready() -> void:
	safe_word_input.text = Config.SAFE_WORD_DEFAULT
	_counter_color = character_counter.get_theme_color("font_color")
	safe_word_input.text_changed.connect(_on_safe_word_changed)
	warning_timer.timeout.connect(_clear_limit_warning)
	_update_counter()
	safe_word_input.text_submitted.connect(_on_safe_word_submitted)
	continue_button.pressed.connect(_on_continue_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	safe_word_input.grab_focus()

func _on_continue_pressed() -> void:
	if _submitted:
		return
	_submitted = true
	continue_pressed.emit(_get_safe_word())

func _on_safe_word_submitted(_submitted_text: String) -> void:
	_on_continue_pressed()

func _on_reset_pressed() -> void:
	safe_word_input.clear()
	_clear_limit_warning()
	_update_counter()
	safe_word_input.grab_focus()

func _on_safe_word_changed(new_text: String) -> void:
	if new_text.length() > Config.SAFE_WORD_MAX_LENGTH:
		var caret_position := safe_word_input.caret_column
		safe_word_input.text = new_text.substr(0, Config.SAFE_WORD_MAX_LENGTH)
		safe_word_input.caret_column = mini(caret_position, Config.SAFE_WORD_MAX_LENGTH)
		_show_limit_warning()
	_update_counter()

func _update_counter() -> void:
	character_counter.text = "%d / %d" % [safe_word_input.text.length(), Config.SAFE_WORD_MAX_LENGTH]

func _show_limit_warning() -> void:
	character_counter.add_theme_color_override("font_color", limit_warning.get_theme_color("font_color"))
	limit_warning.show()
	warning_timer.start()

func _clear_limit_warning() -> void:
	warning_timer.stop()
	character_counter.add_theme_color_override("font_color", _counter_color)
	limit_warning.hide()

func _get_safe_word() -> String:
	if safe_word_input == null:
		return Config.SAFE_WORD_DEFAULT
	return Config.normalize_safe_word(safe_word_input.text)
