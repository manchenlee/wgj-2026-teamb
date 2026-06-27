class_name DialogueChoiceController
extends RefCounted

const Config := preload("res://scripts/core/game_config.gd")
const PlaceholderDialogueDataClass := preload("res://scripts/data/placeholder_dialogue_data.gd")

var data_source = PlaceholderDialogueDataClass.new()
var current_prompt: Dictionary = {}

func next_prompt(physical: float, emotional: float) -> Dictionary:
	current_prompt = data_source.get_prompt(physical, emotional)
	return current_prompt

func apply_choice(choice_quality: String, model) -> Dictionary:
	var delta_value := 0.0
	var reply := ""
	match choice_quality:
		"good":
			delta_value = Config.EMOTIONAL_GAIN_GOOD_CHOICE
			reply = "Companion: That helped."
		"neutral":
			delta_value = Config.EMOTIONAL_GAIN_NEUTRAL_CHOICE
			reply = "Companion: Okay... let us keep going."
		"bad":
			delta_value = -Config.EMOTIONAL_PENALTY_BAD_CHOICE
			reply = "Companion: That made things worse."
		_:
			reply = "Companion: ..."

	model.apply_emotional(delta_value)
	return {"reply": reply, "delta": delta_value}
