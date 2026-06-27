class_name PlaceholderDialogueData
extends RefCounted

const Config := preload("res://scripts/gameplay/GameConfig.gd")

const LOW_PROMPTS := [
	{
		"speaker": "Companion",
		"text": "You feel distant right now. Want to slow down and reconnect?",
		"choices": {
			"good": "Acknowledge gently",
			"neutral": "Keep it brief",
			"bad": "Brush it off"
		}
	},
	{
		"speaker": "Companion",
		"text": "Something feels off-balance. Can we check in?",
		"choices": {
			"good": "Respond with care",
			"neutral": "Answer casually",
			"bad": "Dismiss the concern"
		}
	}
]

const BALANCED_PROMPTS := [
	{
		"speaker": "Companion",
		"text": "That feels better. What do you want to do next?",
		"choices": {
			"good": "Encourage the moment",
			"neutral": "Stay playful",
			"bad": "Turn cold"
		}
	},
	{
		"speaker": "Companion",
		"text": "We are getting into a rhythm now.",
		"choices": {
			"good": "Lean into it",
			"neutral": "Keep steady",
			"bad": "Break the mood"
		}
	}
]

const HIGH_GAP_PROMPTS := [
	{
		"speaker": "Companion",
		"text": "You are pushing in one direction too hard.",
		"choices": {
			"good": "Recenter together",
			"neutral": "Pause a beat",
			"bad": "Ignore the mismatch"
		}
	},
	{
		"speaker": "Companion",
		"text": "We need more balance, not just more intensity.",
		"choices": {
			"good": "Adjust thoughtfully",
			"neutral": "See what happens",
			"bad": "Double down"
		}
	}
]

func get_prompt(physical: float, emotional: float) -> Dictionary:
	var difference := absf(physical - emotional)
	var source := BALANCED_PROMPTS
	if physical < 35.0 or emotional < 35.0:
		source = LOW_PROMPTS
	elif difference > Config.BALANCE_TOLERANCE:
		source = HIGH_GAP_PROMPTS
	return source[randi() % source.size()].duplicate(true)
