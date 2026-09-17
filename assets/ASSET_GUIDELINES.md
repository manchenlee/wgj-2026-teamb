# Assets 命名與分類規則

這份文件規範 `assets/` 內資源的放置位置與命名方式。新資源請依照本文件命名；既有資源若已被場景或程式引用，改名以前請先確認 Godot 參照不會遺失。

## 目錄分類

- `art/`：所有圖片與視覺素材。
- `art/background/`：遊戲背景、場景底圖、環境圖。
- `art/character/`：角色、角色狀態、角色部件。
- `art/character/phase1/`：第一階段角色素材。
- `art/character/phase2/`：第二階段角色素材。
- `art/screens/`：完整畫面用圖片。
- `art/screens/title/`：標題畫面素材。
- `art/screens/ending/`：結局畫面素材。
- `art/ui/`：介面元件、按鈕、圖示、文字框、條狀元件。
- `art/ui/gameplay/`：遊戲主畫面的 HUD、模式切換、對話選項與互動提示。
- `art/ui/screens/`：特定 UI 畫面會用到的介面圖片。
- `audio/bgm/`：背景音樂與長音訊。
- `audio/sfx/`：短音效。若之後加入音效，請建立此資料夾。
- `dialogue/`：對話、回饋、結局等 JSON 資料。
- `fonts/`：字型檔。
- `theme/`：Godot theme、stylebox、UI theme resource。

## 命名原則

- 使用 `snake_case`：全部小寫，以底線分隔單字。
- 不使用空格、中文、特殊符號或連字號。
- 檔名應描述用途，不只描述外觀。
- 同一組連續素材使用固定前綴與編號。
- 編號建議補零到兩位數：`cover_01.png`、`end_05.png`。
- 狀態放在檔名最後：`face_idle.png`、`face_high.png`、`button_hover.png`。
- 不在檔名中重複副檔名：避免 `name.png.png`。
- Godot 自動產生的 `.import` 檔不需手動建立或修改，但應跟原始資源一起提交。

## 建議格式

### 美術素材

角色：

```text
assets/art/character/{phase}/{subject}_{state}.png
assets/art/character/{phase}/{subject}_{index}_{state}.png
```

範例：

```text
assets/art/character/phase1/overall_high.png
assets/art/character/phase2/face_idle.png
assets/art/character/phase2/tentacle_05_active.png
```

背景：

```text
assets/art/background/{scene_or_usage}.png
```

範例：

```text
assets/art/background/game_bg.png
assets/art/background/title_curtain.jpg
```

UI：

```text
assets/art/ui/{element}_{state}.png
assets/art/ui/{screen}/{element}_{state}.png
```

範例：

```text
assets/art/ui/button_normal.png
assets/art/ui/button_hover.png
assets/art/ui/screens/warning_panel.png
```

完整畫面：

```text
assets/art/screens/{screen_name}/{screen_name}_{index}.png
```

範例：

```text
assets/art/screens/title/cover_01.png
assets/art/screens/ending/end_05.png
```

### 音訊素材

BGM：

```text
assets/audio/bgm/{scene_or_mood}.mp3
assets/audio/bgm/{scene_or_mood}_loop.mp3
```

範例：

```text
assets/audio/bgm/default.mp3
assets/audio/bgm/ending.mp3
assets/audio/bgm/overall_high.mp3
```

SFX：

```text
assets/audio/sfx/{action_or_ui_event}.wav
```

範例：

```text
assets/audio/sfx/button_click.wav
assets/audio/sfx/page_turn.wav
```

### 對話資料

```text
assets/dialogue/{content_type}.json
```

範例：

```text
assets/dialogue/opening.json
assets/dialogue/feedback.json
assets/dialogue/endings.json
```

JSON 內部 key 也優先使用 `snake_case`，並讓檔名對應內容用途。

### 字型與 Theme

字型若是外部原始檔，可保留原字型名稱，方便追蹤授權與來源：

```text
assets/fonts/ShipporiMincho-Regular.ttf
```

專案自製 theme resource 使用 `snake_case`：

```text
assets/theme/default_theme.tres
assets/theme/dialogue_theme.tres
```

## 新增素材檢查表

- 資源放在正確分類資料夾。
- 檔名符合 `snake_case`。
- 沒有空格、中文、特殊符號或重複副檔名。
- 同組素材的前綴、狀態名、編號格式一致。
- Godot 重新匯入後，`.import` 檔已同步更新。
- 若改名既有資源，已確認場景、腳本與資源引用仍正常。

## 2026-09-17 UI/UX 素材對應

`art/ui/gameplay/` 內這批素材依 1920×1080 參考稿分工如下：

- `btn_talk_clicked.png`、`btn_talk_unclicked.png`、`btn_talk_warning.png`：心理／對話模式按鈕的選取、未選取、失衡警告狀態。
- `btn_music_clicked.png`、`btn_music_unclicked.png`、`btn_music_warning.png`：生理／調音模式按鈕的選取、未選取、失衡警告狀態。
- `img_score.png`：遊戲畫面左上角好感度計量圖示，搭配橫向進度條與 `/100` 數值。
- `img_dialogue.png`：心理階段下方角色台詞框。
- `btn_choose.png`、`btn_unchoose.png`：心理階段對話選項的 hover／按下與一般狀態。
- `img_tentacle.png`、`btn_friction.png`：生理階段摩擦互動目標與左右摩擦提示。
- `img_heart.png`：生理互動成功、路徑節點完成及角色正向回饋粒子。

安全詞畫面不使用這批遊戲內 HUD 素材；它沿用 `art/background/curtain.jpg` 與角色圖，並在前導劇情之後以 `SafeWordScreen.tscn` 顯示置中輸入視窗。專案流程不再包含規則書畫面，規則資訊由前導劇情自然帶出。

## 既有例外

目前專案中有少量既有檔名包含空格、大寫或重複副檔名。這些檔案可暫時保留，避免破壞 Godot 引用；後續若要整理，建議集中在一次資源重命名工作中處理，並完整測試相關場景。
