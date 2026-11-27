/**
 * `godot-wingman setup`: adds Godot Wingman to the AI apps installed on this computer, so
 * the person does not have to edit configuration files by hand.
 *
 * For each app that is installed, the godot-wingman entry is added, or
 * changed when it starts Godot Wingman in another way (for example the old executable
 * instead of the small bundle run by Bun). A copy of the file is saved next to it first
 * (".before-godot-wingman"). Claude Code is set up with its own `claude mcp` commands.
 * VS Code is set up per project: with a project folder it gets .vscode/mcp.json there,
 * otherwise it is only explained.
 *
 * The Configure buttons in the editor panel use the same code: they ask for the state of
 * every app without changing anything (`checkOnly`), and set up one app (`onlyClientId`).
 */
import { existsSync, readdirSync } from "node:fs";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { BUNDLE_ASSET_NAME, type ServerLaunchCommand } from "../installation.ts";
import { getOperatingSystemDataDirectory } from "../paths.ts";
import { PRODUCT_NAME } from "../product.ts";

export interface SetupStep {
  /** Short name used by `setup --client`, like "claude-desktop". */
  id: string;
  client: string;
  /**
   * "added", "updated", "already set up", "skipped" (not installed) or "failed".
   * With `checkOnly`: "would add" or "would update" instead of "added" or "updated".
   */
  outcome: string;
  detail: string;
}

/** The apps that setup knows, in the order they are set up and shown. */
export const AI_CLIENTS = [
  { id: "codex", name: "Codex" },
  { id: "claude-desktop", name: "Claude Desktop" },
  { id: "cursor", name: "Cursor" },
  { id: "gemini-cli", name: "Gemini CLI" },
  { id: "windsurf", name: "Windsurf" },
  { id: "claude-code", name: "Claude Code" },
  { id: "vscode", name: "VS Code (Copilot)" },
] as const;

export type AiClientId = (typeof AI_CLIENTS)[number]["id"];

export function isAiClientId(text: string): text is AiClientId {
  return AI_CLIENTS.some((client) => client.id === text);
}

interface JsonClient {
  id: AiClientId;
  name: string;
  /**
   * Paths that exist only while the app is installed: its program folder, or a file it
   * writes on first use. A bare settings folder is not enough, because it stays after the
   * app is removed, and other apps create the same folders (Antigravity creates ~/.gemini
   * and ~/.codeium/windsurf).
   */
  installedMarkers: string[];
  /** The app's command; when it is on the PATH, the app is installed. */
  commandName?: string;
  configFile: string;
  /** Key of the server list in the JSON file. */
  serversKey: string;
  /** Keys a new entry needs besides command and args, like VS Code's "type". */
  extraEntryKeys?: Record<string, string>;
}

export interface SetupOptions {
  /** What the AI apps should run: the executable, or Bun with the bundle. */
  launch: ServerLaunchCommand;
  homeDirectory?: string;
  applicationDataDirectory?: string;
  /** %LOCALAPPDATA% on Windows, where Microsoft Store apps keep their files. */
  localApplicationDataDirectory?: string;
  /** Runs `claude mcp ...`; returns the exit code, or null without Claude Code. Replaced in tests. */
  runClaudeCommand?: (commandArguments: string[]) => Promise<number | null>;
  /** Finds a command on the PATH; returns null when it is not there. Replaced in tests. */
  findCommand?: (commandName: string) => string | null;
  /** The folders an app named like this is installed to. Replaced in tests. */
  findProgramFolders?: (applicationName: string) => string[];
  /** Set up only this app. */
  onlyClientId?: AiClientId;
  /** Report what would change, without changing anything. */
  checkOnly?: boolean;
  /** The Godot project folder; VS Code is set up there, in .vscode/mcp.json. */
  projectPath?: string;
}

/** The "command" and "args" entries of a settings file; "args" only when there are any. */
interface LaunchEntry {
  command: string;
  args?: string[];
}

export async function setUpAiClients(options: SetupOptions): Promise<SetupStep[]> {
  const home = options.homeDirectory ?? homedir();
  const applicationData = options.applicationDataDirectory ?? getOperatingSystemDataDirectory();
  const findCommand = options.findCommand ?? ((commandName: string) => Bun.which(commandName));
  const findProgramFolders =
    options.findProgramFolders ?? ((applicationName: string) => listProgramFolders(applicationName, home));
  const launchEntry = describeLaunch(options.launch);
  const checkOnly = options.checkOnly === true;

  const claudeDesktopFolder =
    process.platform === "linux"
      ? join(home, ".config", "Claude")
      : (findMicrosoftStoreClaudeFolder(options.localApplicationDataDirectory ?? process.env.LOCALAPPDATA) ??
        join(applicationData, "Claude"));
  const cursorConfigFile = join(home, ".cursor", "mcp.json");
  const geminiConfigFile = join(home, ".gemini", "settings.json");
  const windsurfConfigFile = join(home, ".codeium", "windsurf", "mcp_config.json");
  const jsonClients: JsonClient[] = [
    {
      id: "claude-desktop",
      name: "Claude Desktop",
      installedMarkers: [claudeDesktopFolder],
      configFile: join(claudeDesktopFolder, "claude_desktop_config.json"),
      serversKey: "mcpServers",
    },
    {
      id: "cursor",
      name: "Cursor",
      installedMarkers: [cursorConfigFile, ...findProgramFolders("Cursor")],
      commandName: "cursor",
      configFile: cursorConfigFile,
      serversKey: "mcpServers",
    },
    {
      id: "gemini-cli",
      name: "Gemini CLI",
      // Gemini CLI writes settings.json when it is first set up.
      installedMarkers: [geminiConfigFile],
      commandName: "gemini",
      configFile: geminiConfigFile,
      serversKey: "mcpServers",
    },
    {
      id: "windsurf",
      name: "Windsurf",
      installedMarkers: [windsurfConfigFile, ...findProgramFolders("Windsurf")],
      commandName: "windsurf",
      configFile: windsurfConfigFile,
      serversKey: "mcpServers",
    },
  ];
  const isInstalled = (client: JsonClient) =>
    client.installedMarkers.some((marker) => existsSync(marker)) ||
    (client.commandName !== undefined && findCommand(client.commandName) !== null);
  const setUpWhenInstalled = async (client: JsonClient): Promise<SetupStep> =>
    isInstalled(client)
      ? await setUpJsonClient(client, launchEntry, checkOnly)
      : { id: client.id, client: client.name, outcome: "skipped", detail: "not installed" };

  const setUpClient: Record<AiClientId, () => Promise<SetupStep>> = {
    codex: () => setUpCodex(join(home, ".codex"), launchEntry, checkOnly),
    "claude-desktop": () => setUpWhenInstalled(jsonClients[0] as JsonClient),
    cursor: () => setUpWhenInstalled(jsonClients[1] as JsonClient),
    "gemini-cli": () => setUpWhenInstalled(jsonClients[2] as JsonClient),
    windsurf: () => setUpWhenInstalled(jsonClients[3] as JsonClient),
    "claude-code": () => setUpClaudeCode(options),
    vscode: async () => {
      const projectPath = options.projectPath;
      if (projectPath === undefined) {
        return {
          id: "vscode",
          client: "VS Code (Copilot)",
          outcome: "skipped",
          detail: `VS Code is set up per project: add .vscode/mcp.json with ${JSON.stringify({
            servers: { [PRODUCT_NAME]: { type: "stdio", ...launchEntry } },
          })}`,
        };
      }
      return await setUpWhenInstalled({
        id: "vscode",
        name: "VS Code (Copilot)",
        installedMarkers: findProgramFolders("Microsoft VS Code"),
        commandName: "code",
        configFile: join(projectPath, ".vscode", "mcp.json"),
        serversKey: "servers",
        extraEntryKeys: { type: "stdio" },
      });
    },
  };

  const steps: SetupStep[] = [];
  for (const client of AI_CLIENTS) {
    if (options.onlyClientId === undefined || options.onlyClientId === client.id) {
      steps.push(await setUpClient[client.id]());
    }
  }
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

/**
 * The settings folder of the packaged (MSIX) Claude Desktop on Windows. Packaged apps get
 * their own copy of %APPDATA%, so this version reads its settings from
 * %LOCALAPPDATA%\Packages\Claude_<id>\LocalCache\Roaming\Claude instead
 * (https://github.com/anthropics/claude-code/issues/26073).
 */
function findMicrosoftStoreClaudeFolder(localApplicationData: string | undefined): string | undefined {
  if (process.platform !== "win32" || localApplicationData === undefined) {
    return undefined;
  }
  const packagesFolder = join(localApplicationData, "Packages");
  if (!existsSync(packagesFolder)) {
    return undefined;
  }
  return readdirSync(packagesFolder)
    .filter((folderName) => folderName.startsWith("Claude_"))
    .map((folderName) => join(packagesFolder, folderName, "LocalCache", "Roaming", "Claude"))
    .find((folder) => existsSync(folder));
}

/** Where desktop apps install themselves: per user on Windows, the Applications folders on macOS. */
function listProgramFolders(applicationName: string, home: string): string[] {
  if (process.platform === "win32") {
    const localApplicationData = process.env.LOCALAPPDATA ?? join(home, "AppData", "Local");
    return [join(localApplicationData, "Programs", applicationName)];
  }
  if (process.platform === "darwin") {
    return [
      join("/Applications", `${applicationName}.app`),
      join(home, "Applications", `${applicationName}.app`),
    ];
  }
  // On Linux the command on the PATH is the sign.
  return [];
}

async function setUpJsonClient(
  client: JsonClient,
  launchEntry: LaunchEntry,
  checkOnly: boolean,
): Promise<SetupStep> {
  let configuration: Record<string, unknown> = {};
  if (existsSync(client.configFile)) {
    const text = await readFile(client.configFile, "utf8");
    try {
      configuration = text.trim() === "" ? {} : (JSON.parse(text) as Record<string, unknown>);
    } catch {
      return {
        id: client.id,
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
    return { id: client.id, client: client.name, outcome: "already set up", detail: client.configFile };
  }
  if (checkOnly) {
    return {
      id: client.id,
      client: client.name,
      outcome: existingEntry === undefined ? "would add" : "would update",
      detail: client.configFile,
    };
  }
  // Other keys of an existing entry (env, timeout...) are kept.
  const { args: _previousArguments, ...keptKeys } = existingEntry ?? {};
  servers[PRODUCT_NAME] = { ...client.extraEntryKeys, ...keptKeys, ...wantedEntry };
  configuration[client.serversKey] = servers;
  await saveWithBackup(client.configFile, `${JSON.stringify(configuration, null, 2)}\n`);
  return {
    id: client.id,
    client: client.name,
    outcome: existingEntry === undefined ? "added" : "updated",
    detail: client.configFile,
  };
}

async function setUpCodex(
  codexFolder: string,
  launchEntry: LaunchEntry,
  checkOnly: boolean,
): Promise<SetupStep> {
  const step = (outcome: string, detail: string): SetupStep => ({
    id: "codex",
    client: "Codex",
    outcome,
    detail,
  });
  if (!existsSync(codexFolder)) {
    return step("skipped", "not installed");
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
      return step("already set up", configFile);
    }
    if (checkOnly) {
      return step("would update", configFile);
    }
    const newBody = [...launchLines, ...bodyLines.filter((line) => !isLaunchLine(line))].join("\n");
    await saveWithBackup(configFile, text.slice(0, bodyStart) + newBody + text.slice(bodyEnd));
    return step("updated", configFile);
  }
  if (checkOnly) {
    return step("would add", configFile);
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
  return step("added", configFile);
}

async function setUpClaudeCode(options: SetupOptions): Promise<SetupStep> {
  const runClaudeCommand = options.runClaudeCommand ?? runClaudeCli;
  const step = (outcome: string, detail: string): SetupStep => ({
    id: "claude-code",
    client: "Claude Code",
    outcome,
    detail,
  });
  if (options.checkOnly === true) {
    // `claude mcp get` succeeds when an entry with this name exists.
    const getExitCode = await runClaudeCommand(["mcp", "get", PRODUCT_NAME]);
    if (getExitCode === null) {
      return step("skipped", "not installed (no claude command)");
    }
    return getExitCode === 0
      ? step("already set up", "claude mcp get")
      : step("would add", "claude mcp add --scope user");
  }
  // Removing first lets a new install replace an entry that starts it in another way.
  const removeExitCode = await runClaudeCommand(["mcp", "remove", "--scope", "user", PRODUCT_NAME]);
  if (removeExitCode === null) {
    return step("skipped", "not installed (no claude command)");
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
    ? step(removeExitCode === 0 ? "updated" : "added", "claude mcp add --scope user")
    : step("failed", "claude mcp add did not work; check with: claude mcp list");
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
