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
| `--mode confirm` | Before every change, Godot shows an Allow / Deny dialog. |
| `--mode read-only` | Tools that change anything are hidden. The AI can only look. |
| `--toolsets edit` | Toolsets enabled at start: a profile (`minimal`, `default`, `edit`, `play`, `all`) or names like `core,scene,animation`. The AI can still switch toolsets later. |
| `--project /path` | Which editor to use when several projects are open. |

Example for Claude Desktop with confirmation and the playtesting tools:

```json
{
  "mcpServers": {
    "godot-pilot": { "command": "/path/to/godot-pilot", "args": ["--mode", "confirm", "--toolsets", "play"] }
  }
}
```

The same options can be set with the environment variables `GODOT_PILOT_MODE`, `GODOT_PILOT_TOOLSETS` and `GODOT_PILOT_PROJECT`.

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
