class_name UiThemeScaler
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const FONT_SIZE_KEYS := [
	"font_size",
	"normal_font_size",
	"bold_font_size",
	"italics_font_size",
	"mono_font_size"
]
const SCALE_META_KEY := "_ui_font_scale_applied"

static func apply_to_tree(root: Node) -> void:
	if root == null:
		return

	if root is Control:
		_apply_to_control(root)

	for child in root.get_children():
		apply_to_tree(child)

static func _apply_to_control(control: Control) -> void:
	if control.has_meta(SCALE_META_KEY):
		return

	for key in FONT_SIZE_KEYS:
		if control.has_theme_font_size(key):
			var current_size := control.get_theme_font_size(key)
			if current_size > 0:
				control.add_theme_font_size_override(key, int(round(current_size * Config.UI_FONT_SCALE)))

	control.set_meta(SCALE_META_KEY, true)
