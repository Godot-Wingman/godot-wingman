#!/usr/bin/env bun
/**
 * Command-line entry point.
 *
 *   godot-pilot                     Start the MCP server (this is what AI clients run).
 *   godot-pilot install <project>   Install or update the addon in a Godot project.
 *   godot-pilot doctor              Check the setup: Godot executables, running editors.
 *   godot-pilot update              Install the newest release from GitHub.
 *   godot-pilot --version | help
 *
 * Server options (also readable from environment variables):
 *   --mode full|confirm|read-only    GODOT_PILOT_MODE      (default: full)
 *   --toolsets a,b,c | <profile>     GODOT_PILOT_TOOLSETS  (default: core,scene,inspector,script,project)
 *   --project <path>                 GODOT_PILOT_PROJECT   (editor to use when several run)
 *   --no-update-check                GODOT_PILOT_NO_UPDATE_CHECK=1 (do not look for new versions)
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
import { createMcpServer } from "./mcp/create-mcp-server.ts";
import { PERMISSION_MODES, parsePermissionMode } from "./mcp/permission-mode.ts";
import { getProductHomeDirectory } from "./paths.ts";
import { PRODUCT_DISPLAY_NAME, PRODUCT_NAME, PRODUCT_VERSION } from "./product.ts";
import { DEFAULT_TOOLSET_NAMES, TOOLSET_PROFILES } from "./tools/toolset-profiles.ts";
import { ALL_TOOLSETS } from "./tools/toolsets.ts";
import { installNewestRelease, isUpdateCheckDisabled, removePreviousExecutable } from "./updates/updates.ts";

const HELP_TEXT = `${PRODUCT_DISPLAY_NAME} ${PRODUCT_VERSION} - lets AI assistants use the Godot editor.

Usage:
  ${PRODUCT_NAME}                      Start the MCP server (add this command to your AI client)
  ${PRODUCT_NAME} install <project>    Install or update the Godot addon in a project
  ${PRODUCT_NAME} doctor               Check Godot executables and running editors
  ${PRODUCT_NAME} update               Install the newest release from GitHub
  ${PRODUCT_NAME} --version

Server options:
  --mode <${PERMISSION_MODES.join("|")}>   What the AI may do without asking (default: full)
  --toolsets <names or profile>        Toolsets enabled at start, comma-separated,
                                       or one of: ${Object.keys(TOOLSET_PROFILES).join(", ")}
  --project <path>                     Editor to use when several are running
  --no-update-check                    Do not look for new versions on GitHub

Docs: https://github.com/Albis0/godot-pilot#readme`;

async function main(): Promise<void> {
  const { values: options, positionals } = parseArgs({
    args: process.argv.slice(2),
    allowPositionals: true,
    options: {
      mode: { type: "string" },
      toolsets: { type: "string" },
      project: { type: "string" },
      "no-update-check": { type: "boolean" },
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
  if (command === "update") {
    const outcome = await installNewestRelease();
    console.log(outcome.message);
    return;
  }
  if (command !== undefined && command !== "serve") {
    console.error(`Unknown command '${command}'.\n\n${HELP_TEXT}`);
    process.exit(1);
  }

  await runServer({
    mode: options.mode ?? process.env.GODOT_PILOT_MODE,
    toolsets: options.toolsets ?? process.env.GODOT_PILOT_TOOLSETS,
    project: options.project ?? process.env.GODOT_PILOT_PROJECT,
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
