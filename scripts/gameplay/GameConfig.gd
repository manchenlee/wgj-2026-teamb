class_name GameConfig
extends RefCounted

const MAX_VALUE: float = 100.0

# Shared placeholder copy.
const FEEDBACK_MESSAGE_TEXT: String = "feedback feedback feedback"
const CHOICE_PROMPT_TEXT: String = "choice choice choice"
const RESPONSE_BUTTON_TEXT: String = "response response response"

# UI scaling.
const UI_FONT_SCALE: float = 2.0

# Core arousal values.
const INITIAL_PHYSICAL: float = 30.0
const INITIAL_EMOTIONAL: float = 30.0
const INITIAL_PEAK: float = 0.0
const MINIMUM_ACTIVE_THRESHOLD: float = 15.0
const BALANCE_TOLERANCE: float = 15.0

# Passive progression.
const PHYSICAL_DECAY_PER_SECOND: float = 2.0
const EMOTIONAL_DECAY_PER_SECOND: float = 2.0
const PHYSICAL_ACTIVITY_GRACE_SECONDS: float = 1.4
const EMOTIONAL_ACTIVITY_GRACE_SECONDS: float = 2.8
const PEAK_GAIN_RATE: float = 12.0
const PEAK_LOSS_RATE: float = 8.0

# Physical interaction tuning.
const DIRECTION_SEQUENCE_LENGTH_MIN: int = 3
const DIRECTION_SEQUENCE_LENGTH_MAX: int = 5
const DIRECTION_PROMPT_TIME_LIMIT: float = 2.4
const NEXT_PROMPT_REVEAL_DELAY: float = 0.5
const PROMPT_SPAWN_DELAY_MIN: float = 0.8
const PROMPT_SPAWN_DELAY_MAX: float = 1.2
const PHYSICAL_GAIN_ON_CORRECT_INPUT: float = 4.0
const PHYSICAL_PENALTY_ON_WRONG_INPUT: float = 3.0
const PHYSICAL_SEQUENCE_COMPLETE_BONUS: float = 7.0
const CORRECT_FEEDBACK_DISPLAY_DURATION: float = 0.45
const WRONG_FEEDBACK_DISPLAY_DURATION: float = 0.55
const ARROW_PROMPT_FONT_SIZE: int = 104
const ARROW_PROMPT_BOX_SIZE: Vector2 = Vector2(132.0, 132.0)
const ARROW_PROMPT_RING_RADIUS: float = 54.0
const ARROW_PROMPT_RING_WIDTH: float = 3.0
const ARROW_PROMPT_ANCHOR_OFFSETS := [
	Vector2(-128.0, -164.0),
	Vector2(0.0, -188.0),
	Vector2(126.0, -148.0),
	Vector2(-156.0, -26.0),
	Vector2(156.0, -18.0),
	Vector2(-120.0, 132.0),
	Vector2(0.0, 164.0),
	Vector2(122.0, 126.0)
]

# Emotional interaction tuning.
const EMOTIONAL_GAIN_GOOD_CHOICE: float = 8.0
const EMOTIONAL_GAIN_NEUTRAL_CHOICE: float = 2.0
const EMOTIONAL_PENALTY_BAD_CHOICE: float = 6.0
const CHOICE_TIMEOUT_SECONDS: float = 4.2
const FEEDBACK_MESSAGE_INTERVAL_MIN: float = 1.8
const FEEDBACK_MESSAGE_INTERVAL_MAX: float = 4.6

# Presentation tuning.
const CIRCLE_RADIUS_MIN: float = 164.0
const CIRCLE_RADIUS_MAX: float = 252.0
const CIRCLE_STROKE_MIN: float = 4.0
const CIRCLE_STROKE_MAX: float = 8.0
const PEAK_LABEL_OFFSET_Y: float = 228.0
const DESKTOP_BREAKPOINT: float = 1080.0

const SUCCESS_ENDING: String = "success"
const PEAK_DEPLETION_FAILURE_ENDING: String = "peak_depletion_failure"
const PHYSICAL_IMBALANCE_FAILURE_ENDING: String = "physical_imbalance_failure"
const EMOTIONAL_IMBALANCE_FAILURE_ENDING: String = "emotional_imbalance_failure"
const PHYSICAL_FAILURE_ENDING: String = PEAK_DEPLETION_FAILURE_ENDING
const EMOTIONAL_FAILURE_ENDING: String = PEAK_DEPLETION_FAILURE_ENDING

const SCREEN_TITLE: String = "title"
const SCREEN_WARNING: String = "warning"
const SCREEN_OPENING: String = "opening"
const SCREEN_GAME: String = "game"
const SCREEN_ENDING: String = "ending"

static func clamp_value(value: float) -> float:
	return clampf(value, 0.0, MAX_VALUE)
