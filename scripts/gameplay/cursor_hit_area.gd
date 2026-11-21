class_name CursorHitArea
extends RefCounted

# The native gameplay cursor is 104 x 104 design pixels with its hotspot in
# the center. Keep its interaction area slightly smaller than a 104 px note.
const SIZE := Vector2(104.0, 104.0)
const DIAMETER: float = SIZE.x
const RADIUS: float = 44.0

