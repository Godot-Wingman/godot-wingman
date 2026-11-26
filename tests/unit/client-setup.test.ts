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

beforeEach(async () => {
  home = await mkdtemp(join(tmpdir(), "godot-wingman-setup-"));
  applicationData = join(home, "AppData");
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
    runClaudeCommand: async () => claudeExitCode,
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
    runClaudeCommand: async (commandArguments) => {
      commands.push(commandArguments);
      return commandArguments[1] === "remove" ? 1 : 0;
    },
  });
  expect(commands[0]).toEqual(["mcp", "remove", "--scope", "user", "godot-wingman"]);
  expect(commands[1]).toEqual(["mcp", "add", "--scope", "user", "godot-wingman", "--", BUN, BUNDLE]);
});
