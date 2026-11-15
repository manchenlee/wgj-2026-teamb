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

    def test_new_click_uses_unused_midi_and_clears_slide(self):
        candidate = gap_fill.add_gap_fill(self.approved, self.notes, 2026)
        additions = [event for event in candidate["events"] if event.get("origin") == "gap_fill"]
        self.assertEqual(len(additions), 1)
        used = {i for event in self.approved["events"] for i in event["note_indices"]}
        for event in additions:
            self.assertEqual(event["type"], "click")
            self.assertEqual(event["pitch_origin"], "original_midi")
            self.assertNotIn(event["pitch_note_index"], used)
            self.assertEqual(event["pitch"], self.notes[event["pitch_note_index"]]["pitch"])
            previous = max((item for item in self.approved["events"]
                            if item["spawn_time"] < event["spawn_time"]),
                           key=lambda item: item["spawn_time"])
            self.assertGreaterEqual(event["spawn_time"] - previous["source_end_time"], 0.3)
        chosen = [base.Candidate(event["type"], tuple(event["note_indices"]), 0, 0)
                  for event in candidate["events"]]
        self.assertLessEqual(base.occupancy(chosen, self.notes,
                                            candidate["loop_duration_seconds"], 2.5)["peak"], 3)

    def test_offline_bank_variants_remain_distinct(self):
        bank = json.loads(gap_fill.BANK_OUTPUT.read_text(encoding="utf-8"))
        approved_bank = json.loads(gap_fill.BANK_SOURCE.read_text(encoding="utf-8"))
        self.assertEqual(bank["variant_count"], approved_bank["variant_count"])
        signatures = set()
        for approved, candidate in zip(approved_bank["variants"], bank["variants"]):
            self.assertTrue(all(event in candidate["events"] for event in approved["events"]))
            self.assertEqual(candidate, gap_fill.add_gap_fill(approved, self.notes, 2026))
            signatures.add(tuple(event["pitch_note_index"] for event in candidate["events"]
                                 if event.get("origin") == "gap_fill"))
        self.assertGreater(len(signatures), 1)


if __name__ == "__main__":
    unittest.main()
