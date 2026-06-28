extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const ENDING_TEXTS_PATH := "res://assets/dialogue/endings.json"
const DEFAULT_ENDING_TEXTS := {
	Config.SUCCESS_ENDING: {
		"title": "整體興奮值滿",
		"body": "隨著一聲悠揚的嗚鳴，你的觸手撥動琴弦，在四弦上掃出漂亮的弧度。"
	},
	Config.PEAK_DEPLETION_FAILURE_ENDING: {
		"title": "整體興奮度歸零",
		"body": "糟糕的手法、不稱職的愛撫與言語，讓你與小提琴的氣氛降到了冰點。"
	},
	Config.PHYSICAL_IMBALANCE_FAILURE_ENDING: {
		"title": "生理滿但心理未到 threshold",
		"body": "激烈的愛撫一路失控，最後只剩下失衡後的空虛弦鳴。"
	},
	Config.EMOTIONAL_IMBALANCE_FAILURE_ENDING: {
		"title": "心理滿但生理未到 threshold",
		"body": "你們在尷尬與遺憾裡暫時停下，等待下一次更好的調音。"
	}
}

signal restart_pressed
signal back_to_title_pressed

@onready var result_label: Label = get_node_or_null(
	"BookPanel/OuterMargin/Layout/ResultSubtypeLabel"
)

@onready var body_label: Label = get_node_or_null(
	"BookPanel/OuterMargin/Layout/EndingBody"
)

@onready var restart_button: Button = get_node_or_null(
	"BookPanel/OuterMargin/Layout/RestartButtons/RestartButton"
)

@onready var back_to_title_button: Button = get_node_or_null(
	"BookPanel/OuterMargin/Layout/RestartButtons/BackToTitleButton"
)

var pending_result_type: String = ""
var ending_texts_by_type: Dictionary = {}

func _ready() -> void:
	ending_texts_by_type = _load_ending_texts()

	if restart_button == null:
		push_error("EndingScreen: RestartButton node not found.")
	else:
		restart_button.pressed.connect(
			func() -> void:
				restart_pressed.emit()
		)

	if back_to_title_button == null:
		push_error("EndingScreen: BackToTitleButton node not found.")
	else:
		back_to_title_button.pressed.connect(
			func() -> void:
				back_to_title_pressed.emit()
		)

	if not pending_result_type.is_empty():
		_apply_result(pending_result_type)

func set_result(result_type: String) -> void:
	pending_result_type = result_type

	# If this screen is already ready, update immediately.
	if is_node_ready():
		_apply_result(result_type)

func _apply_result(result_type: String) -> void:
	if result_label == null:
		push_error(
			"EndingScreen: ResultSubtypeLabel node not found at "
			+ "BookPanel/OuterMargin/Layout/ResultSubtypeLabel"
		)
		return

	if body_label == null:
		push_error(
			"EndingScreen: EndingBody node not found at "
			+ "BookPanel/OuterMargin/Layout/EndingBody"
		)
		return

	result_label.text = "Result: %s" % result_type
	var ending_entry_variant: Variant = ending_texts_by_type.get(result_type, {})
	if ending_entry_variant is Dictionary:
		var ending_entry: Dictionary = ending_entry_variant
		var ending_title: String = str(ending_entry.get("title", ""))
		var ending_body: String = str(ending_entry.get("body", ""))
		if not ending_title.is_empty() and not ending_body.is_empty():
			body_label.text = "%s\n\n%s" % [ending_title, ending_body]
			return

	body_label.text = "未知結局。\n\n尚未找到對應的 ending 文案。"

func _load_ending_texts() -> Dictionary:
	var file: FileAccess = FileAccess.open(ENDING_TEXTS_PATH, FileAccess.READ)
	if file == null:
		push_warning("EndingScreen: ending text file not found: %s" % ENDING_TEXTS_PATH)
		return DEFAULT_ENDING_TEXTS.duplicate(true)

	var parsed_variant: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed_variant is Dictionary):
		push_warning("EndingScreen: ending text JSON is invalid: %s" % ENDING_TEXTS_PATH)
		return DEFAULT_ENDING_TEXTS.duplicate(true)

	var parsed: Dictionary = parsed_variant
	var entries_variant: Variant = parsed.get("entries", {})
	if not (entries_variant is Dictionary):
		push_warning("EndingScreen: ending text entries must be a dictionary.")
		return DEFAULT_ENDING_TEXTS.duplicate(true)

	var merged_entries: Dictionary = DEFAULT_ENDING_TEXTS.duplicate(true)
	var loaded_entries: Dictionary = entries_variant
	merged_entries.merge(loaded_entries, true)
	return merged_entries
