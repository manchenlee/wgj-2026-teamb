class_name DialoguePanel
extends PanelContainer

signal choice_selected(choice_quality: String, choice_text: String)

const HISTORY_BUBBLE_MAX_WIDTH := 232.0
const HISTORY_BUBBLE_MIN_WIDTH := 180.0
const SCROLL_BOTTOM_THRESHOLD := 24.0

@onready var history_scroll: ScrollContainer = $MarginContainer/VBoxContainer/ScrollableChatHistory
@onready var history_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollableChatHistory/ChatHistoryList
@onready var jump_to_latest_button: Button = $MarginContainer/VBoxContainer/ScrollableChatHistory/JumpToLatestButton
@onready var choice_countdown_bar: ProgressBar = $MarginContainer/VBoxContainer/ChoiceCountdownBar
@onready var prompt_panel: PanelContainer = $MarginContainer/VBoxContainer/PromptPanel
@onready var prompt_label: Label = $MarginContainer/VBoxContainer/PromptPanel/PromptLabel
@onready var choice_buttons: VBoxContainer = $MarginContainer/VBoxContainer/ChoiceButtons
@onready var good_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/GoodButton
@onready var neutral_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/NeutralButton
@onready var bad_button: Button = $MarginContainer/VBoxContainer/ChoiceButtons/BadButton

var _pending_unread_messages: int = 0

func _ready() -> void:
	good_button.focus_mode = Control.FOCUS_NONE
	neutral_button.focus_mode = Control.FOCUS_NONE
	bad_button.focus_mode = Control.FOCUS_NONE
	jump_to_latest_button.focus_mode = Control.FOCUS_NONE
	good_button.pressed.connect(func() -> void: choice_selected.emit("good", good_button.text))
	neutral_button.pressed.connect(func() -> void: choice_selected.emit("neutral", neutral_button.text))
	bad_button.pressed.connect(func() -> void: choice_selected.emit("bad", bad_button.text))
	jump_to_latest_button.pressed.connect(_on_jump_to_latest_pressed)
	history_scroll.get_v_scroll_bar().value_changed.connect(_on_history_scrolled)
	resized.connect(_on_panel_resized)
	_on_panel_resized()

func show_choices(choices: Dictionary) -> void:
	good_button.text = str(choices.get("good", ""))
	neutral_button.text = str(choices.get("neutral", ""))
	bad_button.text = str(choices.get("bad", ""))
	choice_buttons.visible = true
	choice_countdown_bar.visible = true
	choice_countdown_bar.value = choice_countdown_bar.max_value

func hide_choices() -> void:
	choice_buttons.visible = false
	choice_countdown_bar.visible = false

func show_prompt(text_value: String) -> void:
	prompt_label.text = text_value
	prompt_panel.visible = true

func hide_prompt() -> void:
	prompt_panel.visible = false

func clear_history() -> void:
	for child in history_list.get_children():
		child.queue_free()
	_pending_unread_messages = 0
	_update_jump_to_latest_button()
	hide_prompt()
	hide_choices()

func append_history(line: String, speaker_type: String = "companion") -> void:
	var should_follow_latest := _is_near_latest()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)

	var companion_message := speaker_type != "player"
	if not companion_message:
		var left_spacer := Control.new()
		left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(left_spacer)

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bubble.custom_minimum_size = Vector2(_get_bubble_width(), 92.0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.modulate = Color(1.0, 1.0, 1.0, 0.0)
	bubble.scale = Vector2(0.94, 0.94)

	var bubble_style := StyleBoxFlat.new()
	bubble_style.bg_color = Color(0.15, 0.15, 0.17, 0.92) if companion_message else Color(0.24, 0.24, 0.3, 0.96)
	bubble_style.corner_radius_top_left = 14
	bubble_style.corner_radius_top_right = 14
	bubble_style.corner_radius_bottom_left = 14
	bubble_style.corner_radius_bottom_right = 14
	bubble_style.content_margin_left = 12.0
	bubble_style.content_margin_top = 10.0
	bubble_style.content_margin_right = 12.0
	bubble_style.content_margin_bottom = 10.0
	bubble.set("theme_override_styles/panel", bubble_style)

	var message_label := Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.text = line
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.custom_minimum_size = Vector2(_get_bubble_width(), 0.0)
	bubble.add_child(message_label)
	row.add_child(bubble)

	if companion_message:
		var right_spacer := Control.new()
		right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(right_spacer)

	history_list.add_child(row)
	UiThemeScaler.apply_to_tree(row)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(bubble, "modulate:a", 1.0, 0.22)
	tween.tween_property(bubble, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if should_follow_latest:
		call_deferred("_scroll_to_latest")
	else:
		_pending_unread_messages += 1
		_update_jump_to_latest_button()

func _scroll_to_latest() -> void:
	history_scroll.scroll_vertical = int(history_scroll.get_v_scroll_bar().max_value)
	_pending_unread_messages = 0
	_update_jump_to_latest_button()

func set_choice_timeout_progress(progress: float) -> void:
	if not choice_countdown_bar.visible:
		return
	choice_countdown_bar.value = clampf(progress, 0.0, 1.0) * choice_countdown_bar.max_value

func _on_jump_to_latest_pressed() -> void:
	_scroll_to_latest()

func _on_history_scrolled(_value: float) -> void:
	if _is_near_latest():
		_pending_unread_messages = 0
	_update_jump_to_latest_button()

func _on_panel_resized() -> void:
	var bubble_width := _get_bubble_width()
	for row in history_list.get_children():
		if row.get_child_count() == 0:
			continue
		for child in row.get_children():
			if child is PanelContainer:
				child.custom_minimum_size.x = bubble_width
				if child.get_child_count() > 0 and child.get_child(0) is Label:
					child.get_child(0).custom_minimum_size.x = bubble_width

func _update_jump_to_latest_button() -> void:
	var should_show := _pending_unread_messages > 0 and not _is_near_latest()
	jump_to_latest_button.visible = should_show
	if should_show:
		jump_to_latest_button.text = "New message (%d)" % _pending_unread_messages

func _is_near_latest() -> bool:
	var scrollbar := history_scroll.get_v_scroll_bar()
	return scrollbar.max_value - scrollbar.value <= SCROLL_BOTTOM_THRESHOLD

func _get_bubble_width() -> float:
	return clampf(size.x - 88.0, HISTORY_BUBBLE_MIN_WIDTH, HISTORY_BUBBLE_MAX_WIDTH)
