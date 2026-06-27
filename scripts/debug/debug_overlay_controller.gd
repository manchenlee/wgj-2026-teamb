class_name DebugOverlayController
extends CanvasLayer

const Config := preload("res://scripts/gameplay/GameConfig.gd")

signal stage_jump_requested(stage: String)
signal values_requested(value: float)
signal force_ending_requested(ending_type: String)
signal reset_run_requested()
signal force_spawn_spot_requested()
signal force_complete_spot_requested()
signal force_expire_spot_requested()

@onready var panel: PanelContainer = $RootPanel
@onready var live_label: Label = $RootPanel/MarginContainer/VBoxContainer/LiveReadout
@onready var spot_telemetry_label: Label = $RootPanel/MarginContainer/VBoxContainer/SpotTelemetryLabel

func _ready() -> void:
	visible = false
	_bind_stage_button("StageButtons/TitleButton", Config.SCREEN_TITLE)
	_bind_stage_button("StageButtons/WarningButton", Config.SCREEN_WARNING)
	_bind_stage_button("StageButtons/OpeningButton", Config.SCREEN_OPENING)
	_bind_stage_button("StageButtons/GameButton", Config.SCREEN_GAME)
	_bind_stage_button("StageButtons/SuccessButton", Config.SUCCESS_ENDING)
	_bind_stage_button("StageButtons/PhysicalFailButton", Config.PHYSICAL_FAILURE_ENDING)
	_bind_stage_button("StageButtons/EmotionalFailButton", Config.EMOTIONAL_FAILURE_ENDING)

	_bind_value_button("ValueButtons/ZeroButton", 0.0)
	_bind_value_button("ValueButtons/FiftyButton", 50.0)
	_bind_value_button("ValueButtons/HundredButton", 100.0)

	$RootPanel/MarginContainer/VBoxContainer/ActionButtons/ForceSuccessButton.pressed.connect(
		func() -> void: force_ending_requested.emit(Config.SUCCESS_ENDING)
	)
	$RootPanel/MarginContainer/VBoxContainer/ActionButtons/ForcePhysicalFailButton.pressed.connect(
		func() -> void: force_ending_requested.emit(Config.PHYSICAL_FAILURE_ENDING)
	)
	$RootPanel/MarginContainer/VBoxContainer/ActionButtons/ForceEmotionalFailButton.pressed.connect(
		func() -> void: force_ending_requested.emit(Config.EMOTIONAL_FAILURE_ENDING)
	)
	$RootPanel/MarginContainer/VBoxContainer/ActionButtons/ResetRunButton.pressed.connect(
		func() -> void: reset_run_requested.emit()
	)
	$RootPanel/MarginContainer/VBoxContainer/SpotButtons/ForceSpawnSpotButton.pressed.connect(
		func() -> void: force_spawn_spot_requested.emit()
	)
	$RootPanel/MarginContainer/VBoxContainer/SpotButtons/ForceCompleteSpotButton.pressed.connect(
		func() -> void: force_complete_spot_requested.emit()
	)
	$RootPanel/MarginContainer/VBoxContainer/SpotButtons/ForceExpireSpotButton.pressed.connect(
		func() -> void: force_expire_spot_requested.emit()
	)


func toggle() -> void:
	visible = not visible


func sync_live_readout(state: Dictionary) -> void:
	live_label.text = (
		"Screen: %s | Phase: %s | Phys: %s | Emot: %s | Peak: %s | Spot: %s" % [
			str(state.get("screen", "-")),
			str(state.get("phase", "-")),
			str(state.get("physical", "-")),
			str(state.get("emotional", "-")),
			str(state.get("peak", "-")),
			str(state.get("spot", "-"))
		]
	)
	spot_telemetry_label.text = (
		"Spot telemetry — incr: +%s  bonus: +%s  penalty: -%s  net: %s" % [
			str(state.get("spot_incr", "-")),
			str(state.get("spot_bonus", "-")),
			str(state.get("spot_penalty", "-")),
			str(state.get("spot_net", "-"))
		]
	)


func _bind_stage_button(path: String, stage: String) -> void:
	var button: Button = $RootPanel/MarginContainer/VBoxContainer.get_node(path)
	button.pressed.connect(func() -> void:
		if stage == Config.SUCCESS_ENDING or stage == Config.PHYSICAL_FAILURE_ENDING \
				or stage == Config.EMOTIONAL_FAILURE_ENDING:
			force_ending_requested.emit(stage)
		else:
			stage_jump_requested.emit(stage)
	)


func _bind_value_button(path: String, value: float) -> void:
	var button: Button = $RootPanel/MarginContainer/VBoxContainer.get_node(path)
	button.pressed.connect(func() -> void: values_requested.emit(value))
