# Godot Pilot

**A local MCP server that lets any AI assistant use the Godot editor the way a person does.** It can see the editor, build scenes, change properties in the inspector, write and check scripts, run the game and play it with real input, then read the errors and fix them.

> **Unofficial project.** Godot Pilot is a community project. It is not made by, affiliated with or endorsed by the Godot Foundation or the Godot Engine project. "Godot" is a trademark of the Godot Foundation.

> **Status: early development (0.x).** Things change quickly and may break. Version 1.0 will only come once the project is stable and well tested by real users.

[Türkçe README](README.tr.md)

## What it does

Godot Pilot works inside the open Godot editor, through an addon:

- **Live changes with undo.** Scene and inspector changes happen in the open editor and go through Godot's undo history, so you can press Ctrl+Z.
- **Seeing.** Screenshots of the editor window, the 2D/3D viewport and the running game, with camera control.
- **Playing.** Real input events: holding keys, timing, sequences, frame stepping and "wait until a condition is true".
- **Godot knowledge.** The class reference of the Godot version you have installed, plus the classes of your GDExtensions and scripts.
- **Fallback.** When no tool fits, the AI can run GDScript inside the editor.
- **You stay in control.** The Godot Pilot panel at the bottom of the editor lists every change the AI made and can put scripts, scenes, resources and settings back to how they were before any of them.
- **Small context.** 118 tools in 20 toolsets: scene, inspector, script, project settings, signals, resources, file system, viewport, playing the game, input, live game inspection, debugging, animation, tile maps, UI, 3D, shaders, audio and export. The AI turns on only the groups it needs. See the [changelog](CHANGELOG.md).

## Permission modes

| Mode | What the AI may do |
|---|---|
| `full` (default) | Use every enabled tool. |
| `confirm` | Look freely. Before every change, Godot shows what the AI wants to do (for GDScript, the whole code) and you click Allow or Deny. |
| `read-only` | Only look. Tools that change files, run GDScript, start the game or send input are hidden. |

Set the mode when you add Godot Pilot to your AI client (`--mode`, see the [installation guide](docs/INSTALL.md)), or in Godot in the Godot Pilot panel. If the two differ, the stricter one applies. In the dialog you can also allow one tool for the rest of the session, so a long series of similar changes does not ask every time.

## Languages

- **GDScript**: fully supported.
- **C#**: the AI can write and edit C# scripts when the project is opened with the .NET build of Godot.
- **GDExtension (Rust, C++)**: the AI sees the classes your extensions add, with their properties, methods and signals.

The end-to-end tests currently use a GDScript project.

## Privacy

Godot Pilot runs on your computer and sends nothing anywhere: no accounts, no cloud, **no telemetry**.

Your AI client is a different matter: what the AI reads through Godot Pilot (code, scenes, screenshots, errors) goes to the AI model you use, under that provider's rules. Only a model running on your own computer keeps everything local.

## Quick start

1. Download the executable for your system from [Releases](https://github.com/Albis0/godot-pilot/releases).
2. Add it to your AI client. For Claude Code:
   ```
   claude mcp add godot-pilot -- /path/to/godot-pilot
   ```
   Every other client (Claude Desktop, Cursor, VS Code, Codex, Gemini CLI, Windsurf...) is covered in the **[installation guide](docs/INSTALL.md)**.
3. Ask your AI: *"Open my Godot project at C:/games/my-game and show me the main scene."*

The AI installs the addon into the project, opens the editor and connects. Requires **Godot 4.5 or newer**. Every change is tested with Godot 4.5.2, 4.6.3 and 4.7.2.

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
bun run test          # unit tests + end-to-end tests against a real headless Godot
bun run test:unit     # only the unit tests, no Godot needed
bun run lint          # Biome
bun run typecheck
bun run build         # standalone executables for every platform in dist/
bun run start         # run the server from source
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

[GNU AGPL-3.0](LICENSE). You may use, study, change and share Godot Pilot. If you distribute a modified version, or offer it to others over a network, you must share its source under the same license.

**Games you make with Godot Pilot are not affected.** The addon is an editor tool and is not included in exported games, so your game can use any license and be sold freely.
