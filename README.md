# Godot Pilot

**A local MCP server that lets any AI assistant use the Godot editor the way a person does.** It can see the editor, build scenes, change properties in the inspector, write and check scripts, run the game and play it with real input, then read the errors and fix them.

> **Unofficial project.** Godot Pilot is a community project. It is not made by, affiliated with or endorsed by the Godot Foundation or the Godot Engine project. "Godot" is a trademark of the Godot Foundation.

> **Status: early development (0.x).** Things change quickly and may break. Version 1.0 will only come once the project is stable and well tested by real users.

[Türkçe README](README.tr.md)

## Why another Godot MCP?

Most Godot MCP servers edit scene files in the background and can take a screenshot. That is not how a person works. Godot Pilot works **inside the running editor**:

| | Typical MCP servers | Godot Pilot |
|---|---|---|
| Changes | Edits files with a separate headless Godot; the open editor does not see them; no undo | Changes happen live in the editor and can be undone with Ctrl+Z |
| Seeing | Game screenshot | Editor window, 2D/3D viewport, game, with camera control |
| Playing | A single key press | Real input events: hold, timing, sequences; frame stepping; "wait until" |
| Godot knowledge | None: the AI guesses APIs | Class reference of **your installed Godot version** |
| Missing tool | Stuck | Runs any GDScript inside the editor as a fallback |
| Context use | All tools always loaded | Tools grouped in toolsets that the AI turns on and off |

## Features

- **Core** (always on): status, opening projects, editor state, running GDScript in the editor, Output panel and errors with stack traces, editor screenshots, version-matched Godot documentation and search, usage guides for the AI.
- **Toolsets** switched on when needed: scene, inspector, script, project settings, signals, resources, file system, viewport, playing the game, input, live game inspection, debugging, animation, tile maps, UI, 3D, shaders, audio and export. See the [roadmap](PLAN.md); not all are finished yet.
- **Permission modes**: `full`, `confirm` (an Allow / Deny dialog in Godot before each change) and `read-only`.
- **Any language**: GDScript, C# and GDExtension (Rust, C++) projects.
- **Private by design**: everything runs on your computer. No accounts, no cloud, **no telemetry**.
- **Nothing to install** besides one executable: the Godot addon is built in and installed into your project automatically.

## Quick start

1. Download the executable for your system from [Releases](https://github.com/Albis0/godot-pilot/releases).
2. Add it to your AI client. For Claude Code:
   ```
   claude mcp add godot-pilot -- /path/to/godot-pilot
   ```
   Every other client (Claude Desktop, Cursor, VS Code, Codex, Gemini CLI, Windsurf...) is covered in the **[installation guide](docs/INSTALL.md)**.
3. Ask your AI: *"Open my Godot project at C:/games/my-game and show me the main scene."*

The AI installs the addon into the project, opens the editor and connects. Requires **Godot 4.5 or newer**; tested with 4.5, 4.6 and 4.7. Older 4.x versions may work without log capture, but are not tested.

## How it works

```
AI client ──stdio──▶ godot-pilot (MCP server)
                          │  WebSocket on 127.0.0.1, secret token
                          ▼
                    Godot editor + Godot Pilot addon
                          │  Godot's own debugger channel
                          ▼
                    Your running game (only when started from the editor)
```

The addon only runs in the editor. It is never part of an exported game.

## Development

Requires [Bun](https://bun.sh) and Godot.

```
bun install
bun test              # unit tests + end-to-end tests against a real headless Godot
bun run lint          # Biome
bun run typecheck
bun run build         # standalone executables for every platform in dist/
bun run start         # run the server from source
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

[GNU AGPL-3.0](LICENSE). You may use, study, change and share Godot Pilot. If you distribute a modified version, or offer it to others over a network, you must share its source under the same license.

**Games you make with Godot Pilot are not affected.** The addon is an editor tool and is not included in exported games, so your game can use any license and be sold freely.
