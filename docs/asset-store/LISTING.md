# Godot Asset Store listing

What to fill in at https://store.godotengine.org (log in, then **Upload Asset**). Rules:
https://docs.godotengine.org/en/stable/community/asset_store/submitting_to_asset_store.html

## Files

Upload `godot-wingman-addon.zip` from the newest GitHub release. The release workflow builds it
in the layout the store wants: `addons/godot_wingman/` and `LICENSE` (with a copyright line)
at the root of the zip.

## Settings

| Field | Value |
|---|---|
| Asset name | Godot Wingman |
| URL slug | godot-wingman |
| Asset type | Addon |
| License | AGPL-3.0 (the same as the repository) |
| Source code | https://github.com/Godot-Wingman/godot-wingman |
| Tags | ai, mcp, editor, tools, automation, playtesting |
| Donation link | none |

**Summary:**

Let your AI assistant work in the Godot editor with you: it builds scenes, writes scripts, plays your game and fixes the bugs it finds, and you can undo every step.

**Description:**

Godot Wingman lets AI assistants such as Claude, Codex, Cursor, Gemini CLI and GitHub Copilot work inside your open Godot editor, the same way you do.

Ask for a double jump, a main menu or a new level, and the AI builds the scenes, sets properties in the Inspector and writes the scripts. Then it runs the game, presses the keys to play it, reads the errors and fixes them.

You stay in control:
- Every change goes through the editor's undo history, so Ctrl+Z works as usual.
- The Godot Wingman panel lists everything the AI changed, and one button takes the project back to how it was before any step.
- For each AI you choose how much it may do: everything, ask you before each change, or only look.
- The Chat tab lets you talk to the AIs from inside Godot. Attach files, nodes or a screenshot, and read their answers with formatting.
- Several AIs can work in the same editor and tell each other what they are changing.

To start, enable the plugin, open the Godot Wingman panel at the bottom of the editor and click Connect AI apps. It shows a one-line installer for the small companion program and connects the AI apps on your computer.

Everything runs on your computer: no accounts, no telemetry. The addon is an editor tool only and is never included in exported games, so what you make with it is yours, under any license.

Works with Godot 4.5 and newer, with GDScript and C#. Godot Wingman is a community project, not made by, affiliated with or endorsed by the Godot Foundation.

**AI usage disclosure** (mandatory; check that it is still true before submitting):

Godot Wingman was built with AI assistance: its code, tests and documentation were written with Claude Code, an AI coding assistant, under the author's direction. The screenshots are real captures of the editor and of a demo game made through Godot Wingman, which uses Kenney's free (CC0) art.

## Media

- Thumbnail (16:9, a real screenshot of the editor with the panel): `docs/asset-store/thumbnail.png`
- Screenshots: `docs/images/editor.png` (Chat tab), `docs/asset-store/changes.png` (Changes tab), `docs/asset-store/connect-ai-apps.png`, `docs/images/level.png`, `docs/images/game-coins.png`, `docs/images/game-double-jump.png`

## Versions

For each release: the version number (for example 0.4.6), the zip from that release, minimum Godot version **4.5**, and the release's changelog section from `CHANGELOG.md`.
