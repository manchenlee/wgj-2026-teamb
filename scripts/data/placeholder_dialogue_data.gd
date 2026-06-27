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
		},
		"reply_good": "Thank you. That helps me settle back in.",
		"reply_neutral": "Okay. I will take the small answer for now.",
		"reply_bad": "That stings. I need more care than that."
	},
	{
		"speaker": "Companion",
		"text": "Something feels off-balance. Can we check in?",
		"choices": {
			"good": "Respond with care",
			"neutral": "Answer casually",
			"bad": "Dismiss the concern"
		},
		"reply_good": "Yeah, that is closer to what I needed.",
		"reply_neutral": "Maybe. I still feel a little unsure.",
		"reply_bad": "Ignoring it will only make it worse."
	}
]

const LOW_LINES := [
	{
		"speaker": "Companion",
		"text": "Stay with me for a second."
	},
	{
		"speaker": "Companion",
		"text": "I am trying to read your pace."
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
		},
		"reply_good": "Mmm. Stay there with me.",
		"reply_neutral": "That works. We can keep it light.",
		"reply_bad": "You just pulled me out of it."
	},
	{
		"speaker": "Companion",
		"text": "We are getting into a rhythm now.",
		"choices": {
			"good": "Lean into it",
			"neutral": "Keep steady",
			"bad": "Break the mood"
		},
		"reply_good": "Yes. That keeps the feeling alive.",
		"reply_neutral": "Steady is okay. Do not lose me completely.",
		"reply_bad": "That killed the momentum."
	}
]

const BALANCED_LINES := [
	{
		"speaker": "Companion",
		"text": "This rhythm is starting to feel natural."
	},
	{
		"speaker": "Companion",
		"text": "Okay, that lands better."
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
		},
		"reply_good": "There. That brings us back together.",
		"reply_neutral": "A pause helps, but we still need to adjust.",
		"reply_bad": "No, that makes the disconnect worse."
	},
	{
		"speaker": "Companion",
		"text": "We need more balance, not just more intensity.",
		"choices": {
			"good": "Adjust thoughtfully",
			"neutral": "See what happens",
			"bad": "Double down"
		},
		"reply_good": "That is better. You are actually listening.",
		"reply_neutral": "Maybe. I am still waiting for you to meet me halfway.",
		"reply_bad": "Too much. You are not hearing me."
	}
]

const HIGH_GAP_LINES := [
	{
		"speaker": "Companion",
		"text": "We are drifting out of sync."
	},
	{
		"speaker": "Companion",
		"text": "Something is off in the balance right now."
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

func get_line(physical: float, emotional: float) -> Dictionary:
	var difference := absf(physical - emotional)
	var source := BALANCED_LINES
	if physical < 35.0 or emotional < 35.0:
		source = LOW_LINES
	elif difference > Config.BALANCE_TOLERANCE:
		source = HIGH_GAP_LINES
	return source[randi() % source.size()].duplicate(true)
