class_name GameConfig
extends RefCounted

const MAX_VALUE: float = 100.0
const INITIAL_PHYSICAL: float = 50.0
const INITIAL_EMOTIONAL: float = 50.0
const INITIAL_PEAK: float = 0.0

const MINIMUM_ACTIVE_THRESHOLD: float = 15.0
const BALANCE_TOLERANCE: float = 15.0
const NATURAL_DECAY_PER_SECOND: float = 2.0

const PHYSICAL_GAIN_PER_CORRECT_INPUT: float = 4.0
const PHYSICAL_PENALTY_PER_WRONG_INPUT: float = 3.0
const EMOTIONAL_GAIN_GOOD_CHOICE: float = 8.0
const EMOTIONAL_GAIN_NEUTRAL_CHOICE: float = 2.0
const EMOTIONAL_PENALTY_BAD_CHOICE: float = 6.0

const PEAK_GAIN_RATE: float = 12.0
const PEAK_LOSS_RATE: float = 8.0

const DIRECTION_SEQUENCE_LENGTH_MIN: int = 3
const DIRECTION_SEQUENCE_LENGTH_MAX: int = 5
const DIRECTION_SEQUENCE_TIME_LIMIT: float = 3.0
const MAX_WRONG_INPUTS_PER_ROUND: int = 3
const ROUND_RESTART_DELAY: float = 0.8
const DIALOGUE_PROMPT_INTERVAL: float = 4.0

const DESKTOP_BREAKPOINT: float = 1080.0

const SUCCESS_ENDING: String = "success"
const PHYSICAL_FAILURE_ENDING: String = "physical_depletion_failure"
const EMOTIONAL_FAILURE_ENDING: String = "emotional_depletion_failure"

const SCREEN_TITLE: String = "title"
const SCREEN_WARNING: String = "warning"
const SCREEN_OPENING: String = "opening"
const SCREEN_GAME: String = "game"
const SCREEN_ENDING: String = "ending"

static func clamp_value(value: float) -> float:
	return clampf(value, 0.0, MAX_VALUE)

