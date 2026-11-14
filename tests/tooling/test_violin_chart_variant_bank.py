"""Deterministic runtime variant bank checks."""

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import build_violin_chart_variant_bank as bank_builder
import generate_violin_chart as generator


class VariantBankTests(unittest.TestCase):
    def test_shipped_banks_are_reproducible_and_preserve_skeleton(self):
        notes = json.loads(generator.SOURCE.read_text(encoding="utf-8"))["notes"]
        for strategy in generator.STRATEGIES:
            with self.subTest(strategy=strategy):
                bank = bank_builder.build_bank(strategy)
                path = ROOT / "data" / f"violin_interaction_chart_{strategy}_variants.json"
                self.assertEqual(json.loads(path.read_text(encoding="utf-8")), bank)
                self.assertEqual(bank["variants"][0], json.loads(
                    (ROOT / "data" / f"violin_interaction_chart_{strategy}.json").read_text(encoding="utf-8")
                ))
                for chart in bank["variants"]:
                    generator.validate_chart(chart, notes)
                if strategy == "moderate":
                    timeline = json.loads(generator.SOURCE.read_text(encoding="utf-8"))
                    for index in (1, 3, 5, 7):
                        raw, _ = generator.generate_chart(timeline, bank["source_sha256"], strategy, 2026, index)
                        self.assertEqual(len(bank["variants"][index]["events"]), len(raw["events"]))
                        self.assertNotEqual(bank["variants"][index]["events"], raw["events"])
                        self.assertEqual(generator.metrics(bank["variants"][index])["playable"],
                                         generator.metrics(raw)["playable"])
                signatures = [
                    {(e["type"], tuple(e["note_indices"])) for e in chart["events"]}
                    for chart in bank["variants"]
                ]
                for i in range(len(signatures)):
                    self.assertGreaterEqual(len(signatures[i] ^ signatures[(i + 1) % len(signatures)]), 10)

    def test_seed_and_loop_selection_is_reproducible_and_changes_adjacent_loops(self):
        count = bank_builder.VARIANT_COUNT
        select = lambda seed, loop: (seed - 2026 + loop) % count
        for seed in (2026, 2027, 98211):
            for loop in range(20):
                self.assertEqual(select(seed, loop), select(seed, loop))
                self.assertNotEqual(select(seed, loop), select(seed, loop + 1))
        self.assertNotEqual(select(2026, 0), select(2027, 0))


if __name__ == "__main__":
    unittest.main()
