#!/usr/bin/env bun
/**
 * Command-line entry point.
 *
 *   godot-wingman                     Start the MCP server (this is what AI clients run).
 *   godot-wingman install <project>   Install or update the addon in a Godot project.
 *   godot-wingman doctor              Check the setup: Godot executables, running editors.
 *   godot-wingman update              Install the newest release from GitHub.
 *   godot-wingman setup               Add Godot Wingman to the AI apps on this computer.
 *   godot-wingman --version | help
 *
 * Server options (also readable from environment variables):
 *   --mode full|confirm|read-only    GODOT_WINGMAN_MODE      (default: full)
 *   --toolsets a,b,c | <profile>     GODOT_WINGMAN_TOOLSETS  (default: core,scene,inspector,script,project)
 *   --project <path>                 GODOT_WINGMAN_PROJECT   (editor to use when several run)
 *   --no-update-check                GODOT_WINGMAN_NO_UPDATE_CHECK=1 (do not look for new versions)
 *
 * Important: in server mode, stdout belongs to the MCP protocol. Everything meant for
 * people must go to stderr (console.error).
 */
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { getBundledAddonVersion, installAddon } from "./addon/addon-installer.ts";
import { readEditorRegistrations } from "./godot/editor-registry.ts";
import { describeExecutable, findGodotExecutables } from "./godot/find-godot-executable.ts";
import { getInstallationKind, getServerLaunchCommand, recordInstallation } from "./installation.ts";
import { createMcpServer } from "./mcp/create-mcp-server.ts";
import { PERMISSION_MODES, parsePermissionMode } from "./mcp/permission-mode.ts";
import { getProductHomeDirectory } from "./paths.ts";
import { PRODUCT_DISPLAY_NAME, PRODUCT_NAME, PRODUCT_VERSION } from "./product.ts";
import { AI_CLIENTS, isAiClientId, setUpAiClients } from "./setup/client-setup.ts";
import { DEFAULT_TOOLSET_NAMES, TOOLSET_PROFILES } from "./tools/toolset-profiles.ts";
import { ALL_TOOLSETS } from "./tools/toolsets.ts";
import { installNewestRelease, isUpdateCheckDisabled, removePreviousExecutable } from "./updates/updates.ts";

const HELP_TEXT = `${PRODUCT_DISPLAY_NAME} ${PRODUCT_VERSION} - lets AI assistants use the Godot editor.

Usage:
  ${PRODUCT_NAME}                      Start the MCP server (add this command to your AI client)
  ${PRODUCT_NAME} install <project>    Install or update the Godot addon in a project
  ${PRODUCT_NAME} doctor               Check Godot executables and running editors
  ${PRODUCT_NAME} update               Install the newest release from GitHub
  ${PRODUCT_NAME} setup                Add Godot Wingman to the AI apps on this computer
  ${PRODUCT_NAME} setup --client <app> Only this app: ${AI_CLIENTS.map((client) => client.id).join(", ")}
                                       (vscode also needs --project <Godot project folder>)
  ${PRODUCT_NAME} setup --status       Show which apps are set up, without changing anything
  ${PRODUCT_NAME} --version

Server options:
  --mode <${PERMISSION_MODES.join("|")}>   What the AI may do without asking (default: full)
  --toolsets <names or profile>        Toolsets enabled at start, comma-separated,
                                       or one of: ${Object.keys(TOOLSET_PROFILES).join(", ")}
  --project <path>                     Editor to use when several are running
  --no-update-check                    Do not look for new versions on GitHub

Docs: https://github.com/Godot-Wingman/godot-wingman#readme`;

async function main(): Promise<void> {
  const { values: options, positionals } = parseArgs({
    args: process.argv.slice(2),
    allowPositionals: true,
    options: {
      mode: { type: "string" },
      toolsets: { type: "string" },
      project: { type: "string" },
      "no-update-check": { type: "boolean" },
      client: { type: "string" },
      status: { type: "boolean" },
      json: { type: "boolean" },
      version: { type: "boolean", short: "v" },
      help: { type: "boolean", short: "h" },
    },
  });
  const [command, ...commandArguments] = positionals;

  if (options.version) {
    console.log(PRODUCT_VERSION);
    return;
  }
  if (options.help || command === "help") {
    console.log(HELP_TEXT);
    return;
  }
  if (command === "install") {
    await runInstallCommand(commandArguments[0]);
    return;
  }
  if (command === "doctor") {
    await runDoctorCommand();
    return;
  }
  if (command === "setup") {
    await runSetupCommand({
      clientId: options.client,
      checkOnly: options.status === true,
      projectPath: options.project ? resolve(options.project) : undefined,
      printJson: options.json === true,
    });
    return;
  }
  if (command === "update") {
    const outcome = await installNewestRelease();
    console.log(outcome.message);
    return;
  }
  if (command === undefined && process.stdin.isTTY) {
    // Started by a person (double-click or a terminal), not by an AI app.
    await runWelcome();
    return;
  }
  if (command !== undefined && command !== "serve") {
    console.error(`Unknown command '${command}'.\n\n${HELP_TEXT}`);
    process.exit(1);
  }

  await runServer({
    mode: options.mode ?? process.env.GODOT_WINGMAN_MODE,
    toolsets: options.toolsets ?? process.env.GODOT_WINGMAN_TOOLSETS,
    project: options.project ?? process.env.GODOT_WINGMAN_PROJECT,
    checkForUpdates: options["no-update-check"] !== true && !isUpdateCheckDisabled(),
  });
}

async function runServer(options: {
  mode?: string;
  toolsets?: string;
  project?: string;
  checkForUpdates: boolean;
}): Promise<void> {
  await removePreviousExecutable();
  await recordInstallation().catch(() => undefined);
  const { server, editors } = createMcpServer({
    permissionMode: parsePermissionMode(options.mode),
    initialToolsets: resolveToolsetSelection(options.toolsets),
    preselectedProjectPath: options.project ? resolve(options.project) : undefined,
    checkForUpdates: options.checkForUpdates,
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(`${PRODUCT_DISPLAY_NAME} ${PRODUCT_VERSION} MCP server is running.`);

  const shutDown = async () => {
    editors.closeAll();
    await server.close();
    process.exit(0);
  };
  process.on("SIGINT", shutDown);
  process.on("SIGTERM", shutDown);
  // The client closing our stdin means it is gone.
  process.stdin.on("end", shutDown);
}

/** "animation,ui" -> those toolsets; "play" -> that profile's toolsets; empty -> defaults. */
function resolveToolsetSelection(selection: string | undefined): string[] {
  if (!selection) {
    return DEFAULT_TOOLSET_NAMES;
  }
  const profile = TOOLSET_PROFILES[selection.trim()];
  if (profile) {
    return profile.toolsets === "all" ? ALL_TOOLSETS.map((toolset) => toolset.name) : profile.toolsets;
  }
  return selection
    .split(",")
    .map((name) => name.trim())
    .filter((name) => name.length > 0);
}

async function runInstallCommand(projectPath: string | undefined): Promise<void> {
  if (!projectPath) {
    console.error(`Usage: ${PRODUCT_NAME} install <path to the folder with project.godot>`);
    process.exit(1);
  }
  const result = await installAddon(resolve(projectPath));
  console.log(
    result.previousVersion
      ? `Updated the addon from ${result.previousVersion} to ${result.installedVersion} in ${result.addonDirectory}`
      : `Installed the addon ${result.installedVersion} in ${result.addonDirectory}`,
  );
  console.log(
    result.pluginWasAlreadyEnabled
      ? "The plugin was already enabled."
      : "Enabled the plugin in project.godot.",
  );
}

/**
 * What a person sees when they open the program themselves. AI apps start it with a pipe
 * as input, so they never get here.
 */
async function runWelcome(): Promise<void> {
  console.log(`${PRODUCT_DISPLAY_NAME} ${PRODUCT_VERSION}

This program lets AI apps (Codex, Claude, Cursor...) use the Godot editor.
You do not need to open it yourself: your AI app starts it in the background.
`);
  if (getInstallationKind() !== "source") {
    const answer = prompt(`Add ${PRODUCT_DISPLAY_NAME} to the AI apps on this computer now? [Y/n]`);
    if (answer !== null && (answer.trim() === "" || /^y/i.test(answer.trim()))) {
      console.log("");
      await runSetupCommand();
    }
  }
  prompt("\nPress Enter to close.");
}

interface SetupCommandOptions {
  clientId?: string;
  checkOnly?: boolean;
  projectPath?: string;
  /** Print one JSON object instead of text; the editor panel reads it. */
  printJson?: boolean;
}

async function runSetupCommand(options: SetupCommandOptions = {}): Promise<void> {
  if (getInstallationKind() === "source") {
    console.error(
      "setup adds an installed Godot Wingman to your AI apps. When running from source, follow docs/INSTALL.md.",
    );
    process.exit(1);
  }
  const clientId = options.clientId;
  if (clientId !== undefined && !isAiClientId(clientId)) {
    console.error(
      `Unknown app '${clientId}'. Known apps: ${AI_CLIENTS.map((client) => client.id).join(", ")}`,
    );
    process.exit(1);
  }
  await recordInstallation();
  const launch = getServerLaunchCommand();
  const steps = await setUpAiClients({
    launch,
    onlyClientId: clientId,
    checkOnly: options.checkOnly,
    projectPath: options.projectPath,
  });
  if (options.printJson) {
    console.log(JSON.stringify({ version: PRODUCT_VERSION, launch, steps }));
    return;
  }
  console.log(
    options.checkOnly
      ? `${PRODUCT_DISPLAY_NAME} (${[launch.command, ...launch.args].join(" ")}) in your AI apps:\n`
      : `Adding ${PRODUCT_DISPLAY_NAME} (${[launch.command, ...launch.args].join(" ")}) to your AI apps:\n`,
  );
  for (const step of steps) {
    console.log(`  ${step.client.padEnd(18)} ${step.outcome.padEnd(15)} ${step.detail}`);
  }
  if (options.checkOnly) {
    return;
  }
  console.log(
    '\nRestart the AI apps that were changed. Then ask the AI: "Create a new Godot game in C:/games/my-game".',
  );
}

async function runDoctorCommand(): Promise<void> {
  console.log(`${PRODUCT_DISPLAY_NAME} ${PRODUCT_VERSION} (addon ${getBundledAddonVersion()})`);
  console.log(`Data folder: ${getProductHomeDirectory()}\n`);

  const executables = await findGodotExecutables();
  console.log(
    executables.length > 0 ? "Godot executables found:" : "No Godot executable found. Set GODOT_PATH.",
  );
  for (const executable of executables) {
    console.log(`  - ${describeExecutable(executable)}`);
  }

  const editors = await readEditorRegistrations();
  console.log(
    editors.length > 0 ? "\nRunning editors with the addon:" : "\nNo editor with the addon is running.",
  );
  for (const editor of editors) {
    console.log(
      `  - ${editor.projectName} | ${editor.projectPath} | Godot ${editor.godotVersion} | port ${editor.port}`,
    );
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
