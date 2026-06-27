extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")

signal restart_pressed

@onready var result_label: Label = get_node_or_null(
	"MarginContainer/VBoxContainer/ResultSubtypeLabel"
)

@onready var body_label: Label = get_node_or_null(
	"MarginContainer/VBoxContainer/EndingBody"
)

@onready var restart_button: Button = get_node_or_null(
	"MarginContainer/VBoxContainer/RestartButton"
)

var pending_result_type: String = ""

func _ready() -> void:
	if restart_button == null:
		push_error("EndingScreen: RestartButton node not found.")
	else:
		restart_button.pressed.connect(
			func() -> void:
				restart_pressed.emit()
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
			+ "MarginContainer/VBoxContainer/ResultSubtypeLabel"
		)
		return

	if body_label == null:
		push_error(
			"EndingScreen: EndingBody node not found at "
			+ "MarginContainer/VBoxContainer/EndingBody"
		)
		return

	result_label.text = "Result: %s" % result_type

	match result_type:
		Config.SUCCESS_ENDING:
			body_label.text = "SUCCESS\nPeak Arousal reached 100."

		Config.PHYSICAL_FAILURE_ENDING:
			body_label.text = "FAILURE\nPhysical Arousal reached 0."

		Config.EMOTIONAL_FAILURE_ENDING:
			body_label.text = "FAILURE\nEmotional Arousal reached 0."

		_:
			body_label.text = "FAILURE\nUnknown ending reason."
