"""Focused offline tests for the candidate chart generator.

Run: python -B -m unittest discover -s tests/tooling -p 'test_*.py'
"""

import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import generate_violin_chart as generator


class ChartGeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source_bytes = generator.SOURCE.read_bytes()
        cls.timeline = json.loads(cls.source_bytes)
        cls.notes, cls.duration = generator.validate_timeline(cls.timeline)
        cls.source_hash = hashlib.sha256(cls.source_bytes).hexdigest()

    def build(self, strategy, loop=0, seed=2026):
        return generator.generate_chart(self.timeline, self.source_hash, strategy, seed, loop)

    def test_candidate_files_match_deterministic_generation(self):
        for strategy in generator.STRATEGIES:
            with self.subTest(strategy=strategy):
                expected, _ = self.build(strategy)
                path = ROOT / "data" / f"violin_interaction_chart_{strategy}.json"
                self.assertEqual(json.loads(path.read_text(encoding="utf-8")), expected)
                generator.validate_chart(expected, self.notes)
                self.assertNotEqual(path, generator.PRODUCTION)

    def test_loop_variants_are_reproducible_and_keep_fast_skeleton(self):
        for strategy in generator.STRATEGIES:
            first, analysis = self.build(strategy, 0)
            first_repeat, _ = self.build(strategy, 0)
            next_loop, next_analysis = self.build(strategy, 1)
            self.assertEqual(first, first_repeat)
            self.assertNotEqual(first["events"], next_loop["events"])
            self.assertNotEqual(
                first["generation_config"]["placement_seed_for_future_runtime"],
                next_loop["generation_config"]["placement_seed_for_future_runtime"],
            )
            for chart, detail in ((first, analysis), (next_loop, next_analysis)):
                selected = {i for event in chart["events"] for i in event["note_indices"]}
                for group in detail["skeleton"]:
                    self.assertTrue(set(group) <= selected, (strategy, group))
                self.assertEqual(detail["rejected_essential"], [])

    def test_fast_phrase_coverage_and_rub_exclusion(self):
        moderate, _ = self.build("moderate")
        high, _ = self.build("high")
        runs = generator.fast_runs(self.notes)
        self.assertEqual(len(runs), 12)
        fast_indices = {i for a, b in runs for i in range(a, b + 1)}
        for chart in (moderate, high):
            for event in chart["events"]:
                if event["type"] == "rub":
                    index = event["note_indices"][0]
                    self.assertNotIn(index, fast_indices)
                    self.assertGreaterEqual(self.notes[index]["end"] - self.notes[index]["start"], 0.75)
            for a, b in runs:
                nominal, playable = generator.passage_metrics(chart, a, b)
                self.assertEqual(nominal, playable)
                self.assertGreater(playable, 0)
                if chart is high:
                    self.assertEqual(playable, b - a + 1)
        for start, minimum in ((55.355, 20), (128.129, 20), (140.516, 12)):
            a, b = next((a, b) for a, b in runs if abs(self.notes[a]["start"] - start) < 0.002)
            self.assertGreaterEqual(generator.passage_metrics(moderate, a, b)[1], minimum)

    def test_slide_group_sizes_and_source_bindings(self):
        for strategy in generator.STRATEGIES:
            chart, _ = self.build(strategy)
            self.assertGreater(sum(e["type"] == "slide" for e in chart["events"]),
                               sum(e["type"] != "slide" for e in chart["events"]))
            for event in chart["events"]:
                if event["type"] != "slide":
                    self.assertEqual(len(event["note_indices"]), 1)
                    continue
                self.assertIn(len(event["checkpoints"]), range(3, 7))
                for index, checkpoint in zip(event["note_indices"], event["checkpoints"]):
                    self.assertEqual(checkpoint["note_index"], index)
                    self.assertEqual(checkpoint["pitch"], self.notes[index]["pitch"])
                    self.assertAlmostEqual(checkpoint["time"], self.notes[index]["start"], places=5)
                self.assertAlmostEqual(event["spawn_time"], event["source_start_time"] - 0.8, places=5)

    def test_moderate_density_and_capacity_model(self):
        production = json.loads(generator.PRODUCTION.read_text(encoding="utf-8"))
        moderate, _ = self.build("moderate")
        high, _ = self.build("high")
        pm = generator.metrics(production)
        mm = generator.metrics(moderate)
        hm = generator.metrics(high)
        self.assertLessEqual(mm["events"], pm["events"] + 10)
        self.assertGreater(mm["playable"], pm["playable"] * 1.5)
        self.assertGreater(hm["playable"], mm["playable"])
        for chart in (moderate, high):
            candidates = [
                generator.Candidate(e["type"], tuple(e["note_indices"]), 0, 0)
                for e in chart["events"]
            ]
            typical = generator.occupancy(candidates, self.notes, self.duration, 2.5)
            worst = generator.occupancy(candidates, self.notes, self.duration, None)
            self.assertGreaterEqual(worst["peak"], typical["peak"])
            self.assertGreater(worst["cross_loop"], 0)
            if chart is moderate:
                self.assertLessEqual(typical["peak"], 3)
            else:
                self.assertGreater(typical["peak"], 3)

    def test_validation_rejects_lost_pitch_or_partial_group(self):
        chart, _ = self.build("moderate")
        broken = copy.deepcopy(chart)
        slide = next(e for e in broken["events"] if e["type"] == "slide")
        slide["checkpoints"][0]["pitch"] = -1
        with self.assertRaises(ValueError):
            generator.validate_chart(broken, self.notes)
        broken = copy.deepcopy(chart)
        slide = next(e for e in broken["events"] if e["type"] == "slide")
        slide["note_indices"].pop(1)
        with self.assertRaises(ValueError):
            generator.validate_chart(broken, self.notes)


if __name__ == "__main__":
    unittest.main()
