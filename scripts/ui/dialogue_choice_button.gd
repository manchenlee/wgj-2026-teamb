extends TextureButton

const NORMAL_TEXT_COLOR := Color.WHITE
const HOVER_TEXT_COLOR := Color.BLACK

@onready var choice_label: Label = $Label


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_update_label_color()


func _on_mouse_entered() -> void:
	_update_label_color()


func _on_mouse_exited() -> void:
	_update_label_color()


func _update_label_color() -> void:
	choice_label.add_theme_color_override(
		"font_color", HOVER_TEXT_COLOR if is_hovered() and not disabled else NORMAL_TEXT_COLOR
	)
