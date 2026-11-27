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

Lets AI apps such as Claude, Codex, Cursor, Gemini CLI and VS Code use the Godot editor: they build scenes, write scripts, play the game with real input and fix the errors they find.

**Description:**

Godot Wingman connects AI apps to the Godot editor through the Model Context Protocol (MCP). The AI works in the open editor the way a person does: it builds scenes, changes properties in the inspector, writes GDScript and C# scripts (GDScript is checked by Godot's own parser), runs the game, plays it with real key presses, reads the errors and fixes them. Changes go through the editor's undo history, and the Godot Wingman panel lists every change, with a button to go back to how the project was before any step.

The addon is one half of Godot Wingman. The other half is a small program that your AI app starts. After enabling the plugin, open the Godot Wingman panel at the bottom of the editor and click Connect AI apps: it shows a one-line installer when the program is missing, and a Configure button for each AI app on your computer.

Everything runs on your computer. There are no accounts and no telemetry. The addon is an editor tool only and is never part of an exported game, so games you make with it are yours, under any license.

Godot Wingman is a community project. It is not made by, affiliated with or endorsed by the Godot Foundation.

**AI usage disclosure** (mandatory; check that it is still true before submitting):

Godot Wingman was built with AI assistance: its code, tests and documentation were written with Claude Code, an AI coding assistant, under the author's direction. The screenshots are real captures of the editor and of a demo game made through Godot Wingman, which uses Kenney's free (CC0) art.

## Media

- Thumbnail (16:9, a real screenshot of the editor with the panel): `docs/asset-store/thumbnail.png`
- Screenshots: `docs/images/editor.png`, `docs/asset-store/connect-ai-apps.png`, `docs/images/level.png`, `docs/images/game-coins.png`, `docs/images/game-double-jump.png`

## Versions

For each release: the version number (for example 0.4.4), the zip from that release, minimum Godot version **4.5**, and the release's changelog section from `CHANGELOG.md`.
