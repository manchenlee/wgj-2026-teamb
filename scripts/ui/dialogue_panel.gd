class_name DialoguePanel
extends PanelContainer

signal choice_selected(choice_quality: String, choice_text: String)

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const CHARACTER_BUBBLE_TEXTURE := preload("res://assets/art/ui/text2.png")
const PLAYER_BUBBLE_TEXTURE := preload("res://assets/art/ui/text.png")
const INACTIVE_CHOICE_TEXTS := ["test", "choice", "response"]
const DISABLED_CHOICE_MODULATE := Color(0.42, 0.42, 0.42, 1.0)
const BUBBLE_DISPLAY_WIDTH := 300.0
const BUBBLE_TEXT_HORIZONTAL_MARGIN := 28
const BUBBLE_TEXT_VERTICAL_MARGIN := 14

@onready var history_scroll: Control = $MarginContainer/VBoxContainer/ScrollableChatHistory
@onready var history_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollableChatHistory/ChatHistoryList
@onready var choice_countdown_bar: ProgressBar = $MarginContainer/VBoxContainer/ChoiceCountdownBar
@onready var good_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/GoodButton
@onready var neutral_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/NeutralButton
@onready var bad_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/BadButton
@onready var choice_button_backgrounds: Array[TextureRect] = [
	$MarginContainer/VBoxContainer/ChoiceButtons/GoodButton/Background,
	$MarginContainer/VBoxContainer/ChoiceButtons/NeutralButton/Background,
	$MarginContainer/VBoxContainer/ChoiceButtons/BadButton/Background
]

func _ready() -> void:
	good_button.focus_mode = Control.FOCUS_NONE
	neutral_button.focus_mode = Control.FOCUS_NONE
	bad_button.focus_mode = Control.FOCUS_NONE
	good_button.pressed.connect(func() -> void: choice_selected.emit("good", good_button.text))
	neutral_button.pressed.connect(func() -> void: choice_selected.emit("neutral", neutral_button.text))
	bad_button.pressed.connect(func() -> void: choice_selected.emit("bad", bad_button.text))
	history_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_set_choices_active(false)

func show_choices(choices: Dictionary) -> void:
	good_button.text = str(choices.get("good", ""))
	neutral_button.text = str(choices.get("neutral", ""))
	bad_button.text = str(choices.get("bad", ""))
	_set_choices_active(true)
	choice_countdown_bar.visible = true
	choice_countdown_bar.value = choice_countdown_bar.max_value
	call_deferred("_scroll_to_latest")

func hide_choices() -> void:
	_set_choices_active(false)
	choice_countdown_bar.visible = false

func show_prompt(_text_value: String) -> void:
	pass

func hide_prompt() -> void:
	pass

func clear_history() -> void:
	for child in history_list.get_children():
		child.queue_free()
	hide_prompt()
	hide_choices()

func append_history(line: String, speaker_type: String = "companion") -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)

	var companion_message := speaker_type != "player"
	var bubble_texture: Texture2D = CHARACTER_BUBBLE_TEXTURE if companion_message else PLAYER_BUBBLE_TEXTURE
	var bubble_display_size := _get_bubble_display_size(bubble_texture)
	if not companion_message:
		var left_spacer := Control.new()
		left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(left_spacer)

	var bubble := MarginContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bubble.custom_minimum_size = bubble_display_size
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.modulate = Color(1.0, 1.0, 1.0, 0.0)
	bubble.add_theme_constant_override("margin_left", BUBBLE_TEXT_HORIZONTAL_MARGIN)
	bubble.add_theme_constant_override("margin_top", BUBBLE_TEXT_VERTICAL_MARGIN)
	bubble.add_theme_constant_override("margin_right", BUBBLE_TEXT_HORIZONTAL_MARGIN)
	bubble.add_theme_constant_override("margin_bottom", BUBBLE_TEXT_VERTICAL_MARGIN)

	var bubble_background := TextureRect.new()
	bubble_background.name = "Background"
	bubble_background.texture = bubble_texture
	bubble_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bubble_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_background.show_behind_parent = true
	bubble_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bubble.add_child(bubble_background)

	var message_label := Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.text = line
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.clip_text = true
	message_label.add_theme_font_size_override("font_size", Config.DIALOGUE_BODY_FONT_SIZE)
	bubble.add_child(message_label)
	row.add_child(bubble)

	if companion_message:
		var right_spacer := Control.new()
		right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(right_spacer)

	history_list.add_child(row)
	UiThemeScaler.apply_to_tree(row)

	var tween := create_tween()
	tween.tween_property(bubble, "modulate:a", 1.0, 0.22)
	call_deferred("_scroll_to_latest")

func _scroll_to_latest() -> void:
	pass

func set_choice_timeout_progress(progress: float) -> void:
	if not choice_countdown_bar.visible:
		return
	choice_countdown_bar.value = clampf(progress, 0.0, 1.0) * choice_countdown_bar.max_value

func _set_choices_active(is_active: bool) -> void:
	var buttons: Array[Button] = [good_button, neutral_button, bad_button]
	for index in range(buttons.size()):
		var button := buttons[index]
		button.disabled = not is_active
		button.modulate = Color.WHITE if is_active else DISABLED_CHOICE_MODULATE
		choice_button_backgrounds[index].modulate = Color.WHITE if is_active else DISABLED_CHOICE_MODULATE
		if not is_active:
			button.text = INACTIVE_CHOICE_TEXTS[index]

func _get_bubble_display_size(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2(BUBBLE_DISPLAY_WIDTH, BUBBLE_DISPLAY_WIDTH)
	var texture_size := texture.get_size()
	if texture_size.x <= 0.0:
		return Vector2(BUBBLE_DISPLAY_WIDTH, BUBBLE_DISPLAY_WIDTH)
	return Vector2(BUBBLE_DISPLAY_WIDTH, BUBBLE_DISPLAY_WIDTH * (texture_size.y / texture_size.x))
