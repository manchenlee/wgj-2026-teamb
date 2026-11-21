extends SceneTree

const Controller := preload("res://scripts/gameplay/dialogue_choice_controller.gd")
const Profile := preload("res://data/character_profiles/pose_character_profile.gd")
const BaseProfile := preload("res://data/character_profiles/phase_character_profile.gd")
const PhaseConfigClass := preload("res://data/phases/phase_config.gd")
const Model := preload("res://scripts/gameplay/arousal_model.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var controller = Controller.new()
	controller.set_phase_config(PhaseConfigClass.new())
	var tagged_count := 0
	for entry_variant in controller.entries:
		var entry := entry_variant as Dictionary
		var feedback := entry.feedback as Array
		var expressions := entry.feedback_expressions as Array
		_check(feedback.size() == expressions.size(), "%s feedback expression count" % entry.id)
		for index in range(feedback.size()):
			controller.reset()
			controller.current_entry = entry.duplicate(true)
			controller.current_feedback_index = index - 1
			var event := controller.next_event(40.0, 40.0)
			_check(event.get("expression", "") == str(expressions[index] if expressions[index] is String else ""), "%s feedback %d expression" % [entry.id, index])
			if expressions[index] is String:
				_check(BaseProfile.expression_from_dialogue_label(expressions[index]) >= 0, "%s feedback %d label mapping" % [entry.id, index])
				tagged_count += 1
		for choice_variant in entry.choice:
			var choice := choice_variant as Dictionary
			var choice_id := str(choice.id)
			var reply_expressions := entry.response_expressions[choice_id] as Array
			_check(reply_expressions.size() == (entry.response[choice_id] as Array).size(), "%s %s response expression count" % [entry.id, choice_id])
			controller.reset()
			controller.current_entry = entry.duplicate(true)
			var outcome := controller.apply_choice(choice_id, Model.new())
			_check(outcome.get("reply_expression", "") == str(reply_expressions[0] if reply_expressions[0] is String else ""), "%s %s first response expression" % [entry.id, choice_id])
			for index in range(1, reply_expressions.size()):
				var event := controller.next_event(40.0, 40.0)
				_check(event.get("expression", "") == str(reply_expressions[index] if reply_expressions[index] is String else ""), "%s %s response %d expression" % [entry.id, choice_id, index])
				if reply_expressions[index] is String:
					_check(BaseProfile.expression_from_dialogue_label(reply_expressions[index]) >= 0, "%s %s response %d label mapping" % [entry.id, choice_id, index])
					tagged_count += 1
			if reply_expressions[0] is String:
				_check(BaseProfile.expression_from_dialogue_label(reply_expressions[0]) >= 0, "%s %s first response label mapping" % [entry.id, choice_id])
				tagged_count += 1
	_check(tagged_count == 75, "Imported expression tag count")
	for phase in range(1, 5):
		var profile = Profile.new(phase)
		for state in [Profile.ExpressionState.NEUTRAL, Profile.ExpressionState.POSITIVE, Profile.ExpressionState.NEGATIVE, Profile.ExpressionState.PSYCHOLOGICAL_POSITIVE, Profile.ExpressionState.LOOK_AWAY, Profile.ExpressionState.NEUTRAL_TALKING, Profile.ExpressionState.SMILE, Profile.ExpressionState.SURPRISED_HIGHLIGHT, Profile.ExpressionState.SURPRISED_NO_HIGHLIGHT, Profile.ExpressionState.NEUTRAL_FACE]:
			var visual := profile.resolve_visual_state(phase - 1, state)
			_check(visual.resolved_expression == state, "%s state %d resolution" % [profile.pose_name, state])
			_check(FileAccess.file_exists(profile.get_texture_path(visual.base_state_key)), "%s state %d texture" % [profile.pose_name, state])
		_check(profile.resolve_visual_state(phase - 1, BaseProfile.expression_from_dialogue_label("害羞")).base_state_key == "overall_init", "%s shy uses default" % profile.pose_name)
		_check(profile.resolve_visual_state(phase - 1, BaseProfile.expression_from_dialogue_label("無表情")).base_state_key == "neutral", "%s expressionless uses neutral" % profile.pose_name)
	if failures.is_empty():
		print("Dialogue expression headless tests passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
