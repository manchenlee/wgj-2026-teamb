class_name NoteInputSampling
extends RefCounted

static var _active_drags: int = 0
static var _previous_accumulated_input: bool = true


static func acquire() -> void:
	if _active_drags == 0:
		_previous_accumulated_input = Input.use_accumulated_input
		Input.use_accumulated_input = false
	_active_drags += 1


static func release() -> void:
	if _active_drags <= 0:
		return
	_active_drags -= 1
	if _active_drags == 0:
		Input.use_accumulated_input = _previous_accumulated_input
