class_name StatusHUD
extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")

const HUD_BACKGROUND_COLOR := Color("290315")
const HEART_LABEL_FONT_SIZE := 24
const CHOICE_FONT_SIZE := 24
const CHOICE_LABEL_MARGIN := Vector2(28.0, 22.0)
const CHOICE_LABEL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const CHOICE_LABEL_OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const CHOICE_LABEL_OUTLINE_SIZE := 0
const HEART_SCALE := 0.8
const STAFF_SCALE := 0.8
const NOTE_SCALE := 0.3
const BAR_HEIGHT_SCALE := 0.3
const STAFF_CENTER_FROM_LEFT_RATIO := 0.34
const NOTE_CENTER_FROM_LEFT_RATIO := 0.6
const NOTE_CENTER_FROM_TOP_RATIO := 0.5

@export var bottom_hud_height: float = 184.0:
	set(value):
		bottom_hud_height = maxf(value, 146.0)
		if is_node_ready():
			_apply_layout()

@export var meter_position: Vector2 = Vector2(16.0, 8.0):
	set(value):
		meter_position = value
		if is_node_ready():
			_apply_layout()

@export var maximum_bar_width: float = 610.0:
	set(value):
		maximum_bar_width = maxf(value, 0.0)
		if is_node_ready():
			_apply_layout()

@export var heart_label_offset: Vector2 = Vector2(0.0, -2.0):
	set(value):
		heart_label_offset = value
		if is_node_ready():
			_apply_layout()

@export var choice_area_position: Vector2 = Vector2(804.0, 18.0):
	set(value):
		choice_area_position = value
		if is_node_ready():
			_apply_layout()

@export var choice_gap: float = 24.0:
	set(value):
		choice_gap = maxf(value, 0.0)
		if is_node_ready():
			_apply_layout()

@export var staff_position_offset: Vector2 = Vector2(34.0, 41.0):
	set(value):
		staff_position_offset = value
		if is_node_ready():
			_apply_layout()

@export var note_center_offset: Vector2 = Vector2(54.0, -6.0):
	set(value):
		note_center_offset = value
		if is_node_ready():
			_apply_layout()

@export var bar_left_offset: Vector2 = Vector2(24.0, 0.0):
	set(value):
		bar_left_offset = value
		if is_node_ready():
			_apply_layout()

@export var meter_vertical_nudge: float = 0.0:
	set(value):
		meter_vertical_nudge = value
		if is_node_ready():
			_apply_layout()

@onready var hud_background: ColorRect = $HUDBackground
@onready var arousal_meter: Control = $ArousalMeter
@onready var heart_icon: TextureRect = $ArousalMeter/HeartIcon
@onready var heart_value_label: Label = $ArousalMeter/HeartValueLabel
@onready var musical_staff: TextureRect = $ArousalMeter/MusicalStaff
@onready var arousal_fill_bar: TextureRect = $ArousalMeter/ArousalFillBar
@onready var treble_clef: TextureRect = $ArousalMeter/TrebleClef
@onready var choice_area: Control = $ChoiceArea
@onready var choice_area_debug_tint: ColorRect = $ChoiceArea/DebugRegionTint
@onready var choice_button_1: TextureButton = $ChoiceArea/ChoiceButton1
@onready var choice_button_2: TextureButton = $ChoiceArea/ChoiceButton2
@onready var choice_label_1: Label = $ChoiceArea/ChoiceButton1/Label
@onready var choice_label_2: Label = $ChoiceArea/ChoiceButton2/Label

var _peak_value: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_background.color = HUD_BACKGROUND_COLOR
	heart_value_label.add_theme_font_size_override("font_size", HEART_LABEL_FONT_SIZE)
	heart_value_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.86, 1.0))
	for label in [choice_label_1, choice_label_2]:
		label.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
		label.add_theme_color_override("font_color", CHOICE_LABEL_COLOR)
		label.add_theme_color_override("font_outline_color", CHOICE_LABEL_OUTLINE_COLOR)
		label.add_theme_constant_override("outline_size", CHOICE_LABEL_OUTLINE_SIZE)
	choice_area.mouse_filter = Control.MOUSE_FILTER_PASS
	choice_button_1.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	choice_button_2.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_layout()
	_apply_meter_fill(_peak_value)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_layout()

func update_values(_physical: float, _emotional: float, peak: float) -> void:
	_peak_value = Config.clamp_value(peak)
	heart_value_label.text = str(int(round(_peak_value)))
	_apply_meter_fill(_peak_value)

func update_combo(_combo: int) -> void:
	pass

func _apply_layout() -> void:
	size.y = bottom_hud_height
	custom_minimum_size.y = bottom_hud_height

	hud_background.position = Vector2.ZERO
	hud_background.size = size

	var heart_size := _get_texture_size(heart_icon.texture)
	var staff_size := _get_texture_size(musical_staff.texture)
	var note_size := _get_texture_size(treble_clef.texture)
	var choice_bubble_size := _get_choice_bubble_size()
	var scaled_heart_size := heart_size * HEART_SCALE
	var scaled_staff_size := staff_size * STAFF_SCALE

	arousal_meter.position = meter_position
	arousal_meter.size = Vector2(
		maxf(choice_area_position.x - meter_position.x, 0.0),
		bottom_hud_height
	)

	heart_icon.z_index = 2
	heart_icon.position = Vector2.ZERO
	heart_icon.scale = Vector2.ONE * HEART_SCALE
	heart_icon.size = heart_size

	heart_value_label.z_index = 3
	heart_value_label.position = heart_icon.position + heart_label_offset
	heart_value_label.size = scaled_heart_size

	var base_staff_position := Vector2(
		scaled_heart_size.x * STAFF_CENTER_FROM_LEFT_RATIO,
		staff_position_offset.y
	) + Vector2(staff_position_offset.x, 0.0)
	musical_staff.z_index = 1
	musical_staff.position = base_staff_position
	musical_staff.size = staff_size
	musical_staff.scale = Vector2.ONE * STAFF_SCALE

	arousal_fill_bar.z_index = 1
	arousal_fill_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arousal_fill_bar.stretch_mode = TextureRect.STRETCH_SCALE
	arousal_fill_bar.scale = Vector2(1.0, BAR_HEIGHT_SCALE)

	treble_clef.z_index = 2
	treble_clef.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	treble_clef.size = note_size
	treble_clef.scale = Vector2.ONE * NOTE_SCALE

	choice_area.position = choice_area_position
	choice_area.size = Vector2(
		(choice_bubble_size.x * 2.0) + choice_gap,
		choice_bubble_size.y
	)
	choice_area_debug_tint.position = Vector2.ZERO
	choice_area_debug_tint.size = choice_area.size

	choice_button_1.position = Vector2.ZERO
	choice_button_1.size = choice_bubble_size
	choice_button_1.custom_minimum_size = choice_bubble_size
	choice_button_2.position = Vector2(choice_bubble_size.x + choice_gap, 0.0)
	choice_button_2.size = choice_bubble_size
	choice_button_2.custom_minimum_size = choice_bubble_size

	var label_size := choice_bubble_size - (CHOICE_LABEL_MARGIN * 2.0)
	choice_label_1.position = CHOICE_LABEL_MARGIN
	choice_label_1.size = label_size
	choice_label_2.position = CHOICE_LABEL_MARGIN
	choice_label_2.size = label_size

	heart_value_label.add_theme_font_size_override("font_size", HEART_LABEL_FONT_SIZE)
	_apply_meter_fill(_peak_value)
	_center_meter_group_vertically()

func _apply_meter_fill(peak: float) -> void:
	if not is_node_ready():
		return
	var bar_texture_size := _get_texture_size(arousal_fill_bar.texture)
	var scaled_heart_size := _get_texture_size(heart_icon.texture) * HEART_SCALE
	var scaled_staff_size := _get_texture_size(musical_staff.texture) * STAFF_SCALE
	var scaled_note_size := _get_texture_size(treble_clef.texture) * NOTE_SCALE
	var fill_ratio := Config.clamp_value(peak) / Config.MAX_VALUE
	var bar_left := Vector2(
		heart_icon.position.x + (scaled_heart_size.x * 0.5) + bar_left_offset.x,
		musical_staff.position.y + (scaled_staff_size.y * 0.5) - ((bar_texture_size.y * BAR_HEIGHT_SCALE) * 0.5) + bar_left_offset.y
	)
	var fixed_bar_left_x := bar_left.x
	var note_center_x := fixed_bar_left_x + (maximum_bar_width * fill_ratio)
	var note_center_y := heart_icon.position.y + (scaled_heart_size.y * 0.5) + note_center_offset.y
	treble_clef.position = Vector2(
		note_center_x - (scaled_note_size.x * NOTE_CENTER_FROM_LEFT_RATIO),
		note_center_y - (scaled_note_size.y * NOTE_CENTER_FROM_TOP_RATIO)
	)
	arousal_fill_bar.position = bar_left
	var note_horizontal_center := treble_clef.position.x + (scaled_note_size.x * NOTE_CENTER_FROM_LEFT_RATIO)
	arousal_fill_bar.size = Vector2(
		maxf(note_horizontal_center - fixed_bar_left_x, 0.0),
		bar_texture_size.y
	)

func _center_meter_group_vertically() -> void:
	var top := heart_icon.position.y
	top = minf(top, musical_staff.position.y)
	top = minf(top, arousal_fill_bar.position.y)
	top = minf(top, treble_clef.position.y)

	var bottom := heart_icon.position.y + (_get_texture_size(heart_icon.texture).y * HEART_SCALE)
	bottom = maxf(bottom, musical_staff.position.y + (_get_texture_size(musical_staff.texture).y * STAFF_SCALE))
	bottom = maxf(bottom, arousal_fill_bar.position.y + (_get_texture_size(arousal_fill_bar.texture).y * BAR_HEIGHT_SCALE))
	bottom = maxf(bottom, treble_clef.position.y + (_get_texture_size(treble_clef.texture).y * NOTE_SCALE))
	var group_height := bottom - top
	var target_top := ((bottom_hud_height - group_height) * 0.5) + meter_vertical_nudge
	var delta_y := target_top - top

	heart_icon.position.y += delta_y
	heart_value_label.position.y += delta_y
	musical_staff.position.y += delta_y
	arousal_fill_bar.position.y += delta_y
	treble_clef.position.y += delta_y

func _get_choice_bubble_size() -> Vector2:
	return _get_texture_size(choice_button_1.texture_normal)

func _get_texture_size(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(texture.get_width(), texture.get_height())
