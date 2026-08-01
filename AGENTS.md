# AGENTS.md

## Project

This is a Godot game project. Use the Godot version declared in `project.godot`: Godot `4.6`, with `GL Compatibility` rendering. The main scene is `res://scenes/Main.tscn`.

## Architecture

- `scenes/` contains Godot scenes. Screen scenes live in `scenes/screens/`; reusable UI/gameplay pieces live in `scenes/components/`.
- `scripts/core/` handles screen flow and session-level orchestration, such as title, warning, rules, gameplay session, endings, and routing.
- `scripts/gameplay/` contains gameplay state and rules: arousal model, interaction spots, dialogue choice control, ending evaluation, and shared game config.
- `scripts/ui/` contains UI controls and visual UI helpers.
- `scripts/presentation/` contains character and visual presentation logic.
- `scripts/data/` and `data/` contain dialogue and phase/character configuration resources.
- `assets/` stores art, audio, fonts, themes, and dialogue JSON.

## Naming And Style

- Use GDScript.
- File and folder names are usually `snake_case`, except scene files and globally named script classes may use `PascalCase`.
- Use `class_name PascalCase` for scripts intended to be referenced by type.
- Use `snake_case` for variables, functions, signals, and exported properties.
- Prefix private/internal helper methods and state with `_`.
- Use `UPPER_SNAKE_CASE` for constants.
- Prefer typed variables, return types, and signal arguments when practical.
- Keep scene node paths explicit with `@onready` variables near the top of scripts.
- Keep gameplay rules in gameplay/data classes, and keep UI scripts focused on presentation and input.
