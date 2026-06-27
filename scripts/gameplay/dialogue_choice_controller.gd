class_name DialogueChoiceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const PlaceholderDialogueDataClass := preload("res://scripts/data/placeholder_dialogue_data.gd")

var data_source = PlaceholderDialogueDataClass.new()
var current_prompt: Dictionary = {}

func next_prompt(physical: float, emotional: float) -> Dictionary:
	current_prompt = data_source.get_prompt(physical, emotional)
	return current_prompt

func apply_choice(choice_quality: String, model) -> Dictionary:
	var delta_value := 0.0
	match choice_quality:
		"good":
			delta_value = Config.EMOTIONAL_GAIN_GOOD_CHOICE
		"neutral":
			delta_value = Config.EMOTIONAL_GAIN_NEUTRAL_CHOICE
		"bad":
			delta_value = -Config.EMOTIONAL_PENALTY_BAD_CHOICE

	model.apply_emotional(delta_value)
	return {"reply": Config.TEST_FEEDBACK_TEXT, "delta": delta_value}
