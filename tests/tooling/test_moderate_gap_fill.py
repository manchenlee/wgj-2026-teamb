"""Checks the offline proposal against the approved Moderate baseline."""

import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import generate_violin_chart as base
import generate_moderate_gap_fill as gap_fill


class ModerateGapFillTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = base.SOURCE.read_bytes()
        cls.notes, _ = base.validate_timeline(json.loads(cls.source))
        cls.approved = json.loads(gap_fill.APPROVED.read_text(encoding="utf-8"))

    def test_candidate_is_reproducible_and_preserves_approved_events(self):
        candidate = gap_fill.add_gap_fill(self.approved, self.notes, 2026)
        saved = json.loads(gap_fill.OUTPUT.read_text(encoding="utf-8"))
        self.assertEqual(saved, candidate)
        self.assertEqual(candidate, gap_fill.add_gap_fill(self.approved, self.notes, 2026))
        self.assertEqual(candidate["source_sha256"], hashlib.sha256(self.source).hexdigest())
        for event in self.approved["events"]:
            self.assertIn(event, candidate["events"])
        base.validate_chart(candidate, self.notes)

    def test_new_clicks_fill_visible_gaps_on_quarter_beats(self):
        candidate = gap_fill.add_gap_fill(self.approved, self.notes, 2026)
        additions = [event for event in candidate["events"] if event.get("origin") == "gap_fill"]
        self.assertGreaterEqual(len(additions), 2)
        self.assertLessEqual(len(additions), 10)
        used = {i for event in self.approved["events"] for i in event["note_indices"]}
        for event in additions:
            self.assertEqual(event["type"], "click")
            self.assertEqual(event["pitch_origin"], "unused_midi")
            self.assertNotIn(event["pitch_note_index"], used)
            self.assertEqual(event["pitch"], self.notes[event["pitch_note_index"]]["pitch"])
            beat = round(event["source_start_time"] / gap_fill.BEAT_SECONDS)
            self.assertLess(abs(event["source_start_time"] - beat * gap_fill.BEAT_SECONDS), 0.000002)
            self.assertAlmostEqual(event["source_start_time"] - event["spawn_time"], base.LEAD, places=5)
        self.assertLess(gap_fill.empty_seconds(candidate, gap_fill.EARLY),
                        gap_fill.empty_seconds(self.approved, gap_fill.EARLY))
        self.assertLess(gap_fill.empty_seconds(candidate, gap_fill.EXPIRY),
                        gap_fill.empty_seconds(self.approved, gap_fill.EXPIRY))
        self.assertLessEqual(gap_fill.peak(candidate, gap_fill.EXPIRY), 3)

    def test_visible_gap_handles_completion_expiry_pause_and_loop_seam(self):
        chart = {"loop_duration_seconds": 10.0, "events": [
            {"spawn_time": 1.0, "type": "click"},
            {"spawn_time": 9.0, "type": "rub"},
        ]}
        expiry_gaps = gap_fill.screen_gaps(chart, gap_fill.EXPIRY)
        self.assertAlmostEqual(expiry_gaps[0][0], 3.28)
        self.assertEqual(expiry_gaps[0][1], 9.0)
        early_gaps = gap_fill.screen_gaps(chart, gap_fill.EARLY)
        self.assertAlmostEqual(early_gaps[0][0], 0.42)
        self.assertEqual(early_gaps[0][1], 1.0)
        self.assertAlmostEqual(early_gaps[1][0], 1.57)
        self.assertEqual(early_gaps[1][1], 9.0)
        paused = gap_fill.empty_seconds(chart, gap_fill.EXPIRY, ((4.0, 6.0),))
        self.assertAlmostEqual(paused, 3.72)

    def test_offline_bank_variants_remain_distinct(self):
        bank = json.loads(gap_fill.BANK_OUTPUT.read_text(encoding="utf-8"))
        approved_bank = json.loads(gap_fill.BANK_SOURCE.read_text(encoding="utf-8"))
        self.assertEqual(bank["variant_count"], approved_bank["variant_count"])
        signatures = set()
        for approved, candidate in zip(approved_bank["variants"], bank["variants"]):
            self.assertTrue(all(event in candidate["events"] for event in approved["events"]))
            self.assertEqual(candidate, gap_fill.add_gap_fill(approved, self.notes, 2026))
            self.assertLessEqual(gap_fill.peak(candidate, gap_fill.EXPIRY), 3)
            self.assertLess(gap_fill.empty_seconds(candidate, gap_fill.EARLY),
                            gap_fill.empty_seconds(approved, gap_fill.EARLY))
            signatures.add(tuple(event["pitch_note_index"] for event in candidate["events"]
                                 if event.get("origin") == "gap_fill"))
        self.assertGreater(len(signatures), 1)
        self.assertEqual(len(signatures), len(approved_bank["variants"]))

    def test_official_bank_matches_approved_candidate_and_export_filters(self):
        official_path = ROOT / "data/violin_interaction_chart_moderate_gap_fill_variants.json"
        official = json.loads(official_path.read_text(encoding="utf-8"))
        candidate = json.loads(gap_fill.BANK_OUTPUT.read_text(encoding="utf-8"))
        approved_bank = json.loads(gap_fill.BANK_SOURCE.read_text(encoding="utf-8"))
        self.assertEqual(official["strategy"], "moderate_gap_fill")
        self.assertEqual(official["variant_count"], 8)
        self.assertEqual(official["source_sha256"], candidate["source_sha256"])
        for original, promoted, reference in zip(approved_bank["variants"], official["variants"], candidate["variants"]):
            self.assertEqual(promoted["generation_config"]["strategy"], "moderate_gap_fill")
            normalized = json.loads(json.dumps(promoted))
            normalized["generation_config"]["strategy"] = "moderate_gap_fill_candidate"
            self.assertEqual(normalized, reference)
            for event in original["events"]:
                self.assertIn(event, promoted["events"])
            extra = [event for event in promoted["events"] if event.get("origin") == "gap_fill"]
            self.assertEqual(len(extra), 10)
            for event in extra:
                beat = round(event["source_start_time"] / gap_fill.BEAT_SECONDS)
                self.assertLess(abs(event["source_start_time"] - beat * gap_fill.BEAT_SECONDS), 0.000002)
                self.assertAlmostEqual(event["source_start_time"] - event["spawn_time"], 0.8, places=5)
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        self.assertEqual(presets.count("data/violin_interaction_chart_moderate_gap_fill_variants.json"), 3)
        self.assertEqual(presets.count("data/violin_interaction_chart_moderate_variants.json"), 3)
        self.assertEqual(presets.count("data/violin_interaction_chart_moderate.json"), 3)


if __name__ == "__main__":
    unittest.main()
