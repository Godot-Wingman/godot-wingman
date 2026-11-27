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

Let your AI assistant work in the Godot editor with you. Claude, Codex, Cursor, Gemini CLI or GitHub Copilot builds scenes, writes scripts, plays your game with real key presses and fixes the bugs it finds, while you watch every change in a panel, talk to it in a chat and undo any step.

**Description:**

Godot Wingman lets AI assistants such as Claude, Codex, Cursor, Gemini CLI, Windsurf and GitHub Copilot work inside your open Godot editor, the same way you do. You describe what you want in plain words, and the AI does the work in the editor in front of you.

What the AI can do:
- Build and change scenes: add nodes, set properties in the Inspector, connect signals, create resources.
- Write and edit GDScript and C# scripts. GDScript is checked by Godot's own parser before it is saved.
- Run the game and play it with real key presses and mouse clicks, take screenshots, read the errors and fix them.
- Work with animations, tilemaps, UI, 3D, shaders and audio, and export the finished game.
- Look things up in the documentation of the Godot version you have installed, instead of guessing APIs that changed.

For example: "Add a double jump to the player", "Make a main menu with Play and Quit buttons", "Build a second level with more coins", or "The game crashes when I pick up a coin, find out why."

You stay in control:
- Every change goes through the editor's undo history, so Ctrl+Z works as usual.
- The Godot Wingman panel lists everything the AI changed, and one button takes the project back to how it was before any step.
- For each AI you choose how much it may do: everything, ask you before each change (you see the full change and choose Allow or Deny), or only look.
- When you undo something or edit by hand, the AI is told, so it does not overwrite your work.

Talk to your AIs from Godot:
- The Chat tab lets you write to one AI or to all of them without leaving the editor.
- Attach project files, folders, selected nodes or a screenshot of the editor, also by dragging them in from the FileSystem and Scene docks.
- Answers show up with formatting and code blocks you can copy, and you see when each AI has read your message.
- Several AIs can work in the same editor at once and tell each other what they are changing.

Getting started:
1. Enable the plugin in Project Settings > Plugins.
2. Open the Godot Wingman panel at the bottom of the editor and click Connect AI apps.
3. If the small companion program is missing, the panel shows a one-line installer. Then click Connect next to your AI app and restart it.
4. Ask your AI to open your Godot project.

Everything runs on your computer. There are no accounts and no telemetry. The addon is an editor tool only and is never included in exported games, so what you make with it is yours, under any license.

Works with Godot 4.5 and newer, with GDScript and C#. Godot Wingman is free and open source (AGPL-3.0). It is a community project, not made by, affiliated with or endorsed by the Godot Foundation.

**AI usage disclosure** (mandatory; check that it is still true before submitting):

Godot Wingman was built with AI assistance: its code, tests and documentation were written with Claude Code, an AI coding assistant, under the author's direction. The screenshots are real captures of the editor and of a demo game made through Godot Wingman, which uses Kenney's free (CC0) art.

## Media

The store wants images of at least 1280x720.

- Thumbnail (1920x1080): `docs/asset-store/thumbnail.png`, made from `docs/asset-store/source/thumbnail.html` and a real capture of the editor.
- Screenshots: `docs/images/editor.png` (Chat tab), `docs/asset-store/changes.png` (Changes tab), `docs/asset-store/connect-ai-apps.png` (the real dialog over the editor), `docs/images/game-coins.png`, `docs/images/game-double-jump.png`

## Versions

For each release: the version number (for example 0.4.6), the zip from that release, minimum Godot version **4.5**, and the release's changelog section from `CHANGELOG.md`.
