class_name PhaseLibrary
extends RefCounted

const Phase1Config := preload("res://data/phases/phase_1_config.gd")
const Phase2Config := preload("res://data/phases/phase_2_config.gd")

static func build_default_sequence() -> Array:
	return [
		Phase1Config.new(),
		Phase2Config.new()
	]
