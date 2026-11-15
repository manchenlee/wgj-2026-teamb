# Clef SF2 isolated proof of concept

This scene and test use only Clef's SF2 runtime files at `addons/clef/player`.
They do not connect to the game session, MIDI timeline, or interaction audio.
The copied Clef source is MIT licensed; see `addons/clef/LICENSE.txt`.
Source revision: `kenyonxu/clef` commit `8ec3f97227272c8757dbe0f99d217dcba649bf4b`.

Set `SF2_POC_PATH` to a locally available SF2 file for the isolated probe.
The production project now includes GeneralUser GS as its default font. The
original probe used GeneralUser GS
v2.0.3 from `mrbumpy409/GeneralUser-GS` commit
`684543d5e5efaef08d02be50dcda8d552478fa60`. Its author license is in
that repository's `documentation/LICENSE.txt`; review the contained-sample
provenance note before considering redistribution.

Run the automated probe with Godot 4.6.2:

```powershell
$env:SF2_POC_PATH='C:\path\to\licensed-font.sf2'
& 'C:\path\to\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://tests/sf2_poc/sf2_poc_headless_test.gd
```

For listening, run `res://tests/sf2_poc/Sf2Poc.tscn` with the same environment
variable. Press 1 for Pizzicato Strings, 2 for Violin, or 3 for Tremolo Strings.
Hold Z, X, C, V to play G3, D4, A4, E5; release a key for Note Off. The demo
opens a blank window and writes events to the console. Try repeated presses,
long holds, and simultaneous keys. Its channel buses route to `Violin`, with
the same +10 dB gain and -6 dB hard limiter used by the current audio backend.

The probe measures API call duration and voice lifecycle. It cannot measure
audible input-to-output latency or perceived sound quality in headless mode.

## Gameplay integration

The game session defaults to the bundled GeneralUser GS SF2. Set
`VIOLIN_SF2_PATH` before launching the game, or change
`violin_soundfont_path` on the game session scene, to use another licensed
`.sf2` file. An empty or unreadable path selects the procedural fallback. The
two exported preset numbers default to 45 (Click) and 40 (Slide and Rub).
Rub uses one sustained Violin note with bow-like amplitude modulation.
The isolated proof-of-concept above still allows listening to preset 44 as a
SoundFont reference; gameplay no longer uses it. See the bundled font's `LICENSE.txt`
and `SOURCE.md` before redistribution.

The production check uses the bundled default SoundFont:

```powershell
& 'C:\path\to\Godot_v4.6.2-stable_win64_console.exe' --headless --path . --script res://tests/gameplay/violin_clef_integration_headless_test.gd
```
