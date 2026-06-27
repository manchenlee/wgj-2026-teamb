class_name GameConfig
extends RefCounted

const MAX_VALUE: float = 100.0

# Shared placeholder copy.
const FEEDBACK_MESSAGE_TEXT: String = "feedback feedback feedback"
const CHOICE_PROMPT_TEXT: String = "choice choice choice"
const RESPONSE_BUTTON_TEXT: String = "response response response"

# UI scaling.
# 整體 UI 字體縮放倍率；調大會讓介面文字更大、更容易閱讀，調小則會讓畫面更緊湊。
const UI_FONT_SCALE: float = 2.0

# Core arousal values.
# 遊戲開始時的身體值；調大會讓玩家開局更接近安全區或目標區，調小則開局壓力更高。
const INITIAL_PHYSICAL: float = 30.0
# 遊戲開始時的情感值；調大會讓玩家一開始較容易維持情感穩定，調小則更容易提早失衡。
const INITIAL_EMOTIONAL: float = 30.0
# 遊戲開始時的高潮值；調大會縮短達成結局所需時間，調小會拉長累積過程。
const INITIAL_PEAK: float = 0.0
# 啟動高潮累積所需的最低活躍門檻；調大表示玩家需要把雙方狀態維持得更高才會開始累積。
const MINIMUM_ACTIVE_THRESHOLD: float = 20.0
# 身體與情感可接受的差距範圍；調大會降低失衡失敗的機率，調小則更要求兩者保持同步。
const BALANCE_TOLERANCE: float = 10.0

# Passive progression.
# 身體值每秒自然下降量；調大會讓身體狀態掉得更快，玩家需要更頻繁操作。
const PHYSICAL_DECAY_PER_SECOND: float = 2.0
# 情感值每秒自然下降量；調大會讓情感更難維持，玩家需要更常做出正確選擇。
const EMOTIONAL_DECAY_PER_SECOND: float = 0.1
# 身體互動後暫停自然衰減的寬限時間；調大會讓連續輸入壓力變小，調小則更吃節奏。
const PHYSICAL_ACTIVITY_GRACE_SECONDS: float = 1.4
# 情感互動後暫停自然衰減的寬限時間；調大可讓選項成功的保護期更長，調小則維持難度更高。
const EMOTIONAL_ACTIVITY_GRACE_SECONDS: float = 2.8
# 高潮值上升速度；調大會更快進入成功結局，調小則需要更久的穩定表現。
const PEAK_GAIN_RATE: float = 3.0
# 高潮值下降速度；調大會更容易因狀態不佳而退步，調小則容錯更高。
const PEAK_LOSS_RATE: float = 1.0
# 當生理或心理停在 0 時，每個歸零狀態額外增加的整體興奮度下降速度；調大會讓放置不管的懲罰更明顯。
const PEAK_ZERO_VALUE_EXTRA_LOSS_RATE: float = 3.0

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
const ARROW_PROMPT_RING_RADIUS: float = 54.0
# 方向提示外圈線條粗細；調大會更顯眼，調小則視覺存在感更弱。
const ARROW_PROMPT_RING_WIDTH: float = 3.0
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
# 選到最佳選項時增加的情感值；調大會讓正確判斷更容易穩住情感，調小則成長較慢。
const EMOTIONAL_GAIN_GOOD_CHOICE: float = 10.0
# 選到中性選項時增加的情感值；調大會降低判斷失誤的成本，調小則更需要選到最佳答案。
const EMOTIONAL_GAIN_NEUTRAL_CHOICE: float = 3.0
# 選到不佳選項時扣除的情感值；調大會讓錯選更傷，調小則玩家較能承受試錯。
const EMOTIONAL_PENALTY_BAD_CHOICE: float = 5.0
# 情感選項的作答時限；調大會給玩家更多閱讀與思考時間，調小則節奏更急迫。
const CHOICE_TIMEOUT_SECONDS: float = 4.2
# 回饋訊息出現的最短間隔；調大會讓情感事件較不密集，調小則更頻繁打斷玩家。
const FEEDBACK_MESSAGE_INTERVAL_MIN: float = 1.5
# 回饋訊息出現的最長間隔；調大會拉大事件間距波動，調小則情感互動節奏更固定。
const FEEDBACK_MESSAGE_INTERVAL_MAX: float = 3.0

# Presentation tuning.
# 圓形 UI 的最小半徑；調大會讓小尺寸狀態下也較醒目，調小則更節省空間。
const CIRCLE_RADIUS_MIN: float = 200.0
# 圓形 UI 的最大半徑；調大會讓高狀態時的視覺膨脹更誇張，調小則變化較收斂。
const CIRCLE_RADIUS_MAX: float = 500.0
# 圓形描邊的最小粗細；調大會讓低狀態時也維持較強存在感，調小則更細緻。
const CIRCLE_STROKE_MIN: float = 4.0
# 圓形描邊的最大粗細；調大會強化高狀態時的視覺張力，調小則整體較輕。
const CIRCLE_STROKE_MAX: float = 8.0
# 主圓在畫面中的中心比例位置；調整後會改變整體 HUD 佈局重心。
const CIRCLE_CENTER_RATIO: Vector2 = Vector2(0.62, 0.5)
# 高潮標籤相對圓心的垂直位移；調大會讓標籤更往下，調小則更貼近主圓。
const PEAK_LABEL_OFFSET_Y: float = 228.0
# 切換桌面版配置的畫面寬度門檻；調大會讓更多裝置維持手機/窄版排版，調小則更早套用桌面版。
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
