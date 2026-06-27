class_name DialoguePanel
extends PanelContainer

signal choice_selected(choice_quality: String)

const Config := preload("res://scripts/gameplay/GameConfig.gd")

@onready var history_scroll: ScrollContainer = $MarginContainer/VBoxContainer/ScrollableChatHistory
@onready var history_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollableChatHistory/ChatHistoryList
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
	good_button.text = Config.TEST_RESPONSE_TEXT
	neutral_button.text = Config.TEST_RESPONSE_TEXT
	bad_button.text = Config.TEST_RESPONSE_TEXT

func clear_history() -> void:
	for child in history_list.get_children():
		child.queue_free()

func append_history(line: String) -> void:
	var message_label := Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.text = line
	message_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	message_label.scale = Vector2(0.94, 0.94)
	history_list.add_child(message_label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(message_label, "modulate:a", 1.0, 0.22)
	tween.tween_property(message_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	call_deferred("_scroll_to_latest")

func _scroll_to_latest() -> void:
	history_scroll.scroll_vertical = int(history_scroll.get_v_scroll_bar().max_value)
