extends Control

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const CursorHitAreaClass := preload("res://scripts/gameplay/cursor_hit_area.gd")
const TITLE_SCENE := preload("res://scenes/screens/TitleScreen.tscn")
const WARNING_SCENE := preload("res://scenes/screens/WarningScreen.tscn")
const OPENING_SCENE := preload("res://scenes/screens/OpeningScreen.tscn")
const SAFE_WORD_SCENE := preload("res://scenes/screens/SafeWordScreen.tscn")
const GAME_SCENE := preload("res://scenes/screens/GameScreen.tscn")
const ENDING_SCENE := preload("res://scenes/screens/EndingScreen.tscn")
const MidiPitchTimelineClass := preload("res://scripts/gameplay/midi_pitch_timeline.gd")
const BGM_DEFAULT := preload("res://assets/audio/bgm/default.mp3")
const BGM_GAMEPLAY := preload("res://assets/audio/bgm/piano_gameplay.ogg")
const BGM_ENDING := preload("res://assets/audio/bgm/ending.mp3")
const TENTACLE_CURSOR := preload("res://assets/art/ui/gameplay/img_tentacle.png")
# Keep the native cursor at its original design size; note hit areas are tuned separately.
const TENTACLE_CURSOR_SIZE := Vector2i(
	int(CursorHitAreaClass.DIAMETER), int(CursorHitAreaClass.DIAMETER)
)
const MAX_CURSOR_SIZE := 256
const BGM_TARGET_VOLUME_DB := -6.0
const BGM_SILENT_VOLUME_DB := -40.0
const BGM_CROSSFADE_DURATION := 1.0
const SCREEN_TRANSITION_DURATION := 0.3
const OPENING_TO_GAME_FADE_DURATION := 0.8
const ENDING_FADE_IN_DURATION := 0.55
const SCREEN_TRANSITION_COLOR := Color(0, 0, 0, 1)

@export var midi_rest_default_open_string_pitch: int = 69

@onready var screen_container: Control = $ScreenContainer
@onready var debug_overlay = $DebugOverlay
@onready var bg_music: AudioStreamPlayer = $BgMusic
@onready var screen_transition_overlay: ColorRect = $ScreenTransitionOverlay
@onready var pause_menu: PauseMenu = $PauseLayer/PauseMenu

var current_screen: Control
var current_screen_id: String = ""
var current_safe_word: String = Config.SAFE_WORD_DEFAULT
var safe_word_completed := false
var bg_music_secondary: AudioStreamPlayer
var active_bgm_player: AudioStreamPlayer
var inactive_bgm_player: AudioStreamPlayer
var bgm_library := {}
var bgm_playback_positions := {}
var current_bgm_key: String = ""
var bgm_tween: Tween
var screen_transition_tween: Tween
var violin_timeline: MidiPitchTimeline = MidiPitchTimelineClass.new()
var _current_cursor_size := Vector2i.ZERO

func _ready() -> void:
	get_window().size_changed.connect(_update_mouse_cursor)
	get_window().dpi_changed.connect(_update_mouse_cursor)
	_update_mouse_cursor()
	_setup_bgm_players()
	_setup_bgm_library()
	violin_timeline.default_open_string_pitch = midi_rest_default_open_string_pitch
	if not violin_timeline.load_from_file("res://data/violin_timeline.json"):
		push_warning("Violin MIDI timeline could not be loaded.")
	debug_overlay.stage_jump_requested.connect(_show_stage)
	debug_overlay.values_requested.connect(_apply_debug_values)
	debug_overlay.force_ending_requested.connect(_force_ending)
	debug_overlay.reset_run_requested.connect(_reset_run)
	debug_overlay.force_spawn_spot_requested.connect(_force_spawn_spot)
	debug_overlay.force_complete_spot_requested.connect(_force_complete_spot)
	debug_overlay.force_expire_spot_requested.connect(_force_expire_spot)
	pause_menu.restart_requested.connect(_restart_game_from_pause)
	pause_menu.exit_requested.connect(get_tree().quit)
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

func _show_title(fade_from_ending: bool = false) -> void:
	safe_word_completed = false
	current_safe_word = Config.SAFE_WORD_DEFAULT
	current_screen_id = Config.SCREEN_TITLE
	var screen := TITLE_SCENE.instantiate()
	screen.start_pressed.connect(_show_warning)
	screen.skip_pressed.connect(_show_safe_word)
	screen.debug_requested.connect(func() -> void: debug_overlay.visible = true)
	_swap_screen(screen, fade_from_ending)
	if fade_from_ending:
		bgm_playback_positions["default"] = 0.0
	_play_bgm("default", fade_from_ending)

func _show_warning() -> void:
	current_screen_id = Config.SCREEN_WARNING
	var screen := WARNING_SCENE.instantiate()
	screen.continue_pressed.connect(_show_opening)
	_swap_screen(screen)
	_play_bgm("default", false)

func _show_opening() -> void:
	safe_word_completed = false
	current_safe_word = Config.SAFE_WORD_DEFAULT
	current_screen_id = Config.SCREEN_OPENING
	var screen := OPENING_SCENE.instantiate()
	screen.safe_word_completed = safe_word_completed
	screen.continue_pressed.connect(_on_opening_skip)
	screen.skip_pressed.connect(_on_opening_skip)
	screen.safe_word_requested.connect(_show_opening_safe_word)
	screen.game_requested.connect(func() -> void: _show_game(current_safe_word, true))
	_swap_screen(screen)
	_play_bgm("default", false)

func _show_opening_safe_word() -> void:
	if current_screen_id != Config.SCREEN_OPENING:
		return
	current_screen_id = Config.SCREEN_SAFE_WORD
	var screen := SAFE_WORD_SCENE.instantiate()
	screen.continue_pressed.connect(_resume_opening_after_safe_word)
	_fade_opening_to_screen(screen)

func _resume_opening_after_safe_word(safe_word: String) -> void:
	if current_screen_id != Config.SCREEN_SAFE_WORD:
		return
	current_safe_word = Config.normalize_safe_word(safe_word)
	safe_word_completed = true
	current_screen_id = Config.SCREEN_OPENING
	var screen := OPENING_SCENE.instantiate()
	screen.start_step_id = "r58"
	screen.safe_word_completed = true
	screen.continue_pressed.connect(_on_opening_skip)
	screen.safe_word_requested.connect(_show_opening_safe_word)
	screen.game_requested.connect(func() -> void: _show_game(current_safe_word, true))
	screen.skip_pressed.connect(_on_opening_skip)
	_swap_screen(screen)

func _on_opening_skip() -> void:
	if current_screen_id != Config.SCREEN_OPENING:
		return
	if safe_word_completed:
		_show_game(current_safe_word, true)
	else:
		_show_opening_safe_word()

func _show_safe_word() -> void:
	current_screen_id = Config.SCREEN_SAFE_WORD
	var screen := SAFE_WORD_SCENE.instantiate()
	screen.continue_pressed.connect(_complete_direct_safe_word)
	_swap_screen(screen)
	_play_bgm("default", false)

func _complete_direct_safe_word(safe_word: String) -> void:
	if current_screen_id != Config.SCREEN_SAFE_WORD:
		return
	safe_word_completed = true
	_show_game(safe_word)

func _show_game(safe_word: String = Config.SAFE_WORD_DEFAULT, fade_from_opening: bool = false) -> void:
	current_screen_id = Config.SCREEN_GAME
	var screen := GAME_SCENE.instantiate()
	var trimmed_safe_word := safe_word.strip_edges()
	current_safe_word = Config.normalize_safe_word(trimmed_safe_word) if not trimmed_safe_word.is_empty() else current_safe_word
	if current_safe_word.is_empty():
		current_safe_word = Config.SAFE_WORD_DEFAULT
	screen.safe_word = current_safe_word
	screen.midi_pitch_provider = Callable(self, "get_gameplay_midi_pitch")
	screen.bgm_position_provider = Callable(self, "get_gameplay_bgm_position")
	screen.ending_requested.connect(_show_ending)
	screen.bgm_requested.connect(_on_game_bgm_requested)
	screen.debug_overlay = debug_overlay
	if fade_from_opening and current_screen_id == Config.SCREEN_GAME and current_screen != null:
		_fade_opening_to_screen(screen)
	else:
		_swap_screen(screen)
		debug_overlay.sync_live_readout(screen.get_debug_state())

func _fade_opening_to_screen(next_screen: Control) -> void:
	if screen_transition_tween != null:
		screen_transition_tween.kill()
	var opening_screen := current_screen
	screen_transition_overlay.visible = true
	screen_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	screen_transition_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	screen_transition_tween = create_tween().set_trans(Tween.TRANS_SINE)
	screen_transition_tween.tween_property(
		screen_transition_overlay, "color:a", 1.0, OPENING_TO_GAME_FADE_DURATION
	)
	screen_transition_tween.parallel().tween_property(
		opening_screen, "modulate:a", 0.0, OPENING_TO_GAME_FADE_DURATION
	)
	screen_transition_tween.tween_callback(func() -> void:
		_swap_screen_immediately(next_screen)
		if current_screen_id == Config.SCREEN_GAME:
			debug_overlay.sync_live_readout(next_screen.get_debug_state())
	)
	screen_transition_tween.tween_property(
		screen_transition_overlay, "color:a", 0.0, OPENING_TO_GAME_FADE_DURATION
	)
	screen_transition_tween.tween_callback(func() -> void:
		screen_transition_overlay.visible = false
		screen_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen_transition_tween = null
	)

func _restart_game_from_pause() -> void:
	pause_menu.close()
	_reset_run_bgm_positions()
	_restart_current_bgm()
	_show_game(current_safe_word)

func _restart_current_bgm() -> void:
	var track_key := current_bgm_key
	if bgm_tween != null:
		bgm_tween.kill()
		bgm_tween = null
	bg_music.stop()
	bg_music_secondary.stop()
	if track_key.is_empty():
		return
	bgm_playback_positions[track_key] = 0.0
	current_bgm_key = ""
	_play_bgm(track_key, false)

func _show_ending(ending_type: String) -> void:
	current_screen_id = Config.SCREEN_ENDING
	var screen := ENDING_SCENE.instantiate()
	screen.safe_word = current_safe_word
	screen.set_result(ending_type)
	screen.restart_pressed.connect(_replay_from_ending)
	screen.back_to_title_pressed.connect(_return_to_title_from_ending)
	_swap_screen_with_fade_in(screen, Color.WHITE if ending_type == Config.SUCCESS_ENDING else Color.BLACK)
	bgm_playback_positions["ending"] = 0.0
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

func _replay_from_ending() -> void:
	_reset_run_bgm_positions()
	_show_game(current_safe_word, true)

func _return_to_title_from_ending() -> void:
	_reset_run_bgm_positions()
	_show_title(true)

func _reset_run_bgm_positions() -> void:
	for track_key in bgm_playback_positions.keys():
		bgm_playback_positions[track_key] = 0.0

func _swap_screen(next_screen: Control, fade_to_black: bool = false) -> void:
	if screen_transition_tween != null:
		screen_transition_tween.kill()
		screen_transition_tween = null
	if not fade_to_black or current_screen == null or screen_transition_overlay == null:
		if screen_transition_overlay != null:
			screen_transition_overlay.visible = false
			screen_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_swap_screen_immediately(next_screen)
		return

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

func _swap_screen_with_fade_in(next_screen: Control, fade_color: Color) -> void:
	if screen_transition_tween != null:
		screen_transition_tween.kill()
		screen_transition_tween = null
	if screen_transition_overlay == null:
		_swap_screen_immediately(next_screen)
		return
	screen_transition_overlay.color = Color(fade_color.r, fade_color.g, fade_color.b, 1.0)
	screen_transition_overlay.visible = true
	screen_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_swap_screen_immediately(next_screen)
	screen_transition_tween = create_tween().set_trans(Tween.TRANS_SINE)
	screen_transition_tween.tween_property(
		screen_transition_overlay, "color:a", 0.0, ENDING_FADE_IN_DURATION
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


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)


func _update_mouse_cursor() -> void:
	var stretch_scale := get_viewport().get_stretch_transform().get_scale()
	# Native cursors use logical display points on HiDPI screens, while the
	# viewport stretch is measured in render pixels. Remove the OS display scale
	# so macOS does not apply the Retina factor to the cursor a second time.
	var display_scale := maxf(
		DisplayServer.screen_get_scale(DisplayServer.SCREEN_OF_MAIN_WINDOW),
		1.0
	)
	var cursor_scale: float = minf(stretch_scale.x, stretch_scale.y) / display_scale
	var cursor_size := Vector2i(
		clampi(roundi(TENTACLE_CURSOR_SIZE.x * cursor_scale), 1, MAX_CURSOR_SIZE),
		clampi(roundi(TENTACLE_CURSOR_SIZE.y * cursor_scale), 1, MAX_CURSOR_SIZE)
	)
	if cursor_size == _current_cursor_size:
		return
	_current_cursor_size = cursor_size
	var cursor_image := TENTACLE_CURSOR.get_image()
	cursor_image.resize(cursor_size.x, cursor_size.y, Image.INTERPOLATE_LANCZOS)
	var cursor_texture := ImageTexture.create_from_image(cursor_image)
	var hotspot := Vector2(cursor_size) * 0.5
	Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, hotspot)
	Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_POINTING_HAND, hotspot)


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
		"gameplay": _prepare_bgm_stream(BGM_GAMEPLAY, true),
		"ending": _prepare_bgm_stream(BGM_ENDING, true)
	}
	bgm_playback_positions.clear()
	for track_key in bgm_library.keys():
		bgm_playback_positions[track_key] = 0.0

func _prepare_bgm_stream(stream: AudioStream, should_loop: bool) -> AudioStream:
	var prepared_stream := stream.duplicate(true)
	if prepared_stream is AudioStreamMP3:
		prepared_stream.loop = should_loop
	elif prepared_stream is AudioStreamOggVorbis:
		prepared_stream.loop = should_loop
	return prepared_stream


func get_gameplay_midi_pitch() -> int:
	var position := get_gameplay_bgm_position()
	if position < 0.0:
		return -1
	return violin_timeline.get_pitch_at_time(position)

func get_gameplay_bgm_position() -> float:
	if current_bgm_key != "gameplay" or active_bgm_player == null or not active_bgm_player.playing:
		return -1.0
	return active_bgm_player.get_playback_position()

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
