# Contributing to Godot Pilot

Thank you for helping! Bug reports, ideas, documentation and code are all welcome.

## Before you start

- **Bugs:** open an issue with the bug template. Include your Godot version, operating system, AI client and the tool call that failed.
- **Bigger changes or new toolsets:** open an issue first, so we can agree on the design before you spend time on it.
- **Security problems:** do not open a public issue; see [SECURITY.md](SECURITY.md).

## Setup

You need [Bun](https://bun.sh) and Godot 4.5 or newer.

```
bun install
bun test
```

`bun test` also starts a real headless Godot editor. If Godot is not found automatically, set `GODOT_PATH` to the Godot executable.

## Project layout

```
server/src/            MCP server (TypeScript, runs on Bun)
  main.ts              command line entry point
  mcp/                 MCP server, toolset switching, permission modes, tool helpers
  godot/               finding Godot, launching it, connecting to the editor
  addon/               installing the addon into projects
  docs/                Godot class reference from the installed Godot version
  tools/<toolset>/     the tools, one folder per toolset
server/guides/         guides for the AI (Markdown)
addon/godot_pilot/     the Godot editor addon (GDScript)
  bridge/              WebSocket server and request routing
  handlers/            the editor side of the tools, one file per group
tests/                 unit tests and end-to-end tests
test-project/          small Godot project used by the tests
```

## How a tool works

1. The AI calls a tool, for example `get_logs`.
2. The tool (`server/src/tools/...`) checks the input and sends a request, for example `get_logs`, to the editor.
3. The addon routes the request to a handler (`addon/godot_pilot/handlers/...`), which does the work in the editor and returns JSON.

To add a tool:

1. Define it with `defineTool` in the right toolset folder. Write the description for the AI: when to use it, what it returns, an example.
2. Add it to the toolset in `server/src/tools/toolsets.ts`.
3. If it needs the editor, add a handler method in the addon and register it in `register_methods`. New handler files go into `HANDLER_GROUP_SCRIPTS` in `plugin.gd`.
4. Add an end-to-end test in `tests/integration`.

## Code style

Write readable code.

- **Descriptive names everywhere.** No single letters or abbreviations: `node`, not `n`; `elapsedSeconds`, not `t`; `response`, not `res`. This includes loop variables and math.
- **Small functions that do one thing.** Split long functions into named steps.
- **Comments explain why**, not what. Every file starts with a short comment about its purpose.
- **TypeScript:** strict mode, no `any`. `bun run lint` (Biome) must pass; `bun run format` fixes formatting.
- **GDScript:** static types (`var speed: float`), Godot's naming conventions (`snake_case`), tabs. Everything in the addon must work in the editor only and must never affect exported games.
- **Changes in the editor go through `EditorUndoRedoManager`** so people can press Ctrl+Z.
- **Do not depend on one Godot version.** Read classes and properties from `ClassDB` at runtime; check for features with `has_method` / `ClassDB.class_exists` instead of version numbers.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org): `feat: add the animation toolset`, `fix: screenshots on macOS`, `docs: ...`, `test: ...`.
- Keep pull requests focused on one thing.
- CI must pass: lint, type check, unit tests on Windows, macOS and Linux, and end-to-end tests with several Godot versions.
- Code written with AI help is welcome. You are responsible for it like for your own: understand it, test it, keep it readable.

## License of contributions

Godot Pilot is licensed under the [GNU AGPL-3.0](LICENSE). By contributing, you agree that your contribution is licensed under the same license.

## Code of conduct

Everyone taking part must follow the [Code of Conduct](CODE_OF_CONDUCT.md).
