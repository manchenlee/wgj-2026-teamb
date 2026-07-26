extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const TITLE_SCENE := preload("res://scenes/screens/TitleScreen.tscn")
const WARNING_SCENE := preload("res://scenes/screens/WarningScreen.tscn")
const OPENING_SCENE := preload("res://scenes/screens/OpeningScreen.tscn")
const RULE_SCENE := preload("res://scenes/screens/RuleScreen.tscn")
const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")
const BGM_DEFAULT := preload("res://assets/audio/bgm/default.mp3")
const BGM_OVERALL_HIGH := preload("res://assets/audio/bgm/overall_high.mp3")
const BGM_OVERALL_LOW := preload("res://assets/audio/bgm/overall_low.mp3")
const BGM_ENDING := preload("res://assets/audio/bgm/ending.mp3")
const BGM_TARGET_VOLUME_DB := -6.0
const BGM_SILENT_VOLUME_DB := -40.0
const BGM_CROSSFADE_DURATION := 1.0
const SCREEN_TRANSITION_DURATION := 0.3
const SCREEN_TRANSITION_COLOR := Color(0, 0, 0, 1)

@onready var screen_container: Control = $ScreenContainer
@onready var debug_overlay = $DebugOverlay
@onready var bg_music: AudioStreamPlayer = $BgMusic
@onready var screen_transition_overlay: ColorRect = $ScreenTransitionOverlay

var current_screen: Control
var current_screen_id: String = ""
var current_safe_word: String = "紅色"
var bg_music_secondary: AudioStreamPlayer
var active_bgm_player: AudioStreamPlayer
var inactive_bgm_player: AudioStreamPlayer
var bgm_library := {}
var bgm_playback_positions := {}
var current_bgm_key: String = ""
var bgm_tween: Tween
var screen_transition_tween: Tween

func _ready() -> void:
	_setup_bgm_players()
	_setup_bgm_library()
	debug_overlay.stage_jump_requested.connect(_show_stage)
	debug_overlay.values_requested.connect(_apply_debug_values)
	debug_overlay.force_ending_requested.connect(_force_ending)
	debug_overlay.reset_run_requested.connect(_reset_run)
	debug_overlay.force_spawn_spot_requested.connect(_force_spawn_spot)
	debug_overlay.force_complete_spot_requested.connect(_force_complete_spot)
	debug_overlay.force_expire_spot_requested.connect(_force_expire_spot)
	if screen_transition_overlay != null:
		screen_transition_overlay.visible = false
		screen_transition_overlay.color = Color(
			SCREEN_TRANSITION_COLOR.r,
			SCREEN_TRANSITION_COLOR.g,
			SCREEN_TRANSITION_COLOR.b,
			0.0
		)
		screen_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_bgm("default", false)
	_show_title()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode == KEY_F1:
		debug_overlay.toggle()

func _show_title() -> void:
	current_screen_id = Config.SCREEN_TITLE
	var screen := TITLE_SCENE.instantiate()
	screen.start_pressed.connect(_show_warning)
	screen.skip_pressed.connect(_show_rule)
	screen.debug_requested.connect(func() -> void: debug_overlay.visible = true)
	_swap_screen(screen)
	_play_bgm("default", false)

func _show_warning() -> void:
	current_screen_id = Config.SCREEN_WARNING
	var screen := WARNING_SCENE.instantiate()
	screen.continue_pressed.connect(_show_opening)
	_swap_screen(screen)
	_play_bgm("default", false)

func _show_opening() -> void:
	current_screen_id = Config.SCREEN_OPENING
	var screen := OPENING_SCENE.instantiate()
	screen.continue_pressed.connect(_show_rule)
	screen.skip_pressed.connect(_show_rule)
	_swap_screen(screen)
	_play_bgm("default", false)

func _show_rule() -> void:
	current_screen_id = "rule"
	var screen := RULE_SCENE.instantiate()
	screen.continue_pressed.connect(_show_game)
	_swap_screen(screen)
	_play_bgm("default", false)

func _show_game(safe_word: String = "紅色") -> void:
	current_screen_id = Config.SCREEN_GAME
	var screen := GAME_SCENE.instantiate()
	var trimmed_safe_word := safe_word.strip_edges()
	current_safe_word = trimmed_safe_word if not trimmed_safe_word.is_empty() else current_safe_word
	if current_safe_word.is_empty():
		current_safe_word = Config.SAFE_WORD_DEFAULT
	screen.safe_word = current_safe_word
	screen.ending_requested.connect(_show_ending)
	screen.bgm_requested.connect(_on_game_bgm_requested)
	screen.debug_overlay = debug_overlay
	_swap_screen(screen)
	debug_overlay.sync_live_readout(screen.get_debug_state())
	_play_bgm("default", false)

func _show_ending(ending_type: String) -> void:
	current_screen_id = Config.SCREEN_ENDING
	var screen := ENDING_SCENE.instantiate()
	screen.set_result(ending_type)
	screen.restart_pressed.connect(func() -> void: _show_game(current_safe_word))
	screen.back_to_title_pressed.connect(_show_title)
	_swap_screen(screen)
	_play_bgm("ending", true)
	debug_overlay.sync_live_readout({
		"screen": "%s:%s" % [Config.SCREEN_ENDING, ending_type],
		"phase": "-",
		"physical": "-",
		"emotional": "-",
		"peak": "-",
		"spot": "-",
		"spot_incr": "-",
		"spot_bonus": "-",
		"spot_penalty": "-",
		"spot_net": "-"
	})

func _swap_screen(next_screen: Control) -> void:
	if current_screen == null or screen_transition_overlay == null:
		_swap_screen_immediately(next_screen)
		return

	if screen_transition_tween != null:
		screen_transition_tween.kill()
		screen_transition_tween = null

	screen_transition_overlay.visible = true
	screen_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	screen_transition_overlay.color = Color(
		SCREEN_TRANSITION_COLOR.r,
		SCREEN_TRANSITION_COLOR.g,
		SCREEN_TRANSITION_COLOR.b,
		0.0
	)

	screen_transition_tween = create_tween().set_trans(Tween.TRANS_SINE)
	screen_transition_tween.tween_property(
		screen_transition_overlay,
		"color:a",
		1.0,
		SCREEN_TRANSITION_DURATION
	)
	screen_transition_tween.tween_callback(func() -> void:
		_swap_screen_immediately(next_screen)
	)
	screen_transition_tween.tween_property(
		screen_transition_overlay,
		"color:a",
		0.0,
		SCREEN_TRANSITION_DURATION
	)
	screen_transition_tween.tween_callback(func() -> void:
		screen_transition_overlay.visible = false
		screen_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen_transition_tween = null
	)

func _swap_screen_immediately(next_screen: Control) -> void:
	if current_screen != null:
		current_screen.queue_free()
	current_screen = next_screen
	screen_container.add_child(current_screen)

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

func _force_spawn_spot() -> void:
	if current_screen_id == Config.SCREEN_GAME and current_screen.has_method("force_spawn_spot"):
		current_screen.force_spawn_spot()

func _force_complete_spot() -> void:
	if current_screen_id == Config.SCREEN_GAME and current_screen.has_method("force_complete_spot"):
		current_screen.force_complete_spot()

func _force_expire_spot() -> void:
	if current_screen_id == Config.SCREEN_GAME and current_screen.has_method("force_expire_spot"):
		current_screen.force_expire_spot()

func _on_game_bgm_requested(track_key: String, use_fade: bool) -> void:
	_play_bgm(track_key, use_fade)

func _setup_bgm_players() -> void:
	bg_music_secondary = AudioStreamPlayer.new()
	bg_music_secondary.name = "BgMusicSecondary"
	add_child(bg_music_secondary)
	move_child(bg_music_secondary, bg_music.get_index() + 1)
	_configure_bgm_player(bg_music)
	_configure_bgm_player(bg_music_secondary)
	active_bgm_player = bg_music
	inactive_bgm_player = bg_music_secondary

func _configure_bgm_player(player: AudioStreamPlayer) -> void:
	player.autoplay = false
	player.bus = "Master"
	player.volume_db = BGM_SILENT_VOLUME_DB

func _setup_bgm_library() -> void:
	bgm_library = {
		"default": _prepare_bgm_stream(BGM_DEFAULT, true),
		"overall_high": _prepare_bgm_stream(BGM_OVERALL_HIGH, true),
		"overall_low": _prepare_bgm_stream(BGM_OVERALL_LOW, true),
		"ending": _prepare_bgm_stream(BGM_ENDING, true)
	}
	bgm_playback_positions.clear()
	for track_key in bgm_library.keys():
		bgm_playback_positions[track_key] = 0.0

func _prepare_bgm_stream(stream: AudioStream, should_loop: bool) -> AudioStream:
	var prepared_stream := stream.duplicate(true)
	if prepared_stream is AudioStreamMP3:
		prepared_stream.loop = should_loop
	return prepared_stream

func _play_bgm(track_key: String, use_fade: bool) -> void:
	if not bgm_library.has(track_key):
		push_warning("Unknown BGM track requested: %s" % track_key)
		return
	if current_bgm_key == track_key and active_bgm_player != null and active_bgm_player.playing:
		return

	if bgm_tween != null:
		bgm_tween.kill()
		bgm_tween = null

	var outgoing_key := current_bgm_key
	var outgoing_player := active_bgm_player
	if outgoing_player != null and outgoing_player.playing and not outgoing_key.is_empty():
		bgm_playback_positions[outgoing_key] = outgoing_player.get_playback_position()

	var incoming_player := inactive_bgm_player if outgoing_player != null else bg_music
	var start_position := float(bgm_playback_positions.get(track_key, 0.0))
	incoming_player.stream = bgm_library[track_key]
	incoming_player.volume_db = BGM_SILENT_VOLUME_DB if use_fade else BGM_TARGET_VOLUME_DB
	incoming_player.play(start_position)

	current_bgm_key = track_key
	active_bgm_player = incoming_player
	inactive_bgm_player = outgoing_player if outgoing_player != null else bg_music_secondary

	if not use_fade or outgoing_player == null or not outgoing_player.playing:
		if outgoing_player != null and outgoing_player != incoming_player:
			outgoing_player.stop()
			outgoing_player.stream = null
			outgoing_player.volume_db = BGM_SILENT_VOLUME_DB
		active_bgm_player.volume_db = BGM_TARGET_VOLUME_DB
		return

	bgm_tween = create_tween()
	bgm_tween.set_parallel(true)
	bgm_tween.tween_property(active_bgm_player, "volume_db", BGM_TARGET_VOLUME_DB, BGM_CROSSFADE_DURATION)
	bgm_tween.tween_property(outgoing_player, "volume_db", BGM_SILENT_VOLUME_DB, BGM_CROSSFADE_DURATION)
	bgm_tween.chain().tween_callback(func() -> void:
		bgm_playback_positions[outgoing_key] = outgoing_player.get_playback_position()
		outgoing_player.stop()
		outgoing_player.stream = null
		outgoing_player.volume_db = BGM_SILENT_VOLUME_DB
	)
