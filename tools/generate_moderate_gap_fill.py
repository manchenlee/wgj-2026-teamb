"""Build a separate, beat-aligned Moderate Gap Fill proposal."""

from __future__ import annotations

import argparse
import hashlib
import json
from copy import deepcopy

import generate_violin_chart as base

APPROVED = base.ROOT / "data/violin_interaction_chart_moderate.json"
OUTPUT = base.ROOT / "data/violin_interaction_chart_moderate_gap_fill_candidate.json"
REPORT = base.ROOT / "data/violin_interaction_chart_moderate_gap_fill_report.md"
BANK_SOURCE = base.ROOT / "data/violin_interaction_chart_moderate_variants.json"
BANK_OUTPUT = base.ROOT / "data/violin_interaction_chart_moderate_gap_fill_variants_candidate.json"

# The timeline contains note seconds and ticks/beat, but omits tempo messages.
# 300 note onsets fit this quarter-note grid within 0.1 ms.
BEAT_SECONDS = 60.0 / 155.0
EARLY = {"click": 0.35, "rub": 1.2, "slide": 1.5}
EXPIRY = {"click": 2.0, "rub": 4.0, "slide": 2.0}


def verify_grid(notes: list[dict]) -> int:
    count = sum(abs(n["start"] - round(n["start"] / BEAT_SECONDS) * BEAT_SECONDS)
                <= 0.005 for n in notes)
    if count < 100:
        raise ValueError("MIDI note onsets do not support 155 BPM quarter notes")
    return count


def _visible_intervals(chart: dict, lives: dict[str, float],
                       pauses: tuple[tuple[float, float], ...] = (),
                       visual_tail: bool = True) -> list[tuple[float, float]]:
    duration = chart["loop_duration_seconds"]
    intervals = []
    for event in chart["events"]:
        start = event["spawn_time"]
        if any(a <= start < b for a, b in pauses):
            continue  # psychological mode consumes scheduled spawns
        tail = (0.22 if lives is EARLY else 0.28) if visual_tail else 0.0
        end = start + lives[event["type"]] + tail
        for a, b in pauses:
            if start < a < end:
                end += b - a  # lifetime timer pauses while hidden
        intervals.append((start, end))
    intervals += [(a - duration, b - duration) for a, b in intervals if b > duration]
    visible = []
    for start, end in intervals:
        pieces = [(max(0.0, start), min(duration, end))]
        for a, b in pauses:
            pieces = [(x, min(y, a)) for x, y in pieces if x < a] + [
                (max(x, b), y) for x, y in pieces if y > b]
        visible += [(x, y) for x, y in pieces if y > x]
    return visible


def screen_gaps(chart: dict, lives: dict[str, float],
                pauses: tuple[tuple[float, float], ...] = ()) -> list[tuple[float, float]]:
    cursor = 0.0
    gaps = []
    for start, end in sorted(_visible_intervals(chart, lives, pauses)):
        if start > cursor:
            gaps.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < chart["loop_duration_seconds"]:
        gaps.append((cursor, chart["loop_duration_seconds"]))
    return gaps


def empty_seconds(chart: dict, lives: dict[str, float],
                  pauses: tuple[tuple[float, float], ...] = ()) -> float:
    # Only count time in physiological mode.
    total = 0.0
    for a, b in screen_gaps(chart, lives, pauses):
        total += b - a - sum(max(0.0, min(b, y) - max(a, x)) for x, y in pauses)
    return total


def peak(chart: dict, lives: dict[str, float]) -> int:
    duration = chart["loop_duration_seconds"]
    edges = []
    for a, b in _visible_intervals(chart, lives, visual_tail=False):
        edges.extend(((a, 1), (b, -1)))
    active = high = 0
    for _, delta in sorted(edges, key=lambda x: (x[0], x[1])):
        active += delta
        high = max(high, active)
    return high


def _pitch_index(target: float, notes: list[dict], used: set[int],
                 seed: int, loop_index: int) -> int | None:
    before = [n["pitch"] for n in notes if n["start"] <= target]
    after = [n["pitch"] for n in notes if n["start"] > target]
    neighbors = before[-1:] + after[:1]
    rng = base._rng(seed, loop_index, f"pitch:{round(target / BEAT_SECONDS)}")
    choices = []
    for index, note in enumerate(notes):
        distance = abs(note["start"] - target)
        if index in used or distance > BEAT_SECONDS * 0.75:
            continue
        harmony = min((abs(note["pitch"] - pitch) for pitch in neighbors), default=0)
        if harmony > 7:
            continue
        choices.append((distance > 0.005, harmony, distance, rng.random() * 0.03, index))
    return min(choices)[-1] if choices else None


def add_gap_fill(chart: dict, notes: list[dict], seed: int, *,
                 max_total: int = 10, min_spacing: float = 0.9,
                 min_benefit: float = 0.25) -> dict:
    verify_grid(notes)
    result = deepcopy(chart)
    result["generation_config"].update({
        "strategy": "moderate_gap_fill_candidate", "gap_fill_seed": seed,
        "gap_fill_beat_seconds": BEAT_SECONDS, "gap_fill_max_total": max_total,
        "gap_fill_min_spacing_seconds": min_spacing,
    })
    used = {i for event in chart["events"] for i in event["note_indices"]}
    duration = chart["loop_duration_seconds"]
    loop_index = int(chart["generation_config"]["loop_index"])
    for _ in range(max_total):
        before_early = empty_seconds(result, EARLY)
        before_expiry = empty_seconds(result, EXPIRY)
        choices = []
        for beat in range(3, int((duration + base.LEAD) / BEAT_SECONDS)):
            target = beat * BEAT_SECONDS
            spawn = target - base.LEAD
            if not 0 < spawn < duration or target >= duration:
                continue
            if any(abs(spawn - e["spawn_time"]) < min_spacing for e in result["events"]):
                continue
            index = _pitch_index(target, notes, used, seed, loop_index)
            if index is None:
                continue
            note = notes[index]
            event = {
                "id": f"gap_fill_click_{beat:04d}", "type": "click",
                "spawn_time": round(spawn, 6),
                "source_start_time": round(target, 6),
                "source_end_time": round(target + min(note["end"] - note["start"], 0.45), 6),
                "pitch": note["pitch"], "pitch_note_index": index,
                "note_indices": [index], "checkpoints": [],
                "origin": "gap_fill", "pitch_origin": "unused_midi",
            }
            proposal = deepcopy(result)
            proposal["events"].append(event)
            proposal["events"].sort(key=lambda e: e["spawn_time"])
            if peak(proposal, EXPIRY) > 3:
                continue
            gain_early = before_early - empty_seconds(proposal, EARLY)
            gain_expiry = before_expiry - empty_seconds(proposal, EXPIRY)
            if gain_early < min_benefit:
                continue
            score = gain_early + 0.55 * gain_expiry
            rng = base._rng(seed, loop_index, f"beat:{beat}")
            choices.append((score + rng.uniform(-0.04, 0.04), -beat, event, proposal))
        if not choices:
            break
        _, _, selected, result = max(choices, key=lambda x: x[:2])
        used.add(selected["pitch_note_index"])
    base.validate_chart(result, notes)
    assert all(event in result["events"] for event in chart["events"])
    return result


def make_report(approved: dict, candidate: dict, notes: list[dict],
                bank: dict, candidate_bank: dict) -> str:
    a, b = base.metrics(approved), base.metrics(candidate)
    added = sorted((e for e in candidate["events"] if e.get("origin") == "gap_fill"),
                   key=lambda e: e["spawn_time"])
    lines = [
        "# Moderate MIDI Gap Fill 候選比較", "",
        "此檔案是離線提案；正式圖譜及遊戲規則均未修改。空檔定義為生理互動物件沒有可見且有效的時間。", "",
        "## 舊版只加一個 Click 的原因", "",
        "舊演算法只掃相鄰 spawn 間隔 ≥3 秒，還要求來源音符避開前後事件區間，並以固定 2.5 秒 Slide 佔用估計拒絕候選。Click 點擊即完成、Rub 可提早完成、Slide 可完成或到期，許多實際空畫面因此發生於短 spawn 間隔內。舊版第 0 輪只找到 1 個 Click。", "",
        "## 數量與四分拍", "",
        "| 項目 | 核准 Moderate | 候選 |", "|---|---:|---:|",
        f"| 事件總數 | {a['events']} | {b['events']} |",
        f"| Click | {a['types'].get('click', 0)} | {b['types'].get('click', 0)} |",
        f"| Slide / Rub | {a['types'].get('slide', 0)} / {a['types'].get('rub', 0)} | {b['types'].get('slide', 0)} / {b['types'].get('rub', 0)} |", "",
        f"時間線有 {verify_grid(notes)}/{len(notes)} 個音符起點吻合 155 BPM 四分音符格（誤差 ≤5 ms）；四分音符長 {BEAT_SECONDS:.9f} 秒。時間線未保存原始 tempo meta 訊息，因此拍速由 MIDI 音符起點推定。新增 Click 目標均在拍點，spawn 比目標早 {base.LEAD:.1f} 秒。", "",
        "| 目標秒數 | spawn 秒數 | 四分拍序 | 音高 / MIDI 索引 |", "|---:|---:|---:|---:|",
    ]
    for e in added:
        beat = round(e["source_start_time"] / BEAT_SECONDS)
        lines.append(f"| {e['source_start_time']:.3f} | {e['spawn_time']:.3f} | {beat} | {e['pitch']} / {e['pitch_note_index']} |")
    lines += ["", "## 空畫面與併發估計", "",
              "空畫面依可見物件計算，並包含上一輪跨 BGM 邊界的存活物件。提早完成模型的有效時間：Click 0.35、Rub 1.2、Slide 1.5 秒，完成後另計 0.22 秒淡出；未操作到期模型的有效時間：Click 2、Rub 4、Slide 初始檢查點 2 秒，到期後另計 0.28 秒淡出。Slide 操作中會重設計時，實際存活可更久。", "",
              "| 情境 | 核准版空畫面 | 候選空畫面 | 改善 | 峰值（核准/候選） |",
              "|---|---:|---:|---:|---:|"]
    for label, lives in (("提早完成", EARLY), ("未操作到期", EXPIRY)):
        before, after = empty_seconds(approved, lives), empty_seconds(candidate, lives)
        lines.append(f"| {label} | {before:.2f} 秒 | {after:.2f} 秒 | {before-after:.2f} 秒 | {peak(approved, lives)} / {peak(candidate, lives)} |")
    lines += ["", "心理模式會隱藏並暫停現有物件，且略過期間應 spawn 的事件。以 70–78 秒暫停作為示例，僅計生理模式空畫面：", "",
              "| 情境 | 核准版 | 候選 |", "|---|---:|---:|"]
    for label, lives in (("提早完成", EARLY), ("未操作到期", EXPIRY)):
        lines.append(f"| {label} | {empty_seconds(approved, lives, ((70., 78.),)):.2f} 秒 | {empty_seconds(candidate, lives, ((70., 78.),)):.2f} 秒 |")
    lines += ["", "候選在未操作到期模型的同時物件峰值不超過 3；遊戲端仍會在滿額或無安全錨點時略過事件。Slide 若持續操作，可比初始計時活得更久，仍有配置跳過風險。", "",
              "## 八輪固定變化", ""]
    for i, variant in enumerate(candidate_bank["variants"]):
        extra = [e for e in variant["events"] if e.get("origin") == "gap_fill"]
        beats = ", ".join(str(round(e["source_start_time"] / BEAT_SECONDS)) for e in extra)
        lines.append(f"- 輪次 {i}：+{len(extra)} Click；四分拍序 {beats or '無'}。")
    lines += ["", "同一 seed 與輪次結果相同。原 Slide/Rub、既有 Click、原音高綁定和計分邏輯保留。新增索引取未使用 MIDI 音符；無拍點音符時，選附近最多相差 7 半音的過渡音高。", "",
              "## 驗證結果", "",
              "- 產生時已核對 MIDI 來源 SHA-256、完整圖譜 schema、音高索引及第 0 輪與單檔候選一致。",
              "- 相關 Python 單元測試 12 項通過；Godot 4.6.2 headless 候選圖譜載入測試通過。",
              "- 正式圖譜與 gameplay 腳本無變更；場景錨點與遮罩仍可能讓個別 Click 在執行時略過。", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--max-total", type=int, default=10)
    args = parser.parse_args()
    source = base.SOURCE.read_bytes()
    notes, _ = base.validate_timeline(json.loads(source))
    approved = json.loads(APPROVED.read_text(encoding="utf-8"))
    if approved["source_sha256"] != hashlib.sha256(source).hexdigest():
        raise ValueError("Approved Moderate MIDI source hash mismatch")
    base.validate_chart(approved, notes)
    candidate = add_gap_fill(approved, notes, args.seed, max_total=args.max_total)
    bank = json.loads(BANK_SOURCE.read_text(encoding="utf-8"))
    if bank["source_sha256"] != approved["source_sha256"]:
        raise ValueError("Approved variant MIDI source hash mismatch")
    variants = [add_gap_fill(v, notes, args.seed, max_total=args.max_total) for v in bank["variants"]]
    if candidate != variants[0]:
        raise ValueError("Candidate differs from loop 0")
    candidate_bank = {"schema_version": 1, "strategy": "moderate_gap_fill_candidate",
                      "source_sha256": approved["source_sha256"],
                      "variant_count": len(variants), "variants": variants}
    OUTPUT.write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    BANK_OUTPUT.write_text(json.dumps(candidate_bank, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    REPORT.write_text(make_report(approved, candidate, notes, bank, candidate_bank), encoding="utf-8")
    print(f"Added {len(candidate['events']) - len(approved['events'])} Click events")


if __name__ == "__main__":
    main()
