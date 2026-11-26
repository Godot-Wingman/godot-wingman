# Installing Godot Pilot

Godot Pilot is one executable file. Your AI client starts it in the background and talks to it; you never run it by hand.

## 1. Download

Get the file for your system from [Releases](https://github.com/Albis0/godot-pilot/releases):

| System | File |
|---|---|
| Windows | `godot-pilot-windows-x64.exe` |
| macOS (Apple Silicon) | `godot-pilot-macos-arm64` |
| macOS (Intel) | `godot-pilot-macos-x64` |
| Linux | `godot-pilot-linux-x64` or `godot-pilot-linux-arm64` |

Put it somewhere permanent, for example `C:\Tools\godot-pilot.exe` or `~/bin/godot-pilot`.

- **macOS:** the file is not signed yet. Allow it once with `xattr -d com.apple.quarantine ~/bin/godot-pilot` and `chmod +x ~/bin/godot-pilot`.
- **Linux:** make it executable with `chmod +x ~/bin/godot-pilot`.

Check it works: `godot-pilot doctor` lists the Godot versions it found.

## 2. Add it to your AI client

In the examples, replace `/path/to/godot-pilot` with the real path. On Windows, write paths in JSON with double backslashes (`C:\\Tools\\godot-pilot.exe`) or forward slashes (`C:/Tools/godot-pilot.exe`).

### Claude Code

```
claude mcp add godot-pilot -- /path/to/godot-pilot
```

Add `--scope user` to use it in every project.

### Claude Desktop

Settings → Developer → Edit Config, then add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "godot-pilot": { "command": "/path/to/godot-pilot" }
  }
}
```

Restart Claude Desktop.

### Cursor

`.cursor/mcp.json` in your project (or `~/.cursor/mcp.json` for all projects):

```json
{
  "mcpServers": {
    "godot-pilot": { "command": "/path/to/godot-pilot" }
  }
}
```

### VS Code (GitHub Copilot)

`.vscode/mcp.json` in your project:

```json
{
  "servers": {
    "godot-pilot": { "type": "stdio", "command": "/path/to/godot-pilot" }
  }
}
```

### OpenAI Codex CLI

`~/.codex/config.toml`:

```toml
[mcp_servers.godot-pilot]
command = "/path/to/godot-pilot"
```

### Gemini CLI

`~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "godot-pilot": { "command": "/path/to/godot-pilot" }
  }
}
```

### Windsurf

`~/.codeium/windsurf/mcp_config.json`:

```json
{
  "mcpServers": {
    "godot-pilot": { "command": "/path/to/godot-pilot" }
  }
}
```

### Any other MCP client

Godot Pilot is a standard MCP server over stdio. Configure the command `/path/to/godot-pilot` with no arguments.

## 3. Use it

Ask your AI something like: *"Open my Godot project in D:/games/platformer and tell me what is in the main scene."*

The AI calls `launch_editor`, which installs the addon into `res://addons/godot_pilot`, enables it and opens the editor. You can also install the addon yourself: `godot-pilot install /path/to/project`.

## Options

Add options as arguments (`"args": [...]` in JSON configs, after `--` for Claude Code):

| Option | Meaning |
|---|---|
| `--mode full` | Default. The AI may use every enabled tool. Editor changes can be undone with Ctrl+Z. |
| `--mode confirm` | Before every change, Godot shows a dialog with everything the AI wants to do (GDScript code in full). Choose Allow, Allow this tool for the session, or Deny. |
| `--mode read-only` | Tools that change anything are hidden. The AI can only look. |
| `--toolsets edit` | Toolsets enabled at start: a profile (`minimal`, `default`, `edit`, `2d`, `3d`, `play`, `all`) or names like `core,scene,animation`. The AI can still switch toolsets later. |
| `--project /path` | Which editor to use when several projects are open. |
| `--no-update-check` | Do not look for new versions on GitHub (see Updating). |

Example for Claude Desktop with confirmation and the playtesting tools:

```json
{
  "mcpServers": {
    "godot-pilot": { "command": "/path/to/godot-pilot", "args": ["--mode", "confirm", "--toolsets", "play"] }
  }
}
```

The same options can be set with the environment variables `GODOT_PILOT_MODE`, `GODOT_PILOT_TOOLSETS`, `GODOT_PILOT_PROJECT` and `GODOT_PILOT_NO_UPDATE_CHECK=1`.

The permission mode can also be chosen in Godot: open the **Godot Pilot** panel at the bottom of the editor. That choice is saved for the project on your computer. If it differs from `--mode`, the stricter of the two applies.

## Updating

At most once a day, Godot Pilot downloads the list of its releases from GitHub (nothing is sent with the request). When a newer version exists, the AI tells you and, if you agree, installs it with the `update_godot_pilot` tool. You can also update yourself:

```
godot-pilot update
```

The download is checked against the release's SHA-256 checksums before it replaces the old file. The new version runs after you restart your AI app; the next `launch_editor` then updates the addon in your project (restart Godot if it is open).

## Several AIs in one editor

More than one AI app can work in the same editor at once. The Godot Pilot panel shows which AI made each change. The AIs hear about each other when they connect and can tell each other what they are about to change (`tell_other_ais`). You can write to all of them from the message field at the bottom of the panel; they read it with their next step.

When you press Ctrl+Z, change something by hand, or go back to an earlier step in the panel, every connected AI is told with its next tool result.

## Godot not found?

Godot Pilot looks for Godot in the usual places (PATH, Desktop, Downloads, `~/Godot`, Program Files, Steam, /Applications...). If yours is elsewhere, set the environment variable `GODOT_PATH` to the executable, or tell the AI the path; it passes it to `launch_editor`, and the path is remembered.

## Running from source

```
git clone https://github.com/Albis0/godot-pilot
cd godot-pilot
bun install
bun run bundle-addon
```

Then use `bun` as the command and `["run", "/path/to/godot-pilot/server/src/main.ts"]` as the arguments.

## Uninstalling

Delete the executable and remove it from your AI client. In a project, delete `res://addons/godot_pilot` and turn the plugin off in Project Settings → Plugins. Godot Pilot's own files (editor registry, documentation cache) live in `%APPDATA%\godot-pilot` (Windows), `~/Library/Application Support/godot-pilot` (macOS) or `~/.local/share/godot-pilot` (Linux).
