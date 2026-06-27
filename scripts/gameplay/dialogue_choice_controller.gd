class_name DialogueChoiceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")
const PlaceholderDialogueDataClass := preload("res://scripts/data/placeholder_dialogue_data.gd")

var data_source = PlaceholderDialogueDataClass.new()
var current_prompt: Dictionary = {}
var event_counter: int = 0

func reset() -> void:
	current_prompt = {}
	event_counter = 0

func next_event(physical: float, emotional: float) -> Dictionary:
	event_counter += 1
	if event_counter % 3 == 0:
		current_prompt = data_source.get_prompt(physical, emotional)
		return current_prompt

	current_prompt = {}
	return data_source.get_line(physical, emotional)

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
	var reply_text := str(current_prompt.get("reply_%s" % choice_quality, ""))
	if reply_text.is_empty():
		reply_text = str(current_prompt.get("reply", ""))
	if reply_text.is_empty():
		reply_text = "..."
	current_prompt = {}
	return {"reply": reply_text, "delta": delta_value}
