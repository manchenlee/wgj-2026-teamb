extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const UiThemeScaler := preload("res://scripts/ui/ui_theme_scaler.gd")
const TITLE_SCENE := preload("res://scenes/screens/TitleScreen.tscn")
const WARNING_SCENE := preload("res://scenes/screens/WarningScreen.tscn")
const OPENING_SCENE := preload("res://scenes/screens/OpeningScreen.tscn")
const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")

@onready var screen_container: Control = $ScreenContainer
@onready var debug_overlay = $DebugOverlay

var current_screen: Control
var current_screen_id: String = ""

func _ready() -> void:
	debug_overlay.stage_jump_requested.connect(_show_stage)
	debug_overlay.values_requested.connect(_apply_debug_values)
	debug_overlay.force_ending_requested.connect(_force_ending)
	debug_overlay.reset_run_requested.connect(_reset_run)
	UiThemeScaler.apply_to_tree(debug_overlay)
	_show_title()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode == KEY_F1:
		debug_overlay.toggle()

func _show_title() -> void:
	current_screen_id = Config.SCREEN_TITLE
	var screen := TITLE_SCENE.instantiate()
	screen.start_pressed.connect(_show_warning)
	screen.debug_requested.connect(func() -> void: debug_overlay.visible = true)
	_swap_screen(screen)

func _show_warning() -> void:
	current_screen_id = Config.SCREEN_WARNING
	var screen := WARNING_SCENE.instantiate()
	screen.continue_pressed.connect(_show_opening)
	_swap_screen(screen)

func _show_opening() -> void:
	current_screen_id = Config.SCREEN_OPENING
	var screen := OPENING_SCENE.instantiate()
	screen.continue_pressed.connect(_show_game)
	_swap_screen(screen)

func _show_game() -> void:
	current_screen_id = Config.SCREEN_GAME
	var screen := GAME_SCENE.instantiate()
	screen.ending_requested.connect(_show_ending)
	screen.debug_overlay = debug_overlay
	_swap_screen(screen)
	debug_overlay.sync_live_readout(screen.get_debug_state())

func _show_ending(ending_type: String) -> void:
	current_screen_id = Config.SCREEN_ENDING
	var screen := ENDING_SCENE.instantiate()
	screen.set_result(ending_type)
	screen.restart_pressed.connect(_show_game)
	screen.back_to_title_pressed.connect(_show_title)
	_swap_screen(screen)
	debug_overlay.sync_live_readout({
		"screen": "%s:%s" % [Config.SCREEN_ENDING, ending_type],
		"physical": "-",
		"emotional": "-",
		"peak": "-",
		"combo": "-",
		"round": "-",
		"sequence": "-"
	})

func _swap_screen(next_screen: Control) -> void:
	if current_screen != null:
		current_screen.queue_free()
	current_screen = next_screen
	screen_container.add_child(current_screen)
	UiThemeScaler.apply_to_tree(current_screen)

func _show_stage(target: String) -> void:
	match target:
		Config.SCREEN_TITLE:
			_show_title()
		Config.SCREEN_WARNING:
			_show_warning()
		Config.SCREEN_OPENING:
			_show_opening()
		Config.SCREEN_GAME:
			_show_game()

func _apply_debug_values(value: float) -> void:
	if current_screen_id == Config.SCREEN_GAME and current_screen.has_method("apply_debug_values"):
		current_screen.apply_debug_values(value)

func _force_ending(ending_type: String) -> void:
	if current_screen_id == Config.SCREEN_GAME and current_screen.has_method("force_ending"):
		current_screen.force_ending(ending_type)
	else:
		_show_ending(ending_type)

func _reset_run() -> void:
	if current_screen_id == Config.SCREEN_GAME and current_screen.has_method("reset_run"):
		current_screen.reset_run()
