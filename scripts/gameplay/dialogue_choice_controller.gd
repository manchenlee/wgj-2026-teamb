class_name DialogueChoiceController
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

var current_prompt: Dictionary = {}
var event_counter: int = 0

func reset() -> void:
	current_prompt = {}
	event_counter = 0

func next_event(_physical: float, _emotional: float) -> Dictionary:
	event_counter += 1
	if event_counter % 3 == 0:
		current_prompt = {
			"text": Config.CHOICE_PROMPT_TEXT,
			"choices": {
				"good": Config.RESPONSE_BUTTON_TEXT,
				"neutral": Config.RESPONSE_BUTTON_TEXT,
				"bad": Config.RESPONSE_BUTTON_TEXT
			}
		}
		return current_prompt

	current_prompt = {}
	return {"text": Config.FEEDBACK_MESSAGE_TEXT}

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
	current_prompt = {}
	return {"reply": Config.FEEDBACK_MESSAGE_TEXT, "delta": delta_value}
