# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com), and versions follow [Semantic Versioning](https://semver.org). Versions below 1.0 may contain breaking changes.

## [Unreleased]

### Added

- Permission mode per AI: every connected AI has its own mode (Full access, Ask first, Read-only) on its card in the Godot Wingman panel. Each AI app keeps the mode last chosen for it in the project; apps seen for the first time get the mode set under the panel's settings button. An AI is told when its mode changes. "Allow for this session" in the approval dialog now applies to that AI only.
- AIs can be renamed in the panel, for example after the model they use, so two sessions of the same app are easy to tell apart. The other AIs see the new name.
- Chat with the AIs in Godot: the panel's Chat tab writes to every AI or to one of them (click its card), with attachments (project files and folders, selected nodes, a screenshot of the editor, files from the computer, also dragged in from the FileSystem and Scene docks). Messages show who wrote to whom, when, and whether the AI has read them; AI answers are shown as formatted Markdown with code blocks that can be copied, and res:// paths open the file. The chat is kept in `.godot/godot_wingman/chat.json` and stays out of exported games.
- `wait_for_person_message`: an AI the person asked to listen to them in Godot waits there for the next chat message and gets it right away, attached pictures included. Its card says Listening. `reply_to_person`: the AI answers in the chat.
- Connect AI apps links to the download page of apps that are not installed.

### Changed

- The Godot Wingman panel is redesigned: one card per connected AI on the left, with its name, app, connection time, changes, what it is doing now and its mode; the change list and the chat in two tabs on the right. The line "connected: claude-code (server mode: full)" is gone. Messages between AIs are no longer listed among the changes.
- Connect AI apps says "Connected and ready", "Installed, not connected yet" (with a Connect button) or "Not installed on this computer" instead of "Set up" and a greyed-out Configure button.

### Fixed

- Godot could crash while quitting with the addon enabled (seen with `--quit`): the addon now stops watching the undo history before the editor frees it.

## [0.4.4] - 2026-11-27

### Added

- **Connect AI apps** in the Godot Wingman panel: a window that lists the AI apps on this computer (Codex, Claude Desktop, Claude Code, Cursor, Gemini CLI, Windsurf, VS Code), shows whether Godot Wingman is set up in each, and has a **Configure** button per app. VS Code is set up for the open project (`.vscode/mcp.json`). When the Godot Wingman program is not installed, for example when only the addon was installed, the window shows the one-line installer with a Copy button and, on Windows and macOS, a button that runs it in a new terminal window.
- `godot-wingman setup --status` shows which apps are set up without changing anything, `--client <app>` sets up one app, and `--json` prints the result for programs.
- An installed Godot Wingman notes how to start it in `installation.json` in its data folder, so the panel can find it.
- The addon folder has a short README, and its LICENSE copy starts with a copyright line.

### Changed

- `godot-wingman-addon.zip` in the releases contains `addons/godot_wingman/` and `LICENSE`, the layout of the Godot Asset Store: unzip it into the project folder.

### Fixed

- `godot-wingman setup` writes the settings of the packaged (MSIX) Claude Desktop on Windows where that version reads them, `%LOCALAPPDATA%\Packages\Claude_<id>\LocalCache\Roaming\Claude`, instead of `%APPDATA%\Claude`, which it ignores ([anthropics/claude-code#26073](https://github.com/anthropics/claude-code/issues/26073)).

## [0.4.3] - 2026-11-27

### Fixed

- `step_frames` ran one physics frame less than asked, and none for `count: 1`, because the game was paused again before the last frame was processed. An input sent while paused now reaches the game on the next stepped frame.
- `execute_game_script` with code that does not compile no longer freezes the game: Godot stopped the game in its debugger, so the tool waited until its timeout and later calls hung. The editor now compiles the code first and returns the errors right away.

## [0.4.2] - 2026-11-27

### Fixed

- `godot-wingman setup` no longer reports Gemini CLI, Windsurf or Cursor as set up when only a folder of theirs is left: such folders stay after an app is removed, and other apps create them too (Antigravity creates `~/.gemini` and `~/.codeium/windsurf`). An app now counts as installed when its command is on the PATH, its program folder exists, or it has written its own settings file.

## [0.4.1] - 2026-11-26

### Changed

- The installers use [Bun](https://bun.sh) when it is installed, or install it, and then download a 1-2 MB `godot-wingman.js` instead of the 100 MB executable. The executable is still in every release and is used when Bun cannot be (or with `GODOT_WINGMAN_USE_EXECUTABLE=1`).
- `godot-wingman setup` changes an existing entry that starts Godot Wingman another way, and keeps its options such as `--mode`.
- Updates replace the same kind of file that is installed (bundle or executable).
- The landing page is dark and lives at https://godot-wingman.pages.dev.

## [0.4.0] - 2026-11-26

### Changed

- The project is now called Godot Wingman (it was Godot Pilot). The executable is `godot-wingman`, the addon folder is `addons/godot_wingman`, and the environment variables start with `GODOT_WINGMAN_`. Installing the addon removes the old `addons/godot_pilot` folder. Versions 0.1 to 0.3 cannot update themselves to this one: install it again with the one-line installer.
- Opening the executable by hand explains what it is and offers to run setup, instead of showing an empty window.
- The Windows executable shows its name, description and version in its file properties.

## [0.3.0] - 2026-11-26

### Added

- `create_project`: the AI creates a new, empty Godot project (name, renderer) and opens it.
- One-line installers for Windows (`install/install.ps1`) and macOS/Linux (`install/install.sh`): download the newest release, check its checksum, install it and run setup. Files downloaded this way get no "unknown app" warning.
- `godot-wingman setup` adds Godot Wingman to Codex, Claude Desktop, Claude Code, Cursor, Gemini CLI and Windsurf, keeping a copy of each changed settings file. Codex gets a longer tool timeout.
- README in Spanish, Portuguese (Brazil), German, French, Russian, Simplified Chinese, Japanese and Korean.

## [0.2.0] - 2026-11-26

### Added

- News for the AI at the end of its tool results: when the person undoes or redoes a change (saying whether it was that AI's change), changes things by hand, or goes back to an earlier step in the panel.
- Several AIs in one editor: they are told when another AI connects or leaves, can message each other with the new `tell_other_ais` tool, and an AI that connects later gets the recent messages. The person can write to the AIs from the Godot Wingman panel.
- Update check: at most once a day the server reads the list of releases from GitHub and tells the AI about a newer version. The new `update_godot_wingman` tool and the `godot-wingman update` command install it after checking its SHA-256 checksum. Off with `--no-update-check`.
- Releases include a `SHA256SUMS` file.
- End-to-end tests with a C# project and a Rust GDExtension, run every night and before releases.
- The addon folder contains a copy of the license.

## [0.1.0] - 2026-11-26

### Added

- MCP server (Bun, TypeScript) shipped as a single executable per platform, with the Godot addon built in.
- Godot editor addon with a localhost WebSocket bridge, secret token and an editor registry, so the server finds running editors by itself.
- Toolsets that can be switched on and off while running, with profiles (`minimal`, `default`, `edit`, `2d`, `3d`, `play`, `all`).
- Permission modes `full`, `confirm` (Allow / Deny dialog in the editor) and `read-only`.
- Core tools: `get_status`, `launch_editor`, `install_addon`, `select_editor`, `list_toolsets`, `toggle_toolsets`, `get_editor_state`, `execute_editor_script`, `get_logs`, `take_editor_screenshot`, `get_class_docs`, `search_docs`, `get_guide`.
- Godot class reference taken from the installed Godot version, plus live class information for GDExtension and script classes.
- Guides for the AI: workflow, editor scripts, C# and GDExtension.
- Editing toolsets, all undoable with Ctrl+Z where the editor supports it:
  - `scene`: scene tree, open/create/save/close scenes, add/delete/duplicate/move/rename/select nodes, batch edits.
  - `inspector`: read and set properties with automatic type conversion and sub-properties (`shape:radius`), reset, groups.
  - `script`: create, read, edit, validate and attach GDScript and C# scripts; GDScript is checked by Godot's parser and the open Script editor is updated.
  - `project`: project settings, input map, autoloads, editor plugins.
  - `signals`: list, connect (adds the handler method to the script) and disconnect.
  - `resources`: create and edit resources and .tres files.
  - `filesystem`: list, read, write, search, move with reference updates, delete to the trash, dependencies, import options, reimport.
  - `viewport`: switch main screens and render the scene from any angle without moving the editor camera.
- Playtesting toolsets:
  - `play`: run and stop the game, pause, step frames, time scale, wait until a condition is true.
  - `input`: real input events (keys, actions, gamepad, mouse clicks and drags, typing, timed sequences, clicking UI by text), timed inside the game.
  - `game_inspect`: screenshots, frame series, live node tree and values, method calls, GDScript in the game, UI control list.
  - `debug`: game output and errors with stack traces, performance monitors.
- Building toolsets:
  - `animation`: create and edit AnimationPlayer animations (any property, 3D transforms, method calls, sounds) with type-checked keys, pose preview, AnimationTree state machines.
  - `tilemap`: TileSets from tile sheets (empty cells skipped, optional collision), placing and erasing tiles, terrain painting, levels shown as a text grid.
  - `ui`: build a whole tree of Control nodes in one step, anchor presets, theme overrides, layout check that points out broken controls.
  - `3d`: primitive meshes with material and collision, sky and sun presets, collision from imported models, measuring nodes (2D too), aiming cameras and lights.
  - `shader`: write .gdshader files with compile errors, read uniforms, set ShaderMaterial values.
  - `audio`: audio buses and effects, sound file details.
  - `export`: export presets, export template check, building the game in a separate Godot process.
- An export plugin keeps the addon out of exported games.
- `launch_editor` keeps Godot's console output in a log and shows its end when startup fails.
- `input_sequence` steps can wait for game conditions (`wait_until`), and inputs still held when a sequence ends or fails are released.
- Godot Wingman panel in the editor: connected AIs, permission mode for the project (the stricter of the panel and `--mode` applies), and a list of every change the AI made with its result, also written to `.godot/godot_wingman/activity.log`.
- Going back: before every change, the project's text files (scripts, scenes, resources, settings, import options) are remembered, and the panel can put them back to how they were before any step.
- The approval dialog of `confirm` mode shows the AI, the tool and every argument in full (code in a scrollable box), and can allow one tool for the rest of the session.
- A wrong node path suggests nodes with a similar name.
- Clear errors when the editor closes or crashes during a request.

### Fixed

- The addon really stays out of exported games now: Godot's own GDScript export step packed the addon's scripts before the export filter could skip them. The addon folder now has a `.gdignore` file, and a test checks the exported pack.
- The game bridge leaves `project.godot` as soon as the game runs, so an export made while the game runs cannot list it.
- Screenshots and renders no longer wait forever when the editor is idle and draws no new frames.
- Godot 4.7 no longer logs a Unicode error for every message the addon sends.
- Taps are held for at least two physics ticks, so games that read `is_action_just_pressed()` in `_physics_process` do not miss them on high refresh rate screens.
- `reimport_files` and `write_file` also work for files in folders the editor has not scanned yet.
