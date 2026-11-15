# Rub 正式音色與後續取樣研究

## 已採用音色

Rub 現與 Slide 使用相同的 GeneralUser GS Violin program 40。採用玩家試聽認可的弓感音量起伏，並將深度從最多 −2.4 dB 增至最多 −4.0 dB，頻率維持 8 Hz。這是音量調變，不是音高顫音，也不重新觸發音符。每次連續 Rub 鎖定第一個 MIDI 音高，原有 0.125 秒無動作釋放仍有效。Clef 音符的獨立聲道只做衰減，釋放時恢復 0 dB；Violin bus、既有增益與 −6 dB limiter 都照舊。舊 Tremolo Strings 44 與開發版切換選項已移除。

## Sonatina Symphonic Orchestra Solo Violin 2 Tremolo

[SSO 官方維護庫](https://github.com/peastman/sso)明列 Solo Violin 2 的 Tremolo。其樂器為 SFZ 定義搭配取樣檔，並非可直接交給目前 `Sf2Reader` 的 SF2；維護庫說明已在 Sforzando 與 sfizz 測試。原樣使用需要相容的 SFZ 播放器，與本專案保留 Clef SF2 架構的要求不合。若未來另取得核准，可評估合法授權的取樣轉換工作流程、音域覆蓋、循環與音量匹配；此原型未下載或附帶任何 SSO 取樣。其 Solo Violin 2 有較多奏法但沒有無限循環版本，長 Rub 的持續性也需實測。[來源說明](https://github.com/peastman/sso#readme)

[專案 LICENSE](https://github.com/peastman/sso/blob/master/LICENSE)標示 Creative Commons Sampling Plus 1.0。[Creative Commons 授權摘要](https://creativecommons.org/licenses/sampling+/1.0/)說明：取樣、混音或創意轉化可商用；完整作品的散布限非商業用途，並要求署名、標示修改與授權條款。對遊戲附帶原始或轉換後取樣的授權適用方式，應先完成發行前審查；不能因「免費下載」就視為可直接打包。該授權工具已被 Creative Commons 退役。
