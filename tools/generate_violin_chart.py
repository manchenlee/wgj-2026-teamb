"""Build deterministic phrase-first candidate charts. Never overwrites production.

    python tools/generate_violin_chart.py [--seed 2026] [--loop-index 0]

Loop variants are generated offline; runtime switching is not enabled.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "violin_timeline.json"
PRODUCTION = ROOT / "data" / "violin_interaction_chart.json"
LEAD = 0.8
FAST_GAP = 0.18
PHRASE_GAP = 0.52
MAX_ACTIVE = 3
STRATEGIES = ("moderate", "high")


@dataclass(frozen=True)
class Candidate:
    kind: str
    indices: tuple[int, ...]
    priority: int
    phrase: int
    essential: bool = False


def _rng(seed: int, loop_index: int, key: str) -> random.Random:
    digest = hashlib.sha256(f"{seed}:{loop_index}:{key}".encode()).digest()
    return random.Random(int.from_bytes(digest[:8], "big"))


def validate_timeline(timeline: dict) -> tuple[list[dict], float]:
    notes = timeline["notes"]
    duration = float(timeline["loop_duration_seconds"])
    if duration <= 0 or not notes:
        raise ValueError("Empty MIDI timeline")
    previous = -1.0
    for note in notes:
        start, end, pitch = note["start"], note["end"], note["pitch"]
        if start < previous or start < 0 or end <= start or end > duration + 0.02 or not 0 <= pitch <= 127:
            raise ValueError("Invalid MIDI note order, duration, or pitch")
        previous = start
    return notes, duration


def phrase_ranges(notes: list[dict]) -> list[tuple[int, int]]:
    """Use rests, onset gaps, and pitch leaps after slower notes as boundaries."""
    starts = [0]
    for i in range(1, len(notes)):
        gap = notes[i]["start"] - notes[i - 1]["start"]
        rest = notes[i]["start"] - notes[i - 1]["end"]
        leap = abs(notes[i]["pitch"] - notes[i - 1]["pitch"])
        if gap > PHRASE_GAP or rest > 0.35 or (gap > 0.32 and leap >= 12):
            starts.append(i)
    return [(start, starts[k + 1] - 1 if k + 1 < len(starts) else len(notes) - 1)
            for k, start in enumerate(starts)]


def fast_runs(notes: list[dict]) -> list[tuple[int, int]]:
    """Close onset spacing is fast; this does not assert notation as triplets."""
    runs = []
    start = 0
    for i in range(len(notes) - 1):
        if notes[i + 1]["start"] - notes[i]["start"] > FAST_GAP:
            if i - start + 1 >= 3:
                runs.append((start, i))
            start = i + 1
    if len(notes) - start >= 3:
        runs.append((start, len(notes) - 1))
    return runs


def _chunks(indices: list[int], rng: random.Random, vary: bool) -> list[tuple[int, ...]]:
    """Partition a phrase into complete 3-6 note figures, never dropping notes."""
    result = []
    remaining = indices[:]
    while remaining:
        if len(remaining) <= 6:
            size = len(remaining)
        elif len(remaining) - 6 in (1, 2):
            size = len(remaining) - 3
        else:
            size = 6
        if vary and size == 6 and len(remaining) > 6 and rng.random() < 0.2:
            result.extend((tuple(remaining[:3]), tuple(remaining[3:6])))
        else:
            result.append(tuple(remaining[:size]))
        remaining = remaining[size:]
    return result


def _source_candidates(notes: list[dict], strategy: str, seed: int, loop_index: int) -> tuple[list[Candidate], dict]:
    fast = fast_runs(notes)
    fast_indices = {i for a, b in fast for i in range(a, b + 1)}
    candidates = []
    skeleton = []
    for phrase_id, (a, b) in enumerate(fast):
        rng = _rng(seed, loop_index, f"fast:{a}")
        chunks = _chunks(list(range(a, b + 1)), rng, strategy == "high" and loop_index > 0)
        for k, indices in enumerate(chunks):
            essential = k == 0 or k == len(chunks) - 1
            if strategy == "moderate" and not essential and k % 2:
                continue
            candidates.append(Candidate("slide", indices, 100 if essential else 85, phrase_id, essential))
            if essential:
                skeleton.append(indices)

    # Split slow material at every fast passage so Rub cannot absorb a run.
    secondary = []
    for a, b in phrase_ranges(notes):
        block = []
        for i in range(a, b + 1):
            if i in fast_indices:
                if block:
                    secondary.append(block)
                    block = []
            else:
                block.append(i)
        if block:
            secondary.append(block)

    for phrase_id, block in enumerate(secondary, start=len(fast)):
        rng = _rng(seed, loop_index, f"secondary:{block[0]}")
        if len(block) >= 3:
            chunks = _chunks(block, rng, strategy == "high" and loop_index > 0)
            phase = rng.randrange(2)
            for k, indices in enumerate(chunks):
                if len(indices) < 3 or strategy == "moderate" and k % 2 != phase:
                    continue
                movement = sum(notes[j]["pitch"] != notes[j - 1]["pitch"] for j in indices[1:])
                candidates.append(Candidate("slide", indices, 65 + min(movement, 5), phrase_id))
        for i in block:
            length = notes[i]["end"] - notes[i]["start"]
            if length >= 0.75:
                # One sustained source note per Rub: all selected pitches stay playable.
                candidates.append(Candidate("rub", (i,), 55, phrase_id))
            elif length <= 0.45:
                previous = notes[i]["start"] - notes[i - 1]["start"] if i else 99.0
                following = notes[i + 1]["start"] - notes[i]["start"] if i + 1 < len(notes) else 99.0
                accent = min(previous, following) > 0.35 or notes[i].get("velocity", 0) >= 100
                if accent or len(block) == 1:
                    candidates.append(Candidate("click", (i,), 45 if accent else 35, phrase_id))
    return candidates, {"fast_runs": fast, "skeleton": skeleton}


def _lifetime(candidate: Candidate, slide_seconds: float | None) -> float:
    if candidate.kind == "slide":
        return 2.0 * len(candidate.indices) if slide_seconds is None else slide_seconds
    return 2.0 if candidate.kind == "click" else 4.0


def occupancy(events: list[Candidate], notes: list[dict], duration: float,
              slide_seconds: float | None) -> dict:
    """Circular-loop occupancy plus chronological cap-only skip estimate."""
    intervals = []
    for event in events:
        spawn = notes[event.indices[0]]["start"] - LEAD
        end = spawn + _lifetime(event, slide_seconds)
        intervals.append((spawn, end, event))
    edges = []
    cross = 0
    for start, end, _ in intervals:
        edges.extend(((start, 1), (end, -1)))
        if end > duration:
            cross += 1
            edges.extend(((start - duration, 1), (end - duration, -1)))
    active = peak = 0
    for _, delta in sorted(edges, key=lambda edge: (edge[0], edge[1])):
        active += delta
        peak = max(peak, active)
    kept = []
    skipped = []
    # Estimate capacity on an ordinary loop, carrying tail interactions from
    # the previous loop. This has no position/psychological-mode model.
    for start, end, event in sorted(intervals, key=lambda entry: entry[0]):
        overlaps = [(a, b) for a, b, _ in kept if a < end and start < b]
        overlaps += [(a - duration, b - duration) for a, b, _ in intervals if b > duration and a - duration < end and start < b - duration]
        local = [(start, 1), (end, -1)]
        for a, b in overlaps:
            local.extend(((max(a, start), 1), (min(b, end), -1)))
        count = local_peak = 0
        for _, delta in sorted(local, key=lambda edge: (edge[0], edge[1])):
            count += delta
            local_peak = max(local_peak, count)
        if local_peak > MAX_ACTIVE:
            skipped.append(event)
        else:
            kept.append((start, end, event))
    return {"peak": peak, "cross_loop": cross, "cap_skips": len(skipped)}


def _select(notes: list[dict], duration: float, candidates: list[Candidate],
            strategy: str) -> tuple[list[Candidate], Counter, list[tuple[Candidate, str]]]:
    chosen = []
    rejected = Counter()
    rejected_essential = []
    used = set()
    spacing = 1.5 if strategy == "moderate" else 0.28
    for candidate in sorted(candidates, key=lambda c: (-c.priority, notes[c.indices[0]]["start"], c.indices)):
        spawn = notes[candidate.indices[0]]["start"] - LEAD
        reason = ""
        if spawn < 0 or spawn >= duration:
            reason = "spawn_boundary"
        elif used.intersection(candidate.indices):
            reason = "already_covered"
        elif not candidate.essential and any(abs(spawn - (notes[c.indices[0]]["start"] - LEAD)) < spacing for c in chosen):
            reason = "secondary_spacing"
        elif strategy == "moderate" and occupancy(chosen + [candidate], notes, duration, 2.5)["peak"] > MAX_ACTIVE:
            reason = "estimated_active_cap"
        if reason:
            rejected[reason] += 1
            if candidate.essential:
                rejected_essential.append((candidate, reason))
        else:
            chosen.append(candidate)
            used.update(candidate.indices)
    return sorted(chosen, key=lambda c: notes[c.indices[0]]["start"]), rejected, rejected_essential


def validate_chart(chart: dict, notes: list[dict]) -> None:
    previous_spawn = -1.0
    seen_ids = set()
    seen_notes = set()
    for event in chart["events"]:
        indices = event["note_indices"]
        spawn = event["spawn_time"]
        if not indices or event["id"] in seen_ids or not previous_spawn < spawn < chart["loop_duration_seconds"]:
            raise ValueError("Duplicate, unordered, or out-of-range event")
        if any(i < 0 or i >= len(notes) or i in seen_notes for i in indices):
            raise ValueError("Duplicate or invalid MIDI note index")
        if indices != list(range(indices[0], indices[-1] + 1)):
            raise ValueError("Interaction drops a source note inside its group")
        if event["pitch"] != notes[event["pitch_note_index"]]["pitch"]:
            raise ValueError("Pitch binding mismatch")
        checkpoints = event["checkpoints"]
        if event["type"] == "slide":
            if not 3 <= len(indices) <= 6 or len(checkpoints) != len(indices):
                raise ValueError("Slide requires 3-6 notes")
            for i, checkpoint in zip(indices, checkpoints):
                if checkpoint["note_index"] != i or checkpoint["pitch"] != notes[i]["pitch"] or abs(checkpoint["time"] - notes[i]["start"]) > 0.000002:
                    raise ValueError("Checkpoint lost MIDI timing or pitch")
        elif event["type"] in ("click", "rub"):
            if len(indices) != 1 or checkpoints:
                raise ValueError("Click/Rub must have one source note")
        else:
            raise ValueError("Invalid interaction type")
        seen_ids.add(event["id"])
        seen_notes.update(indices)
        previous_spawn = spawn


def generate_chart(timeline: dict, source_hash: str, strategy: str, seed: int = 2026,
                   loop_index: int = 0) -> tuple[dict, dict]:
    if strategy not in STRATEGIES or loop_index < 0:
        raise ValueError("Invalid strategy or loop index")
    notes, duration = validate_timeline(timeline)
    candidates, source = _source_candidates(notes, strategy, seed, loop_index)
    selected, rejected, rejected_essential = _select(notes, duration, candidates, strategy)
    events = []
    for candidate in selected:
        indices = list(candidate.indices)
        first = notes[indices[0]]
        checkpoints = [{"note_index": i, "time": round(notes[i]["start"], 6), "pitch": notes[i]["pitch"]}
                       for i in indices] if candidate.kind == "slide" else []
        events.append({
            "id": f"{candidate.kind}_{indices[0]:04d}",
            "type": candidate.kind,
            "spawn_time": round(first["start"] - LEAD, 6),
            "source_start_time": round(first["start"], 6),
            "source_end_time": round(max(notes[i]["end"] for i in indices), 6),
            "pitch": first["pitch"], "pitch_note_index": indices[0],
            "note_indices": indices, "checkpoints": checkpoints,
        })
    chart = {
        "schema_version": 1,
        "source_timeline": "res://data/violin_timeline.json",
        "source_sha256": source_hash,
        "loop_duration_seconds": duration,
        "generation_config": {
            "strategy": strategy, "run_seed": seed, "loop_index": loop_index,
            "placement_seed_for_future_runtime": int.from_bytes(
                hashlib.sha256(f"{seed}:{loop_index}:placement".encode()).digest()[:4], "big"),
            "spawn_lead_seconds": LEAD, "max_active": MAX_ACTIVE,
            "slide_checkpoint_timeout_seconds": 2.0,
        },
        "events": events,
    }
    validate_chart(chart, notes)
    analysis = {
        "candidate_count": len(candidates), "rejections": dict(rejected),
        "fast_runs": source["fast_runs"], "skeleton": source["skeleton"],
        "rejected_essential": [
            {"note_index": c.indices[0], "time": round(notes[c.indices[0]]["start"], 6), "reason": reason}
            for c, reason in rejected_essential
        ],
    }
    return chart, analysis


def metrics(chart: dict) -> dict:
    events = chart["events"]
    return {
        "events": len(events),
        "types": dict(Counter(e["type"] for e in events)),
        "nominal": len({i for e in events for i in e["note_indices"]}),
        "playable": sum(len(e["note_indices"]) if e["type"] == "slide" else 1 for e in events),
        "sizes": dict(Counter(len(e["checkpoints"]) for e in events if e["type"] == "slide")),
    }


def passage_metrics(chart: dict, a: int, b: int) -> tuple[int, int]:
    nominal = playable = 0
    for event in chart["events"]:
        for i in event["note_indices"]:
            if a <= i <= b:
                nominal += 1
                playable += event["type"] != "rub" or event["pitch_note_index"] == i
    return nominal, playable


def report(charts: dict[str, tuple[dict, dict]], timeline: dict) -> str:
    notes, duration = validate_timeline(timeline)
    all_charts = {"production": (json.loads(PRODUCTION.read_text(encoding="utf-8")), {})} | charts
    lines = [
        "# Violin MIDI 候選 chart 比較（離線估算）", "",
        "正式 chart 未覆寫。以下容量略過數是模型估算，不是實際遊玩結果。", "",
        "| 策略 | 互動（Click/Slide/Rub） | 名義選音 | 可逐音觸發 | Slide 3/4/5/6 點 |",
        "|---|---:|---:|---:|---:|",
    ]
    for name, (chart, _) in all_charts.items():
        m = metrics(chart)
        c, s, r = (m["types"].get(t, 0) for t in ("click", "slide", "rub"))
        sizes = "/".join(str(m["sizes"].get(i, 0)) for i in range(3, 7))
        lines.append(f"| {name} | {m['events']} ({c}/{s}/{r}) | {m['nominal']}/{len(notes)} ({m['nominal']/len(notes):.1%}) | {m['playable']}/{len(notes)} ({m['playable']/len(notes):.1%}) | {sizes} |")
    lines += [
        "", "## 12 段快速片語", "",
        "| 起訖秒 | 原音符 | production 名義／可逐音 | moderate 名義／可逐音 | high 名義／可逐音 |",
        "|---|---:|---:|---:|---:|",
    ]
    for a, b in fast_runs(notes):
        row = [f"{notes[a]['start']:.3f}–{notes[b]['start']:.3f}", str(b - a + 1)]
        row += [f"{x}／{y}" for chart, _ in all_charts.values() for x, y in [passage_metrics(chart, a, b)]]
        lines.append("| " + " | ".join(row) + " |")
    lines += [
        "", "## 佔用與漏生模型", "",
        "Click 2 秒、Rub 4 秒；Slide 假設 1.5 秒（快）、2.5 秒（典型）、每點耗滿 2 秒（最壞）。",
        "容量估算包含跨圈尾端互動，只模擬最多 3 個物件；無法推算錨點、遮罩、心理模式或玩家真實速度。", "",
        "六點 Slide 需要較大的安全路徑；若角色遮罩或既有互動使其無法放置，runtime 會以 unsafe_placement 略過整個片語。",
        "心理模式保留的舊互動也可能占用下一次生點名額。這兩種略過沒有可靠的離線百分比，須在遊玩測試量測。", "",
    ]
    for name, (chart, analysis) in charts.items():
        candidates = [Candidate(e["type"], tuple(e["note_indices"]), 0, 0) for e in chart["events"]]
        estimates = [occupancy(candidates, notes, duration, seconds) for seconds in (1.5, 2.5, None)]
        cross_loop = [
            f"{e['source_start_time']:.3f}s {e['type']}({len(e['note_indices'])}音)"
            for e in chart["events"]
            if e["spawn_time"] + (2 * len(e["note_indices"]) if e["type"] == "slide"
                                   else 2 if e["type"] == "click" else 4) > duration
        ]
        skip_summary = "／".join(
            f"{estimate['cap_skips']} ({estimate['cap_skips'] / len(chart['events']):.1%})"
            for estimate in estimates
        )
        lines += [
            f"### {name}", "",
            f"- 快／典型／最壞：峰值 {'／'.join(str(e['peak']) for e in estimates)}；容量略過 "
            f"{skip_summary}。",
            f"- 跨圈存活事件：{'／'.join(str(e['cross_loop']) for e in estimates)}。跨圈期間若舊互動仍存在，下一圈事件可能被略過。",
            f"- 最壞跨圈來源：{', '.join(cross_loop) if cross_loop else '無'}。",
            f"- 候選 {analysis['candidate_count']}；離線拒絕 {analysis['rejections']}。", "",
            f"- 無法保留的骨架組：{analysis['rejected_essential'] or '無'}。", "",
        ]
    lines += [
        "## 變體機制", "",
        "固定 run_seed 與 loop_index 為每個片語導出獨立 RNG。快速片語首尾完整組是固定骨架；",
        "次要片語選取與 High 的六音／兩個三音分組可變，原 MIDI 起音、索引及音高不變。",
        "每份 chart 另存 placement_seed_for_future_runtime，供未來位置隨機化重現；目前 runtime 不讀取它。",
        "Slide 仍由玩家依序通過檢查點；不施加節奏判定，故實際發聲時點可能偏離 MIDI。",
        "變體僅離線輸出；目前 runtime 仍只載入正式 chart。", "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--loop-index", type=int, default=0)
    args = parser.parse_args()
    source = SOURCE.read_bytes()
    timeline = json.loads(source)
    charts = {name: generate_chart(timeline, hashlib.sha256(source).hexdigest(), name,
                                   args.seed, args.loop_index) for name in STRATEGIES}
    suffix = "" if args.loop_index == 0 else f"_loop_{args.loop_index}"
    for name, (chart, _) in charts.items():
        output = ROOT / "data" / f"violin_interaction_chart_{name}{suffix}.json"
        output.write_text(json.dumps(chart, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{name}: {len(chart['events'])} interactions -> {output.relative_to(ROOT)}")
    output = ROOT / "data" / f"violin_interaction_chart_candidates_report{suffix}.md"
    output.write_text(report(charts, timeline), encoding="utf-8")
    print(f"Report -> {output.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
