/**
 * `godot-wingman setup`: adds Godot Wingman to the AI apps installed on this computer, so
 * the person does not have to edit configuration files by hand.
 *
 * For each app whose configuration folder exists, the godot-wingman entry is added when
 * it is missing (an existing entry is left alone). A copy of the file is saved next to
 * it first (".before-godot-wingman"). Claude Code is set up with its own `claude mcp add`
 * command. VS Code is set up per project, so it is only explained.
 */
import { existsSync } from "node:fs";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { getOperatingSystemDataDirectory } from "../paths.ts";
import { PRODUCT_NAME } from "../product.ts";

export interface SetupStep {
  client: string;
  /** "added", "already set up", "skipped" or "failed". */
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
  executablePath: string;
  homeDirectory?: string;
  applicationDataDirectory?: string;
  /** Runs `claude mcp add ...`; returns the exit code. Replaced in tests. */
  runClaudeCommand?: (commandArguments: string[]) => Promise<number | null>;
}

export async function setUpAiClients(options: SetupOptions): Promise<SetupStep[]> {
  const home = options.homeDirectory ?? homedir();
  const applicationData = options.applicationDataDirectory ?? getOperatingSystemDataDirectory();
  const steps: SetupStep[] = [];

  steps.push(await setUpCodex(join(home, ".codex"), options.executablePath));
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
    steps.push(await setUpJsonClient(client, options.executablePath));
  }
  steps.push(await setUpClaudeCode(options));
  steps.push({
    client: "VS Code (Copilot)",
    outcome: "skipped",
    detail: `VS Code is set up per project: add .vscode/mcp.json with {"servers": {"${PRODUCT_NAME}": {"type": "stdio", "command": "${toForwardSlashes(options.executablePath)}"}}}`,
  });
  return steps;
}

async function setUpJsonClient(client: JsonClient, executablePath: string): Promise<SetupStep> {
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
  if (servers[PRODUCT_NAME] !== undefined) {
    return { client: client.name, outcome: "already set up", detail: client.configFile };
  }
  servers[PRODUCT_NAME] = { command: toForwardSlashes(executablePath) };
  configuration[client.serversKey] = servers;
  await saveWithBackup(client.configFile, `${JSON.stringify(configuration, null, 2)}\n`);
  return { client: client.name, outcome: "added", detail: client.configFile };
}

async function setUpCodex(codexFolder: string, executablePath: string): Promise<SetupStep> {
  if (!existsSync(codexFolder)) {
    return { client: "Codex", outcome: "skipped", detail: "not installed" };
  }
  const configFile = join(codexFolder, "config.toml");
  const text = existsSync(configFile) ? await readFile(configFile, "utf8") : "";
  if (new RegExp(`^\\[mcp_servers\\.["']?${PRODUCT_NAME}["']?\\]`, "m").test(text)) {
    return { client: "Codex", outcome: "already set up", detail: configFile };
  }
  // Opening the editor and importing a project can take longer than Codex's default
  // 60 seconds per tool call.
  const section = [
    `[mcp_servers.${PRODUCT_NAME}]`,
    `command = "${toForwardSlashes(executablePath)}"`,
    "tool_timeout_sec = 300",
    "",
  ].join("\n");
  const separator = text === "" || text.endsWith("\n\n") ? "" : text.endsWith("\n") ? "\n" : "\n\n";
  await saveWithBackup(configFile, `${text}${separator}${section}`);
  return { client: "Codex", outcome: "added", detail: configFile };
}

async function setUpClaudeCode(options: SetupOptions): Promise<SetupStep> {
  const runClaudeCommand = options.runClaudeCommand ?? runClaudeCli;
  const exitCode = await runClaudeCommand([
    "mcp",
    "add",
    "--scope",
    "user",
    PRODUCT_NAME,
    "--",
    options.executablePath,
  ]);
  if (exitCode === null) {
    return { client: "Claude Code", outcome: "skipped", detail: "not installed (no claude command)" };
  }
  return exitCode === 0
    ? { client: "Claude Code", outcome: "added", detail: "claude mcp add --scope user" }
    : {
        client: "Claude Code",
        outcome: "already set up",
        detail: "claude mcp add did not add it; it probably exists already (check with: claude mcp list)",
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
