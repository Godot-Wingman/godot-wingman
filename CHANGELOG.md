# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com), and versions follow [Semantic Versioning](https://semver.org). Versions below 1.0 may contain breaking changes.

## [Unreleased]

### Added

- MCP server (Bun, TypeScript) shipped as a single executable per platform, with the Godot addon built in.
- Godot editor addon with a localhost WebSocket bridge, secret token and an editor registry, so the server finds running editors by itself.
- Toolsets that can be switched on and off while running, with profiles (`minimal`, `default`, `edit`, `play`, `all`).
- Permission modes `full`, `confirm` (Allow / Deny dialog in the editor) and `read-only`.
- Core tools: `get_status`, `launch_editor`, `install_addon`, `select_editor`, `list_toolsets`, `toggle_toolsets`, `get_editor_state`, `execute_editor_script`, `get_logs`, `take_editor_screenshot`, `get_class_docs`, `search_docs`, `get_guide`.
- Godot class reference taken from the installed Godot version, plus live class information for GDExtension and script classes.
- Guides for the AI: workflow, editor scripts, C# and GDExtension.
