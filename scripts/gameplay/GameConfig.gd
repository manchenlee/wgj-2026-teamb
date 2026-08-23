class_name GameConfig
extends RefCounted

const MAX_VALUE: float = 100.0

# Shared dialogue defaults.
const FEEDBACK_MESSAGE_TEXT: String = "……"
const RESPONSE_BUTTON_TEXT: String = "……"
const SAFE_WORD_DEFAULT: String = "紅色"
const SAFE_WORD_EVENT_CHANCE: float = 0.15

# Core arousal values.
# 遊戲開始時的身體值；調大會讓玩家開局更接近安全區或目標區，調小則開局壓力更高。
const INITIAL_PHYSICAL: float = 40.0
# 遊戲開始時的情感值；調大會讓玩家一開始較容易維持情感穩定，調小則更容易提早失衡。
const INITIAL_EMOTIONAL: float = 40.0
# 遊戲開始時的高潮值；調大會縮短達成結局所需時間，調小會拉長累積過程。
const INITIAL_PEAK: float = 0.0
# Passive progression.
# 最平衡且兩項分數皆為 100 時，整體興奮度的最大上升速度。
const MAX_POSITIVE_PEAK_GAIN_RATE: float = 1.5

# --- Ordered checkpoint interaction (Physical Arousal) ---

const CLICK_NOTE_LIFETIME: float = 2.0
const SLIDE_CHECKPOINT_TIME_LIMIT: float = 2.0
const RUB_NOTE_LIFETIME: float = 4.0

# Required checkpoints after the start marker.
const SPOT_REQUIRED_CHECKPOINT_COUNT: int = 3

# Forgiving checkpoint hit radius in prompt-layer pixels.
const SPOT_CHECKPOINT_RADIUS: float = 40.0

# Center-to-center spacing used by the small path generator.
const SPOT_CHECKPOINT_SPACING: float = 120.0

# Rub Note tuning.
const RUB_REQUIRED_SCRUB_DISTANCE: float = 600.0
const RUB_VALID_MOTION_THRESHOLD: float = 3.0
const RUB_MAX_DELTA_PER_EVENT: float = 24.0
const RUB_TARGET_RADIUS: float = 80.0

# Total incremental Physical Arousal earned across all checkpoints.
# Applied by InteractionSpotManager from normalized checkpoint progress.
# Three completed checkpoints grant +1 incremental in total.
const SPOT_PROGRESS_GAIN_TOTAL: float = 1.0

# Extra Physical Arousal bonus on sequence completion.
const SPOT_COMPLETION_BONUS: float = 2.0

# Penalty when spot expires essentially ignored (progress_ratio < 0.1).
const SPOT_EXPIRY_PENALTY_IGNORED: float = 5.0

# Penalty when spot expires partially engaged (0.1 <= progress_ratio < 0.5).
const SPOT_EXPIRY_PENALTY_PARTIAL: float = 2.0
# No penalty when progress_ratio >= 0.5.

# Delay between spawn attempts.
const SPOT_INITIAL_SPAWN_DELAY: float = 1.0
const SPOT_SPAWN_DELAY_MIN: float = 1.1
const SPOT_SPAWN_DELAY_MAX: float = 1.6

# A single spawn schedule may overlap a small, one-cursor-manageable set of notes.
const SPOT_MAX_ACTIVE_COUNT: int = 3

# Relative production spawn weights for physiological note types.
const CLICK_NOTE_WEIGHT: float = 6.0
const SLIDE_NOTE_WEIGHT: float = 3.0
const RUB_NOTE_WEIGHT: float = 1.0

# --- LEGACY: Direction-sequence physical interaction (disabled, kept for rollback) ---
# Physical interaction tuning.
# 每次方向輸入序列的最短長度；調大會讓最低挑戰變長，調小則單次任務更簡短。
const DIRECTION_SEQUENCE_LENGTH_MIN: int = 3
# 每次方向輸入序列的最長長度；調大會提高高峰難度，調小可限制複雜度。
const DIRECTION_SEQUENCE_LENGTH_MAX: int = 4
# 單一方向提示的輸入時限；調大會給玩家更多反應時間，調小則更考驗手速。
const DIRECTION_PROMPT_TIME_LIMIT: float = 2.4
# 完成上一個提示到顯示下一個提示的延遲；調大會讓節奏更從容，調小則連續感更強。
const NEXT_PROMPT_REVEAL_DELAY: float = 0.9
# 方向提示生成的最短間隔；調大會降低提示密度，調小則讓操作更頻繁。
const PROMPT_SPAWN_DELAY_MIN: float = 1.1
# 方向提示生成的最長間隔；調大會讓節奏波動更大，調小則整體更緊湊一致。
const PROMPT_SPAWN_DELAY_MAX: float = 1.5
# 正確輸入時增加的身體值；調大會讓操作回饋更明顯，調小則需要更多正確輸入才能維持狀態。
const PHYSICAL_GAIN_ON_CORRECT_INPUT: float = 1.0
# 輸入錯誤時扣除的身體值；調大會放大失誤代價，調小則容錯更高。
const PHYSICAL_PENALTY_ON_WRONG_INPUT: float = 2.0
# 完成整段方向序列時的額外身體獎勵；調大會更鼓勵完整連段，調小則單次正確輸入的重要性相對提高。
const PHYSICAL_SEQUENCE_COMPLETE_BONUS: float = 5.0
# 顯示正確回饋訊息的時間；調大會讓成功提示更明顯，但也可能拖慢視覺節奏。
const CORRECT_FEEDBACK_DISPLAY_DURATION: float = 0.45
# 顯示錯誤回饋訊息的時間；調大會讓失誤提示停留更久，調小則畫面恢復更快。
const WRONG_FEEDBACK_DISPLAY_DURATION: float = 0.55
# 方向提示字體大小；調大會更醒目，調小則可減少遮擋畫面。
const ARROW_PROMPT_FONT_SIZE: int = 104
# 方向提示框的尺寸；調大會增加點擊/辨識範圍感，調小則版面更精簡。
const ARROW_PROMPT_BOX_SIZE: Vector2 = Vector2(132.0, 132.0)
# 方向提示外圈半徑；調大會讓提示元素看起來更鬆散，調小則更集中。
const ARROW_PROMPT_RING_RADIUS: float = 84.0
# 方向提示外圈線條粗細；調大會更顯眼，調小則視覺存在感更弱。
const ARROW_PROMPT_RING_WIDTH: float = 6.0
# 方向提示距離畫面邊緣的保留空間；調大可避免太貼邊，調小則可利用更多畫面範圍。
const ARROW_PROMPT_EDGE_MARGIN: float = 18.0
# 各方向提示相對中心的固定錨點位置；調整這組座標會直接改變提示在畫面上的分布與可讀性。
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
# 對話事件中，生理低於這個值時視為「低生理」。
const FEEDBACK_PHYSICAL_LOW_THRESHOLD: float = 38.0
# 對話事件中，生理高於這個值時視為「高生理」。
const FEEDBACK_PHYSICAL_HIGH_THRESHOLD: float = 45.0
# 對話事件中，心理低於這個值時視為「低心理」。
const FEEDBACK_EMOTIONAL_LOW_THRESHOLD: float = 38.0
# 對話事件中，心理高於這個值時視為「高心理」。
const FEEDBACK_EMOTIONAL_HIGH_THRESHOLD: float = 52.0

# Presentation tuning.
const PHYSIOLOGICAL_EXPRESSION_DURATION_SECONDS: float = 1.5
# 圓形 UI 的最小半徑；調大會讓小尺寸狀態下也較醒目，調小則更節省空間。
const CIRCLE_RADIUS_MIN: float = 100.0
# 圓形 UI 的最大半徑；調大會讓高狀態時的視覺膨脹更誇張，調小則變化較收斂。
const CIRCLE_RADIUS_MAX: float = 500.0
# 圓形描邊的最小粗細；調大會讓低狀態時也維持較強存在感，調小則更細緻。
const CIRCLE_STROKE_MIN: float = 4.0
# 圓形描邊的最大粗細；調大會強化高狀態時的視覺張力，調小則整體較輕。
const CIRCLE_STROKE_MAX: float = 4.0
# 主圓在畫面中的中心比例位置；調整後會改變整體 HUD 佈局重心。
const CIRCLE_CENTER_RATIO: Vector2 = Vector2(0.58, 0.46)
# 高潮標籤相對圓心的垂直位移；調大會讓標籤更往下，調小則更貼近主圓。
const PEAK_LABEL_OFFSET_Y: float = 228.0
# 高潮標籤相對圓心的水平位移；調大會讓標籤更偏右，調小（負值）則偏左。
const PEAK_LABEL_OFFSET_X: float = -40.0
# 回饋標籤相對錨點的垂直位移；調大（負值絕對值增大）會讓標籤更往上，調小則更靠近提示點。
const FEEDBACK_LABEL_OFFSET_Y: float = -74.0
const SUCCESS_ENDING: String = "success"
const PEAK_DEPLETION_FAILURE_ENDING: String = "peak_depletion_failure"
const PHYSICAL_IMBALANCE_FAILURE_ENDING: String = "physical_imbalance_failure"
const EMOTIONAL_IMBALANCE_FAILURE_ENDING: String = "emotional_imbalance_failure"
const PHYSICAL_FAILURE_ENDING: String = PEAK_DEPLETION_FAILURE_ENDING
const EMOTIONAL_FAILURE_ENDING: String = PEAK_DEPLETION_FAILURE_ENDING
const SAFEWORD_IGNORED_FAILURE_ENDING: String = "safeword_ignored_failure"

const SCREEN_TITLE: String = "title"
const SCREEN_WARNING: String = "warning"
const SCREEN_OPENING: String = "opening"
const SCREEN_GAME: String = "game"
const SCREEN_ENDING: String = "ending"

static func clamp_value(value: float) -> float:
	return clampf(value, 0.0, MAX_VALUE)
