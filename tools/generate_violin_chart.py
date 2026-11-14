"""Build a deterministic, offline physiological chart from violin_timeline.json.

This tool has no runtime dependency. Run from the project root:
    python tools/generate_violin_chart.py
"""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TIMELINE_PATH = ROOT / "data" / "violin_timeline.json"
CHART_PATH = ROOT / "data" / "violin_interaction_chart.json"
REPORT_PATH = ROOT / "data" / "violin_interaction_chart_report.md"

LEAD_SECONDS = 0.8
MIN_SPAWN_SPACING_SECONDS = 1.1
CLICK_MAX_DURATION_SECONDS = 0.45
SLIDE_MAX_ONSET_GAP_SECONDS = 0.52
SLIDE_MIN_SPAN_SECONDS = 0.4
RUB_MIN_SPAN_SECONDS = 1.6
RUB_MAX_SPAN_SECONDS = 2.8
RUB_MAX_REST_SECONDS = 0.5
MAX_ACTIVE = 3
CLICK_LIFETIME_SECONDS = 2.0
SLIDE_CHECKPOINT_TIMEOUT_SECONDS = 2.0
RUB_LIFETIME_SECONDS = 4.0
TYPE_CYCLE = ("click", "slide", "click", "rub")


def seconds(value: float) -> float:
    return round(value, 6)


def slide_group(notes: list[dict], index: int, accepted_count: int) -> list[int]:
    target_size = 3 + ((accepted_count // len(TYPE_CYCLE)) % 4)
    group = [index]
    for next_index in range(index + 1, min(index + target_size, len(notes))):
        previous = notes[next_index - 1]
        current = notes[next_index]
        if current["start"] - previous["start"] > SLIDE_MAX_ONSET_GAP_SECONDS:
            break
        group.append(next_index)
    if len(group) < 3 or notes[group[-1]]["start"] - notes[index]["start"] < SLIDE_MIN_SPAN_SECONDS:
        return []
    return group


def rub_phrase(notes: list[dict], index: int) -> list[int]:
    group = [index]
    for next_index in range(index + 1, len(notes)):
        previous = notes[next_index - 1]
        current = notes[next_index]
        if current["start"] - previous["end"] > RUB_MAX_REST_SECONDS:
            break
        if current["start"] - notes[index]["start"] > RUB_MAX_SPAN_SECONDS:
            break
        group.append(next_index)
        if current["end"] - notes[index]["start"] >= RUB_MIN_SPAN_SECONDS:
            break
    if notes[group[-1]]["end"] - notes[index]["start"] < RUB_MIN_SPAN_SECONDS:
        return []
    return group


def candidate(notes: list[dict], index: int, kind: str, accepted_count: int) -> list[int]:
    if kind == "click":
        note = notes[index]
        return [index] if note["end"] - note["start"] <= CLICK_MAX_DURATION_SECONDS else []
    if kind == "slide":
        return slide_group(notes, index, accepted_count)
    return rub_phrase(notes, index)


def occupancy_seconds(kind: str, note_count: int) -> float:
    if kind == "click":
        return CLICK_LIFETIME_SECONDS
    if kind == "rub":
        return RUB_LIFETIME_SECONDS
    # Initial deadline plus a fresh two-second deadline at each reached point.
    return SLIDE_CHECKPOINT_TIMEOUT_SECONDS * note_count


def validate_timeline(timeline: dict) -> tuple[list[dict], float]:
    notes = timeline["notes"]
    duration = float(timeline["loop_duration_seconds"])
    if duration <= 0 or not isinstance(notes, list) or not notes:
        raise ValueError("MIDI timeline has no usable notes or loop duration")
    previous_start = -1.0
    for note in notes:
        start, end, pitch = note["start"], note["end"], note["pitch"]
        if start < previous_start or start < 0 or end <= start or end > duration + 0.02 or not 0 <= pitch <= 127:
            raise ValueError("Invalid MIDI note order, duration, or pitch")
        previous_start = start
    return notes, duration


def generate_chart(timeline: dict, source_hash: str) -> tuple[dict, dict]:
    notes, duration = validate_timeline(timeline)
    events: list[dict] = []
    reservations: list[tuple[float, float]] = []
    selected: set[int] = set()
    reasons: Counter[str] = Counter()
    index = 0
    while index < len(notes):
        kind = TYPE_CYCLE[len(events) % len(TYPE_CYCLE)]
        group = candidate(notes, index, kind, len(events))
        if not group:
            reasons["unsuitable_for_next_type"] += 1
            index += 1
            continue
        start = notes[index]["start"]
        spawn = start - LEAD_SECONDS
        release = spawn + occupancy_seconds(kind, len(group))
        if spawn < 0 or release > duration:
            reasons["loop_boundary"] += 1
            index += 1
            continue
        if events and spawn - events[-1]["spawn_time"] < MIN_SPAWN_SPACING_SECONDS - 0.000001:
            reasons["spawn_spacing"] += 1
            index += 1
            continue
        overlap = sum(a < release and spawn < b for a, b in reservations)
        if overlap >= MAX_ACTIVE:
            reasons["estimated_active_cap"] += 1
            index += 1
            continue

        checkpoints = [
            {"note_index": note_index, "time": seconds(notes[note_index]["start"]), "pitch": notes[note_index]["pitch"]}
            for note_index in group
        ]
        pitch_source = max(group, key=lambda n: (notes[n]["end"] - notes[n]["start"], -n)) if kind == "rub" else group[0]
        event = {
            "id": f"{kind}_{index:04d}",
            "type": kind,
            "spawn_time": seconds(spawn),
            "source_start_time": seconds(start),
            "source_end_time": seconds(max(notes[n]["end"] for n in group)),
            "pitch": notes[pitch_source]["pitch"],
            "pitch_note_index": pitch_source,
            "note_indices": group,
            "checkpoints": checkpoints if kind == "slide" else [],
        }
        events.append(event)
        reservations.append((spawn, release))
        selected.update(group)
        index = group[-1] + 1

    # Sweep half-open worst-case occupancy intervals, processing releases first.
    edges = [(a, 1) for a, _ in reservations] + [(b, -1) for _, b in reservations]
    active = peak_active = 0
    for _, delta in sorted(edges, key=lambda edge: (edge[0], edge[1])):
        active += delta
        peak_active = max(peak_active, active)
    if peak_active > MAX_ACTIVE:
        raise AssertionError("Generated chart exceeds the configured active cap")
    if any(len(event["checkpoints"]) not in range(3, 7) for event in events if event["type"] == "slide"):
        raise AssertionError("Slide group length is outside 3–6")
    if len(selected) != sum(len(event["note_indices"]) for event in events):
        raise AssertionError("A MIDI note was assigned to multiple events")

    config = {
        "spawn_lead_seconds": LEAD_SECONDS,
        "minimum_spawn_spacing_seconds": MIN_SPAWN_SPACING_SECONDS,
        "max_active": MAX_ACTIVE,
        "click_lifetime_seconds": CLICK_LIFETIME_SECONDS,
        "slide_checkpoint_timeout_seconds": SLIDE_CHECKPOINT_TIMEOUT_SECONDS,
        "rub_lifetime_seconds": RUB_LIFETIME_SECONDS,
    }
    chart = {
        "schema_version": 1,
        "source_timeline": "res://data/violin_timeline.json",
        "source_sha256": source_hash,
        "loop_duration_seconds": duration,
        "generation_config": config,
        "events": events,
    }
    analysis = {
        "note_count": len(notes),
        "selected_note_count": len(selected),
        "skipped_note_count": len(notes) - len(selected),
        "selected_by_type": Counter(
            event["type"] for event in events for _ in event["note_indices"]
        ),
        "event_counts": Counter(event["type"] for event in events),
        "slide_sizes": Counter(len(event["checkpoints"]) for event in events if event["type"] == "slide"),
        "peak_active": peak_active,
        "estimated_overlap_events": sum(
            any(other_start < end and start < other_end for other_start, other_end in reservations[:i] + reservations[i + 1:])
            for i, (start, end) in enumerate(reservations)
        ),
        "rejection_reasons": reasons,
    }
    return chart, analysis


def report(chart: dict, analysis: dict) -> str:
    counts = analysis["event_counts"]
    sizes = analysis["slide_sizes"]
    selected_by_type = analysis["selected_by_type"]
    duration = chart["loop_duration_seconds"]
    events = chart["events"]
    return f"""# 小提琴 MIDI 生理互動譜面分析（離線第 1 階段）

- 來源：`data/violin_timeline.json`；SHA-256：`{chart['source_sha256']}`；循環 {duration:.3f} 秒。
- 譜面：{len(events)} 件（Click {counts['click']}、Slide {counts['slide']}、Rub {counts['rub']}），平均 {len(events) * 60 / duration:.1f} 件／分鐘。
- MIDI 音符：共 {analysis['note_count']} 個；納入 {analysis['selected_note_count']} 個（{analysis['selected_note_count'] / analysis['note_count']:.1%}），略過 {analysis['skipped_note_count']} 個。略過原因含密度限制及不適合下一類互動的音，單一音符不會重複分配。
- 納入音符按互動分：Click {selected_by_type['click']}、Slide {selected_by_type['slide']}、Rub {selected_by_type['rub']}。譜面 `note_indices` 可追溯每個納入音；其餘 MIDI 索引即為略過音。
- Slide 組大小：{', '.join(f'{n} 音 {sizes[n]} 組' for n in range(3, 7))}。起點包含在組內；每點有來源索引、起點秒數與音高。秒數只作譜面資料，不作輸入判定。
- 預告：來源首音前 {LEAD_SECONDS:.1f} 秒生成；相鄰生成至少 {MIN_SPAWN_SPACING_SECONDS:.1f} 秒。Click 保留 2 秒、Rub 保留 4 秒、Slide 估算每點最多 2 秒，未增加節奏命中視窗。
- 最保守占用估算：峰值同時 {analysis['peak_active']} 件（上限 {MAX_ACTIVE}）；有占用重疊的事件 {analysis['estimated_overlap_events']} 件。此為最晚到期估算；玩家提早完成會降低實際並存數。
- 候選未採用次數（可多次落在最終略過的音附近）：類型不合 {analysis['rejection_reasons']['unsuitable_for_next_type']}、最小生成間距 {analysis['rejection_reasons']['spawn_spacing']}、估算並存上限 {analysis['rejection_reasons']['estimated_active_cap']}、循環邊界 {analysis['rejection_reasons']['loop_boundary']}。

## 規則與剩餘衝突

- 固定類型序列 Click／Slide／Click／Rub；Click 取 ≤{CLICK_MAX_DURATION_SECONDS:.2f} 秒的短音；Slide 取連續 3–6 音；Rub 取至少 {RUB_MIN_SPAN_SECONDS:.1f} 秒的連續樂句，並選句中最長音的音高。這是離線選曲規則，並不改變既有完成與失敗條件。
- Rub 的樂句可能比單一音長；譜面音高應在每次連續按住摩擦時鎖定。Slide 的各點音高應於到點播放時取對應欄位。第 1 階段未接入音效。
- 心理模式會暫停已存在的生理互動，但背景音樂仍行進。未來排程須跳過心理模式期間錯過的譜面事件且不處罰，恢復時仍保留已暫停的互動；因此實際占用可能超過此處按音樂時間計算的預估，執行時仍須檢查 3 件上限並跳過無法生成的事件。
- 錨點、遮罩、擺放避讓與姿勢切換只能在執行時確認；即使譜面估算允許，實際位置不安全的事件仍須跳過且不處罰。循環首尾也不安排跨界仍未到期的互動，以免重播時重複生成。

此報告由 `python tools/generate_violin_chart.py` 與譜面同時產生；第 1 階段未變更執行時程式、場景或計分。
"""


def main() -> None:
    source = TIMELINE_PATH.read_bytes()
    chart, analysis = generate_chart(json.loads(source), hashlib.sha256(source).hexdigest())
    CHART_PATH.write_text(json.dumps(chart, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    REPORT_PATH.write_text(report(chart, analysis), encoding="utf-8")
    print(f"Generated {len(chart['events'])} events; selected {analysis['selected_note_count']} MIDI notes; peak estimated active {analysis['peak_active']}.")
    print(f"Chart: {CHART_PATH.relative_to(ROOT)}")
    print(f"Report: {REPORT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
