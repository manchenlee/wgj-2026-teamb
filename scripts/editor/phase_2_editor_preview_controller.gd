@tool
extends Control

const ANCHOR_IDS := [
	"HeadLeft",
	"HeadRight",
	"Chest",
	"LeftArm",
	"RightArm",
	"Waist",
	"LeftLeg",
	"RightLeg"
]

const MARKER_COLORS := [
	Color(0.96, 0.34, 0.34, 0.28),
	Color(0.96, 0.62, 0.24, 0.28),
	Color(0.96, 0.86, 0.24, 0.28),
	Color(0.38, 0.84, 0.42, 0.28),
	Color(0.24, 0.78, 0.9, 0.28),
	Color(0.44, 0.56, 0.96, 0.28),
	Color(0.72, 0.44, 0.96, 0.28),
	Color(0.94, 0.4, 0.7, 0.28)
]

@export_category("Phase 2 Preview")
@export var show_phase2_editor_reference: bool = true:
	set(value):
		show_phase2_editor_reference = value
		_refresh_preview()

@export var print_phase_2_anchor_rects: bool = false:
	set(value):
		if not value:
			print_phase_2_anchor_rects = false
			return
		_print_anchor_rect_dump()
		print_phase_2_anchor_rects = false
		notify_property_list_changed()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_preview()
	set_process(true)

func _process(_delta: float) -> void:
	_refresh_preview()

func _refresh_preview() -> void:
	var reference_rect := _get_reference_rect()
	var screen_reference_enabled := _is_screen_reference_enabled()
	if reference_rect != null:
		reference_rect.visible = Engine.is_editor_hint() and show_phase2_editor_reference and screen_reference_enabled

	var markers_visible := Engine.is_editor_hint() and _is_layout_debug_enabled()
	visible = markers_visible
	_sync_anchor_markers(markers_visible)

func _sync_anchor_markers(markers_visible: bool) -> void:
	for index in range(ANCHOR_IDS.size()):
		var anchor_id := ANCHOR_IDS[index]
		var marker := get_node_or_null(anchor_id) as ColorRect
		if marker == null:
			continue
		marker.color = MARKER_COLORS[index % MARKER_COLORS.size()]
		marker.visible = markers_visible
		var border := marker.get_node_or_null("Border") as ColorRect
		if border != null:
			border.color = MARKER_COLORS[index % MARKER_COLORS.size()].lightened(0.15)
			border.visible = markers_visible
			border.size = marker.size
		var label := marker.get_node_or_null("Fill/Label") as Label
		if label != null:
			label.text = anchor_id
			label.visible = markers_visible
	_sync_editor_anchor_nodes()

func _get_reference_rect() -> TextureRect:
	var screen := _get_game_screen()
	if screen == null:
		return null
	return screen.get_node_or_null("BackgroundAnchor/Phase2EditorReference") as TextureRect

func _get_game_screen() -> Node:
	var current: Node = self
	while current != null:
		if String(current.name) == "GameScreen":
			return current
		current = current.get_parent()
	return null

func _is_layout_debug_enabled() -> bool:
	var screen := _get_game_screen()
	if screen == null:
		return false
	return bool(screen.get("show_layout_debug_bounds"))

func _is_screen_reference_enabled() -> bool:
	var screen := _get_game_screen()
	if screen == null:
		return true
	return bool(screen.get("show_phase2_editor_reference"))

func _sync_editor_anchor_nodes() -> void:
	var screen := _get_game_screen()
	if screen == null:
		return
	var prompt_region := screen.get_node_or_null("MainCharacterArea/CharacterPromptRegion") as Control
	if prompt_region == null:
		return
	for index in range(ANCHOR_IDS.size()):
		var anchor_id: String = ANCHOR_IDS[index]
		var anchor_node := prompt_region.get_node_or_null(anchor_id) as Control
		var marker := get_node_or_null(anchor_id) as Control
		if anchor_node == null or marker == null:
			continue
		anchor_node.position = marker.position
		anchor_node.size = marker.size
		anchor_node.visible = false

func _print_anchor_rect_dump() -> void:
	var lines: Array[String] = []
	lines.append("{")
	for index in range(ANCHOR_IDS.size()):
		var anchor_id: String = ANCHOR_IDS[index]
		var marker := get_node_or_null(anchor_id) as Control
		if marker == null:
			continue
		lines.append(
			"\t\"%s\": Rect2(%.1f, %.1f, %.1f, %.1f)," % [
				anchor_id,
				marker.position.x,
				marker.position.y,
				marker.size.x,
				marker.size.y
			]
		)
	lines.append("}")
	print("Phase 2 anchor Rect2 dump:\n%s" % "\n".join(lines))
