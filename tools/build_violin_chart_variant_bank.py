"""Precompute runtime chart variants without changing the production chart.

Run: python -B tools/build_violin_chart_variant_bank.py
"""

import hashlib
import json
from copy import deepcopy

import generate_violin_chart as generator

VARIANT_COUNT = 8
BASE_SEED = 2026


def _vary_secondary_slide_grouping(chart: dict, notes: list[dict]) -> dict:
    """Shift one boundary between secondary Slides without changing density."""
    fast_indices = {i for a, b in generator.fast_runs(notes) for i in range(a, b + 1)}
    for position, (first, second) in enumerate(zip(chart["events"], chart["events"][1:])):
        indices = first["note_indices"] + second["note_indices"]
        if (first["type"] != "slide" or second["type"] != "slide"
                or indices != list(range(indices[0], indices[-1] + 1))
                or len(first["note_indices"]) >= 6 or len(second["note_indices"]) <= 3
                or fast_indices.intersection(indices)):
            continue
        proposal = deepcopy(chart)
        all_checkpoints = first["checkpoints"] + second["checkpoints"]
        boundary = len(first["note_indices"]) + 1
        for replacement, group in zip(proposal["events"][position:position + 2],
                                      (indices[:boundary], indices[boundary:])):
            replacement["id"] = f"slide_{group[0]:04d}"
            replacement["note_indices"] = group
            replacement["checkpoints"] = [
                checkpoint for checkpoint in all_checkpoints
                if checkpoint["note_index"] in group
            ]
            replacement["pitch_note_index"] = group[0]
            replacement["pitch"] = notes[group[0]]["pitch"]
            replacement["source_start_time"] = round(notes[group[0]]["start"], 6)
            replacement["source_end_time"] = round(max(notes[i]["end"] for i in group), 6)
            replacement["spawn_time"] = round(notes[group[0]]["start"] - generator.LEAD, 6)
        proposal["events"].sort(key=lambda item: item["spawn_time"])
        try:
            generator.validate_chart(proposal, notes)
        except ValueError:
            continue
        selected = [generator.Candidate(e["type"], tuple(e["note_indices"]), 0, 0)
                    for e in proposal["events"]]
        if generator.occupancy(selected, notes, chart["loop_duration_seconds"], 2.5)["peak"] <= 3:
            return proposal
    return chart


def build_bank(strategy: str) -> dict:
    source = generator.SOURCE.read_bytes()
    timeline = json.loads(source)
    notes, _ = generator.validate_timeline(timeline)
    source_hash = hashlib.sha256(source).hexdigest()
    variants = []
    for index in range(VARIANT_COUNT):
        chart, analysis = generator.generate_chart(timeline, source_hash, strategy, BASE_SEED, index)
        if analysis["rejected_essential"]:
            raise ValueError(f"Essential phrase lost in {strategy} variant {index}")
        if strategy == "moderate" and index % 2 == 1:
            chart = _vary_secondary_slide_grouping(chart, notes)
        variants.append(chart)
    signatures = [
        {(event["type"], tuple(event["note_indices"])) for event in chart["events"]}
        for chart in variants
    ]
    for index in range(VARIANT_COUNT):
        if len(signatures[index] ^ signatures[(index + 1) % VARIANT_COUNT]) < 10:
            raise ValueError(f"Adjacent {strategy} variants are too similar")
    return {
        "schema_version": 1,
        "strategy": strategy,
        "source_sha256": source_hash,
        "variant_count": VARIANT_COUNT,
        "variants": variants,
    }


def main() -> None:
    for strategy in generator.STRATEGIES:
        bank = build_bank(strategy)
        path = generator.ROOT / "data" / f"violin_interaction_chart_{strategy}_variants.json"
        path.write_text(json.dumps(bank, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"{strategy}: {bank['variant_count']} variants -> {path.relative_to(generator.ROOT)}")


if __name__ == "__main__":
    main()
