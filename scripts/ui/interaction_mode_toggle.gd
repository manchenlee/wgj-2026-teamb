class_name InteractionModeToggle
extends Control

signal toggle_requested()

const PSYCHOLOGICAL_MODE := 0
const PHYSIOLOGICAL_MODE := 1
const TALK_CLICKED := preload("res://assets/art/ui/gameplay/btn_talk_clicked.png")
const TALK_UNCLICKED := preload("res://assets/art/ui/gameplay/btn_talk_unclicked.png")
const TALK_WARNING := preload("res://assets/art/ui/gameplay/btn_talk_warning.png")
const MUSIC_CLICKED := preload("res://assets/art/ui/gameplay/btn_music_clicked.png")
const MUSIC_UNCLICKED := preload("res://assets/art/ui/gameplay/btn_music_unclicked.png")
const MUSIC_WARNING := preload("res://assets/art/ui/gameplay/btn_music_warning.png")
const WARNING_PULSE_SPEED: float = 6.0
const WARNING_ALPHA_MIN: float = 0.25
const WARNING_ALPHA_MAX: float = 1.0
const WARNING_SCALE_MIN: float = 0.96
const WARNING_SCALE_MAX: float = 1.08

@onready var toggle_button: Button = $ToggleButton
@onready var mode_label: Label = $ModeLabel
@onready var talk_button: TextureButton = $TalkButton
@onready var music_button: TextureButton = $MusicButton

var _interaction_mode: int = PSYCHOLOGICAL_MODE
var _imbalance_warning_active: bool = false
var _lower_score_mode: int = -1
var _warning_pulse_time: float = 0.0


func _ready() -> void:
	toggle_button.pressed.connect(_on_toggle_button_pressed)
	talk_button.pressed.connect(_on_talk_button_pressed)
	music_button.pressed.connect(_on_music_button_pressed)
	talk_button.pivot_offset = talk_button.size * 0.5
	music_button.pivot_offset = music_button.size * 0.5
	_sync_presentation()
	set_process(false)


func _process(delta: float) -> void:
	_warning_pulse_time += delta
	var pulse_ratio := (cos(_warning_pulse_time * WARNING_PULSE_SPEED) + 1.0) * 0.5
	var warning_alpha := lerpf(WARNING_ALPHA_MIN, WARNING_ALPHA_MAX, pulse_ratio)
	var warning_scale := lerpf(WARNING_SCALE_MIN, WARNING_SCALE_MAX, pulse_ratio)
	var warning_scale_vector := Vector2.ONE * warning_scale
	if _lower_score_mode == PSYCHOLOGICAL_MODE:
		talk_button.modulate.a = warning_alpha
		talk_button.scale = warning_scale_vector
	elif _lower_score_mode == PHYSIOLOGICAL_MODE:
		music_button.modulate.a = warning_alpha
		music_button.scale = warning_scale_vector


func set_interaction_mode(mode: int) -> void:
	if mode != PSYCHOLOGICAL_MODE and mode != PHYSIOLOGICAL_MODE:
		push_warning("InteractionModeToggle received unsupported mode: %d" % mode)
		return
	_interaction_mode = mode
	_sync_presentation()


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
	set_process(active)
	_sync_presentation()


func is_imbalance_warning_active() -> bool:
	return _imbalance_warning_active


func get_lower_score_mode() -> int:
	return _lower_score_mode


func _on_toggle_button_pressed() -> void:
	toggle_requested.emit()

func _on_talk_button_pressed() -> void:
	if _interaction_mode != PSYCHOLOGICAL_MODE:
		toggle_requested.emit()

func _on_music_button_pressed() -> void:
	if _interaction_mode != PHYSIOLOGICAL_MODE:
		toggle_requested.emit()


func _sync_presentation() -> void:
	if mode_label != null:
		mode_label.text = "調音" if _interaction_mode == PHYSIOLOGICAL_MODE else "對話"
	if toggle_button != null:
		toggle_button.tooltip_text = (
			"切換至對話模式（Q）"
			if _interaction_mode == PHYSIOLOGICAL_MODE
			else "切換至調音模式（Q）"
		)
	if talk_button != null:
		talk_button.texture_normal = TALK_WARNING if _is_warning_for(PSYCHOLOGICAL_MODE) else (
			TALK_CLICKED if _interaction_mode == PSYCHOLOGICAL_MODE else TALK_UNCLICKED
		)
		talk_button.texture_hover = TALK_CLICKED
		talk_button.texture_pressed = TALK_CLICKED
		talk_button.modulate = Color.WHITE
		talk_button.scale = Vector2.ONE
	if music_button != null:
		music_button.texture_normal = MUSIC_WARNING if _is_warning_for(PHYSIOLOGICAL_MODE) else (
			MUSIC_CLICKED if _interaction_mode == PHYSIOLOGICAL_MODE else MUSIC_UNCLICKED
		)
		music_button.texture_hover = MUSIC_CLICKED
		music_button.texture_pressed = MUSIC_CLICKED
		music_button.modulate = Color.WHITE
		music_button.scale = Vector2.ONE

func _is_warning_for(mode: int) -> bool:
	return _imbalance_warning_active and _lower_score_mode == mode
