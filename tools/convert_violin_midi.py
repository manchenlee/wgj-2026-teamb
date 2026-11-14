"""Convert the paired violin MIDI and piano OGG into a Godot-ready timeline.

Requires mido and ffprobe. The OGG duration is authoritative for looping.
"""

import argparse
import hashlib
import json
import subprocess
from collections import defaultdict
from pathlib import Path

import mido


def _ogg_duration(path: Path) -> float:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return float(json.loads(result.stdout)["format"]["duration"])


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def convert(midi_path: Path, ogg_path: Path) -> dict:
    midi = mido.MidiFile(midi_path)
    if midi.ticks_per_beat <= 0:
        raise ValueError("SMPTE MIDI timing is not supported")

    tempo = 500_000
    tick = 0
    seconds = 0.0
    active = defaultdict(list)
    notes = []
    unmatched_note_offs = 0
    for message in mido.merge_tracks(midi.tracks):
        tick += message.time
        seconds += message.time * tempo / (midi.ticks_per_beat * 1_000_000)
        if message.type == "set_tempo":
            tempo = message.tempo
        elif message.type == "note_on" and message.velocity > 0:
            active[(message.channel, message.note)].append((seconds, message.velocity))
        elif message.type == "note_off" or (message.type == "note_on" and message.velocity == 0):
            key = (message.channel, message.note)
            if not active[key]:
                unmatched_note_offs += 1
                continue
            start, velocity = active[key].pop(0)
            notes.append({
                "start": round(start, 9),
                "end": round(seconds, 9),
                "pitch": message.note,
                "velocity": velocity,
            })

    if any(active.values()) or not notes:
        raise ValueError("MIDI has unfinished notes or no complete notes")
    notes.sort(key=lambda note: (note["start"], note["pitch"]))
    loop_duration = _ogg_duration(ogg_path)
    if abs(seconds - loop_duration) > 0.02:
        raise ValueError(f"OGG/MIDI length mismatch: {loop_duration:.6f}s / {seconds:.6f}s")
    if notes[-1]["end"] > loop_duration + 0.02:
        raise ValueError("Last MIDI note extends too far beyond the OGG loop")

    return {
        "loop_duration_seconds": loop_duration,
        "midi_duration_seconds": round(seconds, 9),
        "ticks_per_beat": midi.ticks_per_beat,
        "midi_sha256": _sha256(midi_path),
        "ogg_sha256": _sha256(ogg_path),
        "unmatched_note_offs": unmatched_note_offs,
        "notes": notes,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("midi", type=Path)
    parser.add_argument("ogg", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    timeline = convert(args.midi, args.ogg)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(timeline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"Wrote {len(timeline['notes'])} notes; MIDI {timeline['midi_duration_seconds']:.6f}s, "
        f"OGG {timeline['loop_duration_seconds']:.6f}s; "
        f"ignored {timeline['unmatched_note_offs']} unmatched note-offs"
    )


if __name__ == "__main__":
    main()
