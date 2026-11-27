# Godot Wingman addon

This is the editor half of [Godot Wingman](https://github.com/Godot-Wingman/godot-wingman), which lets AI apps (Claude, Codex, Cursor, Gemini CLI, Windsurf, VS Code and other MCP clients) use the Godot editor: build scenes, write scripts, run the game, play it with real input, read the errors and fix them. Every change goes through the editor's undo history.

The other half is a small program that your AI app starts (an MCP server). The addon talks to it over a local connection on 127.0.0.1 with a secret token.

## Getting started

1. Enable the plugin: Project > Project Settings > Plugins > Godot Wingman.
2. Open the **Godot Wingman** panel at the bottom of the editor and click **Connect AI apps**.
3. If the program is not installed yet, the window shows a one-line installer. Run it, then click **Check again**.
4. Click **Configure** next to your AI app and restart that app.

The program can also install and update this addon in a project by itself, so you only need the Asset Store copy if you prefer to start from Godot.

The addon is an editor tool only. It is never part of an exported game, and games you make with it are yours, under any license.

Godot Wingman is a community project. It is not made by, affiliated with or endorsed by the Godot Foundation. Requires Godot 4.5 or newer. License: AGPL-3.0, see LICENSE.
