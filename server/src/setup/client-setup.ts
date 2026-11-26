/**
 * `godot-wingman setup`: adds Godot Wingman to the AI apps installed on this computer, so
 * the person does not have to edit configuration files by hand.
 *
 * For each app whose configuration folder exists, the godot-wingman entry is added, or
 * changed when it starts Godot Wingman in another way (for example the old executable
 * instead of the small bundle run by Bun). A copy of the file is saved next to it first
 * (".before-godot-wingman"). Claude Code is set up with its own `claude mcp` commands.
 * VS Code is set up per project, so it is only explained.
 */
import { existsSync } from "node:fs";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { BUNDLE_ASSET_NAME, type ServerLaunchCommand } from "../installation.ts";
import { getOperatingSystemDataDirectory } from "../paths.ts";
import { PRODUCT_NAME } from "../product.ts";

export interface SetupStep {
  client: string;
  /** "added", "updated", "already set up", "skipped" or "failed". */
  outcome: string;
  detail: string;
}

interface JsonClient {
  name: string;
  /** The app's folder: when it does not exist, the app is not installed. */
  folder: string;
  configFile: string;
  /** Key of the server list in the JSON file. */
  serversKey: string;
}

export interface SetupOptions {
  /** What the AI apps should run: the executable, or Bun with the bundle. */
  launch: ServerLaunchCommand;
  homeDirectory?: string;
  applicationDataDirectory?: string;
  /** Runs `claude mcp ...`; returns the exit code, or null without Claude Code. Replaced in tests. */
  runClaudeCommand?: (commandArguments: string[]) => Promise<number | null>;
}

/** The "command" and "args" entries of a settings file; "args" only when there are any. */
interface LaunchEntry {
  command: string;
  args?: string[];
}

export async function setUpAiClients(options: SetupOptions): Promise<SetupStep[]> {
  const home = options.homeDirectory ?? homedir();
  const applicationData = options.applicationDataDirectory ?? getOperatingSystemDataDirectory();
  const launchEntry = describeLaunch(options.launch);
  const steps: SetupStep[] = [];

  steps.push(await setUpCodex(join(home, ".codex"), launchEntry));
  const claudeDesktopFolder =
    process.platform === "linux" ? join(home, ".config", "Claude") : join(applicationData, "Claude");
  const jsonClients: JsonClient[] = [
    {
      name: "Claude Desktop",
      folder: claudeDesktopFolder,
      configFile: join(claudeDesktopFolder, "claude_desktop_config.json"),
      serversKey: "mcpServers",
    },
    {
      name: "Cursor",
      folder: join(home, ".cursor"),
      configFile: join(home, ".cursor", "mcp.json"),
      serversKey: "mcpServers",
    },
    {
      name: "Gemini CLI",
      folder: join(home, ".gemini"),
      configFile: join(home, ".gemini", "settings.json"),
      serversKey: "mcpServers",
    },
    {
      name: "Windsurf",
      folder: join(home, ".codeium", "windsurf"),
      configFile: join(home, ".codeium", "windsurf", "mcp_config.json"),
      serversKey: "mcpServers",
    },
  ];
  for (const client of jsonClients) {
    steps.push(await setUpJsonClient(client, launchEntry));
  }
  steps.push(await setUpClaudeCode(options));
  steps.push({
    client: "VS Code (Copilot)",
    outcome: "skipped",
    detail: `VS Code is set up per project: add .vscode/mcp.json with ${JSON.stringify({
      servers: { [PRODUCT_NAME]: { type: "stdio", ...launchEntry } },
    })}`,
  });
  return steps;
}

function describeLaunch(launch: ServerLaunchCommand): LaunchEntry {
  const command = toForwardSlashes(launch.command);
  return launch.args.length > 0 ? { command, args: launch.args.map(toForwardSlashes) } : { command };
}

/**
 * The server options (like "--mode", "confirm") of an existing entry, without the path
 * of a bundle, so switching between the bundle and the executable keeps them.
 */
function findServerOptions(existingArguments: unknown): string[] {
  if (!Array.isArray(existingArguments)) {
    return [];
  }
  return existingArguments.filter(
    (argument): argument is string => typeof argument === "string" && !argument.endsWith(BUNDLE_ASSET_NAME),
  );
}

function withServerOptions(launchEntry: LaunchEntry, serverOptions: string[]): LaunchEntry {
  const allArguments = [...(launchEntry.args ?? []), ...serverOptions];
  return allArguments.length > 0
    ? { command: launchEntry.command, args: allArguments }
    : { command: launchEntry.command };
}

async function setUpJsonClient(client: JsonClient, launchEntry: LaunchEntry): Promise<SetupStep> {
  if (!existsSync(client.folder)) {
    return { client: client.name, outcome: "skipped", detail: "not installed" };
  }
  let configuration: Record<string, unknown> = {};
  if (existsSync(client.configFile)) {
    const text = await readFile(client.configFile, "utf8");
    try {
      configuration = text.trim() === "" ? {} : (JSON.parse(text) as Record<string, unknown>);
    } catch {
      return {
        client: client.name,
        outcome: "failed",
        detail: `${client.configFile} is not plain JSON (comments?), so it was not changed. Add the entry by hand (see docs/INSTALL.md).`,
      };
    }
  }
  const servers = (configuration[client.serversKey] ?? {}) as Record<string, unknown>;
  const existingEntry = servers[PRODUCT_NAME] as Record<string, unknown> | undefined;
  const wantedEntry = withServerOptions(launchEntry, findServerOptions(existingEntry?.args));
  if (
    existingEntry !== undefined &&
    existingEntry.command === wantedEntry.command &&
    JSON.stringify(existingEntry.args ?? []) === JSON.stringify(wantedEntry.args ?? [])
  ) {
    return { client: client.name, outcome: "already set up", detail: client.configFile };
  }
  // Other keys of an existing entry (env, timeout...) are kept.
  const { args: _previousArguments, ...keptKeys } = existingEntry ?? {};
  servers[PRODUCT_NAME] = { ...keptKeys, ...wantedEntry };
  configuration[client.serversKey] = servers;
  await saveWithBackup(client.configFile, `${JSON.stringify(configuration, null, 2)}\n`);
  return {
    client: client.name,
    outcome: existingEntry === undefined ? "added" : "updated",
    detail: client.configFile,
  };
}

async function setUpCodex(codexFolder: string, launchEntry: LaunchEntry): Promise<SetupStep> {
  if (!existsSync(codexFolder)) {
    return { client: "Codex", outcome: "skipped", detail: "not installed" };
  }
  const configFile = join(codexFolder, "config.toml");
  const text = existsSync(configFile) ? await readFile(configFile, "utf8") : "";
  const describeInToml = (entry: LaunchEntry) => {
    const lines = [`command = "${entry.command}"`];
    if (entry.args) {
      lines.push(`args = [${entry.args.map((argument) => `"${argument}"`).join(", ")}]`);
    }
    return lines;
  };

  const header = new RegExp(`^\\[mcp_servers\\.["']?${PRODUCT_NAME}["']?\\][^\\n]*\\n?`, "m").exec(text);
  if (header) {
    // Replace only the command and args lines of the existing section.
    const bodyStart = header.index + header[0].length;
    const nextSectionOffset = text.slice(bodyStart).search(/^\[/m);
    const bodyEnd = nextSectionOffset === -1 ? text.length : bodyStart + nextSectionOffset;
    const bodyLines = text.slice(bodyStart, bodyEnd).split("\n");
    const isLaunchLine = (line: string) => /^(command|args)\s*=/.test(line.trim());
    const currentLaunchLines = bodyLines.filter(isLaunchLine).map((line) => line.trim());
    const currentArguments = [
      ...(currentLaunchLines.find((line) => line.startsWith("args"))?.matchAll(/"((?:[^"\\]|\\.)*)"/g) ?? []),
    ].map((match) => match[1] ?? "");
    const launchLines = describeInToml(withServerOptions(launchEntry, findServerOptions(currentArguments)));
    if (currentLaunchLines.join("\n") === launchLines.join("\n")) {
      return { client: "Codex", outcome: "already set up", detail: configFile };
    }
    const newBody = [...launchLines, ...bodyLines.filter((line) => !isLaunchLine(line))].join("\n");
    await saveWithBackup(configFile, text.slice(0, bodyStart) + newBody + text.slice(bodyEnd));
    return { client: "Codex", outcome: "updated", detail: configFile };
  }

  // Opening the editor and importing a project can take longer than Codex's default
  // 60 seconds per tool call.
  const section = [
    `[mcp_servers.${PRODUCT_NAME}]`,
    ...describeInToml(launchEntry),
    "tool_timeout_sec = 300",
    "",
  ].join("\n");
  const separator = text === "" || text.endsWith("\n\n") ? "" : text.endsWith("\n") ? "\n" : "\n\n";
  await saveWithBackup(configFile, `${text}${separator}${section}`);
  return { client: "Codex", outcome: "added", detail: configFile };
}

async function setUpClaudeCode(options: SetupOptions): Promise<SetupStep> {
  const runClaudeCommand = options.runClaudeCommand ?? runClaudeCli;
  // Removing first lets a new install replace an entry that starts it in another way.
  const removeExitCode = await runClaudeCommand(["mcp", "remove", "--scope", "user", PRODUCT_NAME]);
  if (removeExitCode === null) {
    return { client: "Claude Code", outcome: "skipped", detail: "not installed (no claude command)" };
  }
  const exitCode = await runClaudeCommand([
    "mcp",
    "add",
    "--scope",
    "user",
    PRODUCT_NAME,
    "--",
    options.launch.command,
    ...options.launch.args,
  ]);
  return exitCode === 0
    ? {
        client: "Claude Code",
        outcome: removeExitCode === 0 ? "updated" : "added",
        detail: "claude mcp add --scope user",
      }
    : {
        client: "Claude Code",
        outcome: "failed",
        detail: "claude mcp add did not work; check with: claude mcp list",
      };
}

/** Returns null when the claude command is not installed. */
async function runClaudeCli(commandArguments: string[]): Promise<number | null> {
  const claudePath = Bun.which("claude");
  if (!claudePath) {
    return null;
  }
  const claudeProcess = Bun.spawn([claudePath, ...commandArguments], { stdout: "ignore", stderr: "ignore" });
  return await claudeProcess.exited;
}

async function saveWithBackup(filePath: string, content: string): Promise<void> {
  if (existsSync(filePath)) {
    await copyFile(filePath, `${filePath}.before-godot-wingman`);
  }
  await mkdir(dirname(filePath), { recursive: true });
  await writeFile(filePath, content);
}

/** JSON and TOML both accept forward slashes on Windows, and need no escaping. */
function toForwardSlashes(path: string): string {
  return path.replaceAll("\\", "/");
}
