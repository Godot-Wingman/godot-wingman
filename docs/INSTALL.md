# Installing Godot Wingman

Godot Wingman comes in two forms: a small file (`godot-wingman.js`, about 1-2 MB) that runs with [Bun](https://bun.sh), or a single executable file with Bun built in (about 100 MB). Your AI client starts it in the background and talks to it; you never run it by hand.

## Install with one command (recommended)

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/Godot-Wingman/godot-wingman/main/install/install.ps1 | iex
```

**macOS and Linux** (Terminal):

```sh
curl -fsSL https://raw.githubusercontent.com/Godot-Wingman/godot-wingman/main/install/install.sh | sh
```

The script uses Bun when it is installed (version 1.3 or newer) and installs it with Bun's own installer when it is missing; then it downloads the small `godot-wingman.js`. If Bun cannot be used, it downloads the single executable instead. To always use the executable and never install Bun, set `GODOT_WINGMAN_USE_EXECUTABLE=1` first. It checks the download's SHA-256 checksum, installs it (Windows: `%LOCALAPPDATA%\Programs\godot-wingman`, added to your PATH; macOS and Linux: `~/.local/bin`) and runs `godot-wingman setup`. That adds Godot Wingman to the AI apps it finds: Codex, Claude Desktop, Claude Code, Cursor, Gemini CLI and Windsurf. A copy of every settings file it changes is kept next to it (`.before-godot-wingman`). Restart those apps afterwards.

Files downloaded by these scripts are not marked as coming from the internet, so Windows SmartScreen and macOS Gatekeeper do not warn about them. Read the scripts first if you like: [install.ps1](../install/install.ps1), [install.sh](../install/install.sh).

Then ask your AI: *"Create a new Godot game in C:/games/my-game"* or *"Open my Godot project in D:/games/platformer"*.

## Install by hand

### 1. Download

Get the file for your system from [Releases](https://github.com/Godot-Wingman/godot-wingman/releases):

| System | File |
|---|---|
| Windows | `godot-wingman-windows-x64.exe` |
| macOS (Apple Silicon) | `godot-wingman-macos-arm64` |
| macOS (Intel) | `godot-wingman-macos-x64` |
| Linux | `godot-wingman-linux-x64` or `godot-wingman-linux-arm64` |
| Any system with Bun 1.3+ | `godot-wingman.js` (run it with `bun /path/to/godot-wingman.js`; in AI client settings use Bun as the command and the file as the first argument) |

Put it somewhere permanent, for example `C:\Tools\godot-wingman.exe` or `~/bin/godot-wingman`.

- **Windows:** the file is not signed yet, so Windows may say it is an unknown app. Run `Unblock-File C:\Tools\godot-wingman.exe` once in PowerShell, or choose More info → Run anyway.
- **macOS:** the file is not signed yet. Allow it once with `xattr -d com.apple.quarantine ~/bin/godot-wingman` and `chmod +x ~/bin/godot-wingman`.
- **Linux:** make it executable with `chmod +x ~/bin/godot-wingman`.

Check it works: `godot-wingman doctor` lists the Godot versions it found.

### 2. Add it to your AI client

`godot-wingman setup` does this for every AI app it finds. You can also do it one app at a time:

- In Godot, open the **Godot Wingman** panel at the bottom and click **Connect AI apps**. It lists the AI apps on this computer, shows which ones are set up, and has a **Configure** button for each. For VS Code it writes `.vscode/mcp.json` in the open project.
- In a terminal: `godot-wingman setup --status` shows the state of every app without changing anything, and `godot-wingman setup --client cursor` sets up one app (`codex`, `claude-desktop`, `cursor`, `gemini-cli`, `windsurf`, `claude-code`, or `vscode` with `--project <Godot project folder>`).

To do it by hand:

In the examples, replace `/path/to/godot-wingman` with the real path. On Windows, write paths in JSON with double backslashes (`C:\\Tools\\godot-wingman.exe`) or forward slashes (`C:/Tools/godot-wingman.exe`).

#### Claude Code

```
claude mcp add godot-wingman -- /path/to/godot-wingman
```

Add `--scope user` to use it in every project.

#### Claude Desktop

Settings → Developer → Edit Config, then add to `claude_desktop_config.json` (the packaged Windows version reads it from `%LOCALAPPDATA%\Packages\Claude_<id>\LocalCache\Roaming\Claude`, even though Edit Config opens the one in `%APPDATA%\Claude`):

```json
{
  "mcpServers": {
    "godot-wingman": { "command": "/path/to/godot-wingman" }
  }
}
```

Restart Claude Desktop.

#### Cursor

`.cursor/mcp.json` in your project (or `~/.cursor/mcp.json` for all projects):

```json
{
  "mcpServers": {
    "godot-wingman": { "command": "/path/to/godot-wingman" }
  }
}
```

#### VS Code (GitHub Copilot)

`.vscode/mcp.json` in your project:

```json
{
  "servers": {
    "godot-wingman": { "type": "stdio", "command": "/path/to/godot-wingman" }
  }
}
```

#### OpenAI Codex CLI

`~/.codex/config.toml`:

```toml
[mcp_servers.godot-wingman]
command = "/path/to/godot-wingman"
# Opening a project can take longer than Codex's default of 60 seconds per tool call.
tool_timeout_sec = 300
```

#### Gemini CLI

`~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "godot-wingman": { "command": "/path/to/godot-wingman" }
  }
}
```

#### Windsurf

`~/.codeium/windsurf/mcp_config.json`:

```json
{
  "mcpServers": {
    "godot-wingman": { "command": "/path/to/godot-wingman" }
  }
}
```

#### Any other MCP client

Godot Wingman is a standard MCP server over stdio. Configure the command `/path/to/godot-wingman` with no arguments.

## Use it

Ask your AI something like: *"Open my Godot project in D:/games/platformer and tell me what is in the main scene."* For a new game: *"Create a new 2D Godot game in C:/games/space-shooter."* (the AI calls `create_project`).

The AI calls `launch_editor`, which installs the addon into `res://addons/godot_wingman`, enables it and opens the editor. You can also install the addon yourself: `godot-wingman install /path/to/project`.

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
    "godot-wingman": { "command": "/path/to/godot-wingman", "args": ["--mode", "confirm", "--toolsets", "play"] }
  }
}
```

The same options can be set with the environment variables `GODOT_WINGMAN_MODE`, `GODOT_WINGMAN_TOOLSETS`, `GODOT_WINGMAN_PROJECT` and `GODOT_WINGMAN_NO_UPDATE_CHECK=1`.

The permission mode can also be chosen in Godot: open the **Godot Wingman** panel at the bottom of the editor. That choice is saved for the project on your computer. If it differs from `--mode`, the stricter of the two applies.

## Updating

At most once a day, Godot Wingman downloads the list of its releases from GitHub (nothing is sent with the request). When a newer version exists, the AI tells you and, if you agree, installs it with the `update_godot_wingman` tool. You can also update yourself:

```
godot-wingman update
```

The download is checked against the release's SHA-256 checksums before it replaces the old file. The new version runs after you restart your AI app; the next `launch_editor` then updates the addon in your project (restart Godot if it is open).

## Several AIs in one editor

More than one AI app can work in the same editor at once. The Godot Wingman panel shows which AI made each change. The AIs hear about each other when they connect and can tell each other what they are about to change (`tell_other_ais`). You can write to all of them from the message field at the bottom of the panel; they read it with their next step.

When you press Ctrl+Z, change something by hand, or go back to an earlier step in the panel, every connected AI is told with its next tool result.

## Godot not found?

Godot Wingman looks for Godot in the usual places (PATH, Desktop, Downloads, `~/Godot`, Program Files, Steam, /Applications...). If yours is elsewhere, set the environment variable `GODOT_PATH` to the executable, or tell the AI the path; it passes it to `launch_editor`, and the path is remembered.

## Running from source

```
git clone https://github.com/Godot-Wingman/godot-wingman
cd godot-wingman
bun install
bun run bundle-addon
```

Then use `bun` as the command and `["run", "/path/to/godot-wingman/server/src/main.ts"]` as the arguments.

## Uninstalling

Delete the executable and remove it from your AI client. In a project, delete `res://addons/godot_wingman` and turn the plugin off in Project Settings → Plugins. Godot Wingman's own files (editor registry, documentation cache) live in `%APPDATA%\godot-wingman` (Windows), `~/Library/Application Support/godot-wingman` (macOS) or `~/.local/share/godot-wingman` (Linux).
