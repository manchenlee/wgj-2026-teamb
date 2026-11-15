"""Offline Moderate + Gap Fill proposal; never changes the approved bank.

Run: python -B tools/generate_moderate_gap_fill.py [--seed 2026]
"""

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


def add_gap_fill(chart: dict, notes: list[dict], seed: int, *,
                 min_gap: float = 3.0, max_per_gap: int = 1,
                 max_total: int = 3, slide_clearance: float = 0.3) -> dict:
    """Use only unused MIDI notes; no inferred harmony means no invented pitches."""
    result = deepcopy(chart)
    result["generation_config"].update({
        "strategy": "moderate_gap_fill_candidate", "gap_fill_seed": seed,
        "gap_fill_min_gap_seconds": min_gap, "gap_fill_max_per_gap": max_per_gap,
        "gap_fill_max_total": max_total, "gap_fill_slide_clearance_seconds": slide_clearance,
    })
    used = {i for event in chart["events"] for i in event["note_indices"]}
    fast = {i for a, b in base.fast_runs(notes) for i in range(a, b + 1)}
    additions = []
    for left, right in zip(chart["events"], chart["events"][1:]):
        gap = right["spawn_time"] - left["spawn_time"]
        if gap < min_gap or len(additions) >= max_total:
            continue
        eligible = []
        for index, note in enumerate(notes):
            spawn = note["start"] - base.LEAD
            if index in used or index in fast or not (0 <= spawn < chart["loop_duration_seconds"]):
                continue
            if spawn - left["spawn_time"] < 1.45 or right["spawn_time"] - spawn < 1.45:
                continue
            if spawn < left["source_end_time"] + slide_clearance:
                continue
            if note["end"] > right["source_start_time"] - slide_clearance:
                continue
            # A click should be a short, distinct note, not a hidden part of a run.
            if not 0.16 <= note["end"] - note["start"] <= 0.65:
                continue
            nearby = [item for item in notes if abs(item["start"] - note["start"]) <= 0.7]
            if len(nearby) >= 5 and sum(
                    b["start"] - a["start"] <= 0.25
                    for a, b in zip(nearby, nearby[1:])) >= 4:
                continue
            eligible.append(index)
        rng = base._rng(seed, int(chart["generation_config"]["loop_index"]),
                        f"gap_fill:{left['id']}:{right['id']}")
        scores = {i: abs((notes[i]["start"] - base.LEAD) -
                         (left["spawn_time"] + right["spawn_time"]) / 2) +
                  rng.uniform(-0.12, 0.12) for i in eligible}
        eligible.sort(key=lambda i: (scores[i], i))
        for index in eligible[:max_per_gap]:
            note = notes[index]
            if any(abs(note["start"] - base.LEAD - earlier["spawn_time"]) < 1.45
                   for earlier in additions):
                continue
            candidate = {
                "id": f"gap_fill_click_{index:04d}", "type": "click",
                "spawn_time": round(note["start"] - base.LEAD, 6),
                "source_start_time": round(note["start"], 6),
                "source_end_time": round(note["end"], 6),
                "pitch": note["pitch"], "pitch_note_index": index,
                "note_indices": [index], "checkpoints": [],
                "origin": "gap_fill", "pitch_origin": "original_midi",
            }
            proposal = deepcopy(result)
            proposal["events"].append(candidate)
            proposal["events"].sort(key=lambda event: event["spawn_time"])
            chosen = [base.Candidate(e["type"], tuple(e["note_indices"]), 0, 0)
                      for e in proposal["events"]]
            if base.occupancy(chosen, notes, chart["loop_duration_seconds"], 2.5)["peak"] > 3:
                continue
            result = proposal
            additions.append(candidate)
            if len(additions) >= max_total:
                break
    base.validate_chart(result, notes)
    assert all(event in result["events"] for event in chart["events"])
    return result


def _long_gaps(chart: dict, threshold: float = 3.0) -> list[tuple[float, float, float]]:
    events = chart["events"]
    return [(a["spawn_time"], b["spawn_time"], b["spawn_time"] - a["spawn_time"])
            for a, b in zip(events, events[1:])
            if b["spawn_time"] - a["spawn_time"] >= threshold]


def make_report(approved: dict, candidate: dict, notes: list[dict]) -> str:
    lines = ["# Moderate + Gap Fill 離線候選分析", "",
             "此候選版未載入遊戲，也未覆寫已核准 Moderate 圖表或變體庫。所有新增音高均來自原始 MIDI；沒有新增推測的過門音。", "",
             "| 指標 | 已核准 Moderate | Gap Fill 候選 |", "|---|---:|---:|"]
    a, b = base.metrics(approved), base.metrics(candidate)
    for title, key in (("互動總數", "events"), ("可逐音觸發機會", "playable")):
        lines.append(f"| {title} | {a[key]} | {b[key]} |")
    for kind in ("click", "slide", "rub"):
        lines.append(f"| {kind.title()} | {a['types'].get(kind, 0)} | {b['types'].get(kind, 0)} |")
    lines += ["", "## 新增 Click", "", "| 時間（生成／MIDI） | 音高 | 原始 MIDI 索引 | 來源 |",
              "|---|---:|---:|---|"]
    added = [e for e in candidate["events"] if e.get("origin") == "gap_fill"]
    for event in added:
        lines.append(f"| {event['spawn_time']:.3f}／{event['source_start_time']:.3f} 秒 | {event['pitch']} | {event['pitch_note_index']} | {event['pitch_origin']} |")
    lines += ["", "## 仍保留的長互動間隔（生成時間差 ≥3 秒）", "",
              "| 已核准 Moderate | Gap Fill 候選 |", "|---|---|"]
    for label, chart in (("已核准", approved), ("候選", candidate)):
        gaps = _long_gaps(chart)
        text = "、".join(f"{start:.2f}–{end:.2f}（{length:.2f} 秒）" for start, end, length in gaps)
        lines.append(f"| {label} | {text or '無'} |")
    lines += ["", "## 佔用量估計", "",
              "Click 以 2 秒、Rub 以 4 秒；Slide 的快速／典型／最壞完成時間分別為 1.5 秒／2.5 秒／每檢查點 2 秒。估計只涵蓋同時數上限，沒有模擬玩家位置、遮罩或心理模式。", "",
              "| 情境 | 已核准峰值／上限略過 | 候選峰值／上限略過 |",
              "|---|---:|---:|"]
    for label, seconds in (("快速", 1.5), ("典型", 2.5), ("最壞", None)):
        values = []
        for chart in (approved, candidate):
            events = [base.Candidate(e["type"], tuple(e["note_indices"]), 0, 0)
                      for e in chart["events"]]
            estimate = base.occupancy(events, notes, chart["loop_duration_seconds"], seconds)
            values.append(f"{estimate['peak']}／{estimate['cap_skips']}")
        lines.append(f"| {label} | {' | '.join(values)} |")
    lines += ["", "## 風險與變化", "",
              "- 原有 Slide 事件、檢查點、時間與排序內容保持相同；新增 Click 避開快速 MIDI 連音、Slide 的來源結尾，以及相鄰互動生成點。",
              "- 典型完成時間的同時數不超過 3；最壞情境仍可能因慢速完成與場上位置造成略過。位置遮罩與心理模式需在實際遊戲試玩確認。",
              "- 72.77–75.10 秒是真實 MIDI 休止。只有單聲部小提琴資料，無法確認和聲；因此沒有臆造音階過門音。",
              "- 同一 seed 與 loop_index 會得到相同選擇。另輸出 8 個離線候選變體供比較；執行時仍載入已核准 Moderate 變體庫。", "",
              "## 驗證範圍", "",
              "產生器逐項驗證來源 MIDI 音高、0.8 秒生成提前量、事件順序、Slide 的 3–6 個原始檢查點、原圖表事件完整保留與典型同時數上限。Godot 執行時 schema 另由 `midi_chart_candidates_headless_test.gd` 驗證；實際位置與玩家速度仍需遊玩觀察。", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--min-gap", type=float, default=3.0)
    parser.add_argument("--max-per-gap", type=int, default=1)
    parser.add_argument("--max-total", type=int, default=3)
    args = parser.parse_args()
    if args.min_gap <= 0 or not 0 <= args.max_per_gap <= 2 or args.max_total < 0:
        parser.error("Use positive min-gap, max-per-gap 0–2, and nonnegative max-total")
    source = base.SOURCE.read_bytes()
    notes, _ = base.validate_timeline(json.loads(source))
    approved = json.loads(APPROVED.read_text(encoding="utf-8"))
    if approved["source_sha256"] != hashlib.sha256(source).hexdigest():
        raise ValueError("Approved Moderate source hash differs from MIDI timeline")
    base.validate_chart(approved, notes)
    candidate = add_gap_fill(approved, notes, args.seed, min_gap=args.min_gap,
                             max_per_gap=args.max_per_gap, max_total=args.max_total)
    bank = json.loads(BANK_SOURCE.read_text(encoding="utf-8"))
    if bank["source_sha256"] != approved["source_sha256"]:
        raise ValueError("Approved bank source hash differs from timeline")
    variants = [add_gap_fill(variant, notes, args.seed, min_gap=args.min_gap,
                             max_per_gap=args.max_per_gap, max_total=args.max_total)
                for variant in bank["variants"]]
    if candidate != variants[0]:
        raise ValueError("Standalone Moderate candidate differs from loop 0")
    candidate_bank = {
        "schema_version": 1, "strategy": "moderate_gap_fill_candidate",
        "source_sha256": approved["source_sha256"],
        "variant_count": len(variants), "variants": variants,
    }
    OUTPUT.write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    BANK_OUTPUT.write_text(json.dumps(candidate_bank, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    variation = "\n".join(
        f"- 變體 {i}: +{len(variant['events']) - len(bank['variants'][i]['events'])} Click；"
        f"MIDI 索引 {', '.join(str(e['pitch_note_index']) for e in variant['events'] if e.get('origin') == 'gap_fill') or '無'}"
        for i, variant in enumerate(variants))
    report = make_report(approved, candidate, notes)
    report += "\n## 離線迴圈變體\n\n" + variation + "\n"
    REPORT.write_text(report, encoding="utf-8")
    print(f"Added {len(candidate['events']) - len(approved['events'])} Click events: {OUTPUT.relative_to(base.ROOT)}")


if __name__ == "__main__":
    main()
