class_name CursorHitArea
extends RefCounted

# The native gameplay cursor is 104 x 104 design pixels with its hotspot in
# the center. Treat the visible cursor as a 104 px circular interaction area.
const SIZE := Vector2(104.0, 104.0)
const DIAMETER: float = SIZE.x
const RADIUS: float = 52.0

