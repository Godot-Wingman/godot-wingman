# Security policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's private reporting instead: open the **Security** tab of this repository and click **Report a vulnerability**. You will get an answer as soon as possible, usually within a week.

## Supported versions

Godot Pilot is in early development (0.x). Only the latest release receives fixes.

## Security model

Knowing what Godot Pilot is designed to do helps to tell a bug from a feature:

- **The AI can run any code inside the Godot editor** (`execute_editor_script`). This is intentional: it gives the AI the same power as a person sitting at the editor. Use the `confirm` or `read-only` permission mode if you want to limit it.
- **The editor bridge only listens on 127.0.0.1.** Other computers cannot connect.
- **Every connection must present a random token** that the editor writes to a file in the user's data folder. Other users of the same computer cannot read that file on a normally configured system.
- **The addon never runs in exported games.**
- **Godot Pilot sends nothing about you or your project over the internet.** It has no telemetry and no online services. Its only internet access is downloading the list of its own releases from GitHub at most once a day (`--no-update-check` turns it off), and the new version when you agree to update; downloads are checked against the release's SHA-256 checksums. Your AI client is separate: what the AI reads through Godot Pilot goes to the AI model you use.
- **`read-only` mode** hides every tool that changes files, runs GDScript, starts the game or sends input. **`confirm` mode** shows every change, including the full GDScript code, in a dialog in the editor before it runs.

Things we consider vulnerabilities: connecting to the bridge without the token, reaching the bridge from another computer, the addon running in an exported game, bypassing the `read-only` or `confirm` modes, or Godot Pilot sending data anywhere.
