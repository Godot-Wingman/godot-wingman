/**
 * Tests of `godot-wingman setup` (server/src/setup/client-setup.ts) in a fake home folder.
 */
import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ServerLaunchCommand } from "../../server/src/installation.ts";
import { type SetupStep, setUpAiClients } from "../../server/src/setup/client-setup.ts";

const EXECUTABLE = "C:\\Tools\\godot-wingman.exe";
let home = "";
let applicationData = "";
/** The commands the fake computer has on its PATH. */
let commandsOnPath = new Map<string, string>();

beforeEach(async () => {
  home = await mkdtemp(join(tmpdir(), "godot-wingman-setup-"));
  applicationData = join(home, "AppData");
  commandsOnPath = new Map();
});

afterEach(async () => {
  await rm(home, { recursive: true, force: true });
});

const BUN = "C:\\Users\\me\\.bun\\bin\\bun.exe";
const BUNDLE = "C:\\Users\\me\\AppData\\Local\\Programs\\godot-wingman\\godot-wingman.js";
const EXECUTABLE_LAUNCH: ServerLaunchCommand = { command: EXECUTABLE, args: [] };
const BUNDLE_LAUNCH: ServerLaunchCommand = { command: BUN, args: [BUNDLE] };

function runSetup(
  claudeExitCode: number | null = null,
  launch: ServerLaunchCommand = EXECUTABLE_LAUNCH,
): Promise<SetupStep[]> {
  return setUpAiClients({
    launch,
    homeDirectory: home,
    applicationDataDirectory: applicationData,
    localApplicationDataDirectory: join(home, "LocalAppData"),
    runClaudeCommand: async () => claudeExitCode,
    findCommand: (commandName) => commandsOnPath.get(commandName) ?? null,
    findProgramFolders: () => [],
  });
}

function outcomeOf(steps: SetupStep[], client: string): string | undefined {
  return steps.find((step) => step.client === client)?.outcome;
}

test("apps that are not installed are skipped and nothing is written", async () => {
  const steps = await runSetup();
  expect(outcomeOf(steps, "Codex")).toBe("skipped");
  expect(outcomeOf(steps, "Cursor")).toBe("skipped");
  expect(outcomeOf(steps, "Claude Code")).toBe("skipped");
});

test("folders left by other apps or by a removed app do not count as installed", async () => {
  // Antigravity creates these, and they stay after Windsurf is removed.
  await mkdir(join(home, ".gemini", "antigravity"), { recursive: true });
  await mkdir(join(home, ".codeium", "windsurf"), { recursive: true });
  await mkdir(join(home, ".cursor"));
  const steps = await runSetup();
  expect(outcomeOf(steps, "Gemini CLI")).toBe("skipped");
  expect(outcomeOf(steps, "Windsurf")).toBe("skipped");
  expect(outcomeOf(steps, "Cursor")).toBe("skipped");
});

test("an app whose command is on the PATH is set up even before its first run", async () => {
  commandsOnPath.set("gemini", "C:\\Tools\\gemini.cmd");
  expect(outcomeOf(await runSetup(), "Gemini CLI")).toBe("added");
  const config = JSON.parse(await readFile(join(home, ".gemini", "settings.json"), "utf8"));
  expect(config.mcpServers["godot-wingman"]).toEqual({ command: "C:/Tools/godot-wingman.exe" });
});

test("Codex gets a section with a longer tool timeout, once", async () => {
  await mkdir(join(home, ".codex"));
  await writeFile(join(home, ".codex", "config.toml"), 'model = "gpt-5"\n');
  expect(outcomeOf(await runSetup(), "Codex")).toBe("added");
  const config = await readFile(join(home, ".codex", "config.toml"), "utf8");
  expect(config).toContain('model = "gpt-5"');
  expect(config).toContain(
    '[mcp_servers.godot-wingman]\ncommand = "C:/Tools/godot-wingman.exe"\ntool_timeout_sec = 300',
  );
  // The old file is kept.
  expect(await readFile(join(home, ".codex", "config.toml.before-godot-wingman"), "utf8")).toBe(
    'model = "gpt-5"\n',
  );

  expect(outcomeOf(await runSetup(), "Codex")).toBe("already set up");
  const configAfterSecondRun = await readFile(join(home, ".codex", "config.toml"), "utf8");
  expect(configAfterSecondRun.match(/\[mcp_servers\.godot-wingman\]/g)?.length).toBe(1);
});

test("JSON apps keep their other servers", async () => {
  await mkdir(join(home, ".cursor"));
  await writeFile(
    join(home, ".cursor", "mcp.json"),
    JSON.stringify({ mcpServers: { other: { command: "x" } } }),
  );
  expect(outcomeOf(await runSetup(), "Cursor")).toBe("added");
  const config = JSON.parse(await readFile(join(home, ".cursor", "mcp.json"), "utf8"));
  expect(config.mcpServers.other).toEqual({ command: "x" });
  expect(config.mcpServers["godot-wingman"]).toEqual({ command: "C:/Tools/godot-wingman.exe" });
});

test("a config file with comments is not touched", async () => {
  await mkdir(join(home, ".gemini"));
  const original = '{\n  // my settings\n  "theme": "dark"\n}\n';
  await writeFile(join(home, ".gemini", "settings.json"), original);
  expect(outcomeOf(await runSetup(), "Gemini CLI")).toBe("failed");
  expect(await readFile(join(home, ".gemini", "settings.json"), "utf8")).toBe(original);
});

test("Claude Code replaces an existing entry with its own commands", async () => {
  expect(outcomeOf(await runSetup(0), "Claude Code")).toBe("updated");
});

test("switching to the bundle updates existing entries and keeps their other settings", async () => {
  await mkdir(join(home, ".codex"));
  await mkdir(join(home, ".cursor"));
  await writeFile(
    join(home, ".codex", "config.toml"),
    '[mcp_servers.godot-wingman]\ncommand = "C:/Tools/godot-wingman.exe"\ntool_timeout_sec = 300\n\n[other]\nkey = 1\n',
  );
  await writeFile(
    join(home, ".cursor", "mcp.json"),
    JSON.stringify({
      mcpServers: { "godot-wingman": { command: "C:/Tools/godot-wingman.exe", env: { A: "1" } } },
    }),
  );

  const steps = await runSetup(null, BUNDLE_LAUNCH);
  expect(outcomeOf(steps, "Codex")).toBe("updated");
  expect(outcomeOf(steps, "Cursor")).toBe("updated");
  expect(await readFile(join(home, ".codex", "config.toml"), "utf8")).toBe(
    '[mcp_servers.godot-wingman]\ncommand = "C:/Users/me/.bun/bin/bun.exe"\nargs = ["C:/Users/me/AppData/Local/Programs/godot-wingman/godot-wingman.js"]\ntool_timeout_sec = 300\n\n[other]\nkey = 1\n',
  );
  const cursorConfig = JSON.parse(await readFile(join(home, ".cursor", "mcp.json"), "utf8"));
  expect(cursorConfig.mcpServers["godot-wingman"]).toEqual({
    command: "C:/Users/me/.bun/bin/bun.exe",
    args: ["C:/Users/me/AppData/Local/Programs/godot-wingman/godot-wingman.js"],
    env: { A: "1" },
  });

  const secondSteps = await runSetup(null, BUNDLE_LAUNCH);
  expect(outcomeOf(secondSteps, "Codex")).toBe("already set up");
  expect(outcomeOf(secondSteps, "Cursor")).toBe("already set up");
});

test("Claude Code gets the bundle command with its argument", async () => {
  const commands: string[][] = [];
  await setUpAiClients({
    launch: BUNDLE_LAUNCH,
    homeDirectory: home,
    applicationDataDirectory: applicationData,
    localApplicationDataDirectory: join(home, "LocalAppData"),
    runClaudeCommand: async (commandArguments) => {
      commands.push(commandArguments);
      return commandArguments[1] === "remove" ? 1 : 0;
    },
    findCommand: () => null,
    findProgramFolders: () => [],
  });
  expect(commands[0]).toEqual(["mcp", "remove", "--scope", "user", "godot-wingman"]);
  expect(commands[1]).toEqual(["mcp", "add", "--scope", "user", "godot-wingman", "--", BUN, BUNDLE]);
});

test("server options like --mode are kept when switching to the bundle", async () => {
  await mkdir(join(home, ".codex"));
  await mkdir(join(home, ".cursor"));
  await writeFile(
    join(home, ".codex", "config.toml"),
    '[mcp_servers.godot-wingman]\ncommand = "C:/Tools/godot-wingman.exe"\nargs = ["--mode", "confirm"]\n',
  );
  await writeFile(
    join(home, ".cursor", "mcp.json"),
    JSON.stringify({
      mcpServers: { "godot-wingman": { command: "C:/Tools/godot-wingman.exe", args: ["--mode", "confirm"] } },
    }),
  );
  await runSetup(null, BUNDLE_LAUNCH);
  const bundle = "C:/Users/me/AppData/Local/Programs/godot-wingman/godot-wingman.js";
  expect(await readFile(join(home, ".codex", "config.toml"), "utf8")).toContain(
    `args = ["${bundle}", "--mode", "confirm"]`,
  );
  const cursorConfig = JSON.parse(await readFile(join(home, ".cursor", "mcp.json"), "utf8"));
  expect(cursorConfig.mcpServers["godot-wingman"].args).toEqual([bundle, "--mode", "confirm"]);
});

test("checkOnly reports what would change and writes nothing", async () => {
  await mkdir(join(home, ".codex"));
  commandsOnPath.set("cursor", "C:Toolscursor.cmd");
  const steps = await setUpAiClients({
    launch: EXECUTABLE_LAUNCH,
    homeDirectory: home,
    applicationDataDirectory: applicationData,
    localApplicationDataDirectory: join(home, "LocalAppData"),
    runClaudeCommand: async () => 1,
    findCommand: (commandName) => commandsOnPath.get(commandName) ?? null,
    findProgramFolders: () => [],
    checkOnly: true,
  });
  expect(outcomeOf(steps, "Codex")).toBe("would add");
  expect(outcomeOf(steps, "Cursor")).toBe("would add");
  expect(outcomeOf(steps, "Claude Code")).toBe("would add");
  expect(outcomeOf(steps, "Windsurf")).toBe("skipped");
  expect(steps.map((step) => step.id)).toEqual([
    "codex",
    "claude-desktop",
    "cursor",
    "gemini-cli",
    "windsurf",
    "claude-code",
    "vscode",
  ]);
  expect(await Bun.file(join(home, ".codex", "config.toml")).exists()).toBe(false);
  expect(await Bun.file(join(home, ".cursor", "mcp.json")).exists()).toBe(false);

  // After a real setup the same check says it is done.
  await runSetup();
  const checkedAgain = await setUpAiClients({
    launch: EXECUTABLE_LAUNCH,
    homeDirectory: home,
    applicationDataDirectory: applicationData,
    localApplicationDataDirectory: join(home, "LocalAppData"),
    runClaudeCommand: async () => 0,
    findCommand: (commandName) => commandsOnPath.get(commandName) ?? null,
    findProgramFolders: () => [],
    checkOnly: true,
  });
  expect(outcomeOf(checkedAgain, "Codex")).toBe("already set up");
  expect(outcomeOf(checkedAgain, "Cursor")).toBe("already set up");
  expect(outcomeOf(checkedAgain, "Claude Code")).toBe("already set up");
});

test("onlyClientId sets up that one app and leaves the others alone", async () => {
  await mkdir(join(home, ".codex"));
  commandsOnPath.set("cursor", "C:Toolscursor.cmd");
  const steps = await setUpAiClients({
    launch: EXECUTABLE_LAUNCH,
    homeDirectory: home,
    applicationDataDirectory: applicationData,
    localApplicationDataDirectory: join(home, "LocalAppData"),
    runClaudeCommand: async () => 0,
    findCommand: (commandName) => commandsOnPath.get(commandName) ?? null,
    findProgramFolders: () => [],
    onlyClientId: "cursor",
  });
  expect(steps).toHaveLength(1);
  expect(steps[0]?.outcome).toBe("added");
  expect(await Bun.file(join(home, ".codex", "config.toml")).exists()).toBe(false);
});

test("VS Code gets .vscode/mcp.json in the project folder", async () => {
  commandsOnPath.set("code", "C:Toolscode.cmd");
  const projectPath = join(home, "my-game");
  const steps = await setUpAiClients({
    launch: BUNDLE_LAUNCH,
    homeDirectory: home,
    applicationDataDirectory: applicationData,
    localApplicationDataDirectory: join(home, "LocalAppData"),
    findCommand: (commandName) => commandsOnPath.get(commandName) ?? null,
    findProgramFolders: () => [],
    onlyClientId: "vscode",
    projectPath,
  });
  expect(steps[0]?.outcome).toBe("added");
  const config = JSON.parse(await readFile(join(projectPath, ".vscode", "mcp.json"), "utf8"));
  expect(config.servers["godot-wingman"]).toEqual({
    type: "stdio",
    command: "C:/Users/me/.bun/bin/bun.exe",
    args: ["C:/Users/me/AppData/Local/Programs/godot-wingman/godot-wingman.js"],
  });
});

test("Claude Desktop from the Microsoft Store gets its settings in its package folder", async () => {
  if (process.platform !== "win32") return;
  const storeFolder = join(
    home,
    "LocalAppData",
    "Packages",
    "Claude_pzs8sxrjxfjjc",
    "LocalCache",
    "Roaming",
    "Claude",
  );
  await mkdir(storeFolder, { recursive: true });
  expect(outcomeOf(await runSetup(), "Claude Desktop")).toBe("added");
  const config = JSON.parse(await readFile(join(storeFolder, "claude_desktop_config.json"), "utf8"));
  expect(config.mcpServers["godot-wingman"]).toEqual({ command: "C:/Tools/godot-wingman.exe" });
  expect(await Bun.file(join(applicationData, "Claude", "claude_desktop_config.json")).exists()).toBe(false);
});
