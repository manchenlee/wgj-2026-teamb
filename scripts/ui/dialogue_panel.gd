class_name DialoguePanel
extends PanelContainer

signal choice_selected(choice_quality: String)

@onready var history_label: RichTextLabel = $MarginContainer/VBoxContainer/ScrollableChatHistory/ChatHistory
@onready var speaker_label: Label = $MarginContainer/VBoxContainer/CurrentDialoguePrompt/SpeakerLabel
@onready var prompt_label: Label = $MarginContainer/VBoxContainer/CurrentDialoguePrompt/PromptText
@onready var good_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/GoodButton
@onready var neutral_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/NeutralButton
@onready var bad_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/BadButton

func _ready() -> void:
	good_button.pressed.connect(func() -> void: choice_selected.emit("good"))
	neutral_button.pressed.connect(func() -> void: choice_selected.emit("neutral"))
	bad_button.pressed.connect(func() -> void: choice_selected.emit("bad"))

func set_prompt(prompt: Dictionary) -> void:
	speaker_label.text = str(prompt.get("speaker", "Companion"))
	prompt_label.text = str(prompt.get("text", "..."))
	var choices: Dictionary = prompt.get("choices", {})
	good_button.text = str(choices.get("good", "Good"))
	neutral_button.text = str(choices.get("neutral", "Neutral"))
	bad_button.text = str(choices.get("bad", "Bad"))

func clear_history() -> void:
	history_label.text = ""

func append_history(line: String) -> void:
	if history_label.text.is_empty():
		history_label.text = line
	else:
		history_label.text += "\n" + line
	history_label.scroll_to_line(history_label.get_line_count())
