class_name InteractionModeToggle
extends Control

signal toggle_requested()

const PSYCHOLOGICAL_MODE := 0
const PHYSIOLOGICAL_MODE := 1
const TALK_CLICKED := preload("res://assets/art/ui/gameplay/btn_talk_clicked.png")
const TALK_ICON := preload("res://assets/art/ui/gameplay/mode_dialogue_icon.png")
const TALK_WARNING := preload("res://assets/art/ui/gameplay/btn_talk_warning.png")
const MUSIC_CLICKED := preload("res://assets/art/ui/gameplay/btn_music_clicked.png")
const MUSIC_ICON := preload("res://assets/art/ui/gameplay/mode_tuning_icon.png")
const MUSIC_WARNING := preload("res://assets/art/ui/gameplay/btn_music_warning.png")
const WARNING_PULSE_SPEED: float = 6.0
const WARNING_ALPHA_MIN: float = 0.25
const WARNING_ALPHA_MAX: float = 1.0
const WARNING_SCALE_MIN: float = 0.96
const WARNING_SCALE_MAX: float = 1.08
const SLIDE_DURATION: float = 0.28
const ACTIVE_POSITION := Vector2(6.0, 0.0)
const ACTIVE_SIZE := Vector2(120.0, 120.0)
const INACTIVE_POSITION := Vector2(19.0, 130.0)
const INACTIVE_SIZE := Vector2(94.0, 94.0)
const WARNING_BADGE_REGION := Rect2(118.0, 24.0, 46.0, 50.0)

@onready var toggle_button: Button = $ToggleButton
@onready var mode_label: Label = $ModeLabel
@onready var talk_button: TextureButton = $TalkButton
@onready var music_button: TextureButton = $MusicButton
@onready var talk_warning_badge: TextureRect = $TalkButton/WarningBadge
@onready var music_warning_badge: TextureRect = $MusicButton/WarningBadge

var _interaction_mode: int = PHYSIOLOGICAL_MODE
var _imbalance_warning_active: bool = false
var _lower_score_mode: int = -1
var _warning_pulse_time: float = 0.0
var _slide_tween: Tween


func _ready() -> void:
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	talk_button.pressed.connect(_on_toggle_button_pressed)
	music_button.pressed.connect(_on_toggle_button_pressed)
	talk_warning_badge.texture = _warning_badge_texture(TALK_WARNING)
	music_warning_badge.texture = _warning_badge_texture(MUSIC_WARNING)
	_sync_presentation(false)


func _process(delta: float) -> void:
	_warning_pulse_time += delta
	var pulse_ratio := (cos(_warning_pulse_time * WARNING_PULSE_SPEED) + 1.0) * 0.5
	var warning_alpha := lerpf(WARNING_ALPHA_MIN, WARNING_ALPHA_MAX, pulse_ratio)
	var warning_scale := lerpf(WARNING_SCALE_MIN, WARNING_SCALE_MAX, pulse_ratio)
	var warned_button: TextureButton = talk_button if _lower_score_mode == PSYCHOLOGICAL_MODE else music_button
	warned_button.modulate.a = warning_alpha
	warned_button.scale = Vector2.ONE * warning_scale


func set_interaction_mode(mode: int) -> void:
	if mode != PSYCHOLOGICAL_MODE and mode != PHYSIOLOGICAL_MODE:
		push_warning("InteractionModeToggle received unsupported mode: %d" % mode)
		return
	if _interaction_mode == mode:
		return
	_interaction_mode = mode
	if is_node_ready():
		_sync_presentation(true)


func get_interaction_mode() -> int:
	return _interaction_mode


func set_imbalance_warning(active: bool, lower_mode: int) -> void:
	if active and lower_mode != PSYCHOLOGICAL_MODE and lower_mode != PHYSIOLOGICAL_MODE:
		push_warning("InteractionModeToggle received unsupported lower mode: %d" % lower_mode)
		return
	var normalized_lower_mode := lower_mode if active else -1
	if _imbalance_warning_active == active and _lower_score_mode == normalized_lower_mode:
		return
	_imbalance_warning_active = active
	_lower_score_mode = normalized_lower_mode
	_warning_pulse_time = 0.0
	if is_node_ready():
		_sync_textures()
		_reset_warning_modulation()
	set_process(active)


func is_imbalance_warning_active() -> bool:
	return _imbalance_warning_active


func get_lower_score_mode() -> int:
	return _lower_score_mode


func _on_toggle_button_pressed() -> void:
	toggle_requested.emit()

func _sync_presentation(animate: bool) -> void:
	mode_label.text = "調音" if _interaction_mode == PHYSIOLOGICAL_MODE else "對話"
	toggle_button.tooltip_text = (
		"切換至對話模式（Q）"
		if _interaction_mode == PHYSIOLOGICAL_MODE
		else "切換至調音模式（Q）"
	)
	_sync_textures()
	_reset_warning_modulation()
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if animate:
		_slide_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween_button(music_button, _interaction_mode == PHYSIOLOGICAL_MODE)
		_tween_button(talk_button, _interaction_mode == PSYCHOLOGICAL_MODE)
	else:
		_place_button(music_button, _interaction_mode == PHYSIOLOGICAL_MODE)
		_place_button(talk_button, _interaction_mode == PSYCHOLOGICAL_MODE)
	set_process(_imbalance_warning_active)


func _sync_textures() -> void:
	_set_button_texture(talk_button, talk_warning_badge, PSYCHOLOGICAL_MODE, TALK_CLICKED, TALK_ICON, TALK_WARNING)
	_set_button_texture(music_button, music_warning_badge, PHYSIOLOGICAL_MODE, MUSIC_CLICKED, MUSIC_ICON, MUSIC_WARNING)


func _set_button_texture(button: TextureButton, badge: TextureRect, mode: int, active_art: Texture2D, inactive_art: Texture2D, warning_art: Texture2D) -> void:
	var warned: bool = _is_warning_for(mode)
	var active: bool = mode == _interaction_mode
	button.texture_normal = (warning_art if warned else active_art) if active else inactive_art
	button.texture_hover = (warning_art if warned else active_art) if active else inactive_art
	button.texture_pressed = button.texture_hover
	badge.visible = warned and not active
	button.tooltip_text = "調音模式" if mode == PHYSIOLOGICAL_MODE else "對話模式"


func _warning_badge_texture(art: Texture2D) -> AtlasTexture:
	var badge := AtlasTexture.new()
	badge.atlas = art
	badge.region = WARNING_BADGE_REGION
	return badge


func _tween_button(button: TextureButton, active: bool) -> void:
	var target_position: Vector2 = ACTIVE_POSITION if active else INACTIVE_POSITION
	var target_size: Vector2 = ACTIVE_SIZE if active else INACTIVE_SIZE
	_slide_tween.parallel().tween_property(button, "position", target_position, SLIDE_DURATION)
	_slide_tween.parallel().tween_property(button, "size", target_size, SLIDE_DURATION)
	_slide_tween.parallel().tween_property(button, "pivot_offset", target_size * 0.5, SLIDE_DURATION)


func _place_button(button: TextureButton, active: bool) -> void:
	button.position = ACTIVE_POSITION if active else INACTIVE_POSITION
	button.size = ACTIVE_SIZE if active else INACTIVE_SIZE
	button.pivot_offset = button.size * 0.5


func _reset_warning_modulation() -> void:
	for button in [talk_button, music_button]:
		button.modulate = Color.WHITE
		button.scale = Vector2.ONE

func _is_warning_for(mode: int) -> bool:
	return _imbalance_warning_active and _lower_score_mode == mode
