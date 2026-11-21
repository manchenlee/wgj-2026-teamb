class_name CursorHitArea
extends RefCounted

# The native gameplay cursor is 104 x 104 design pixels with its hotspot in
# the center. Keep note hit areas slightly larger than their visible circles.
const SIZE := Vector2(104.0, 104.0)
const DIAMETER: float = SIZE.x
const NOTE_HIT_MARGIN: float = 8.0

