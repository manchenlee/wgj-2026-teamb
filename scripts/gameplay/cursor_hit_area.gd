class_name CursorHitArea
extends RefCounted

# The native gameplay cursor is 104 x 104 design pixels with its hotspot in
# the center. Mouse input uses a small inset from each note's visible edge.
const SIZE := Vector2(104.0, 104.0)
const DIAMETER: float = SIZE.x
const NOTE_HIT_MARGIN: float = -6.0

