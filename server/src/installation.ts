/**
 * How this copy of Godot Wingman was installed, and the command that starts it.
 *
 * There are three ways to run it:
 * - "bundle": the small godot-wingman.js file from a release, run by a Bun that is
 *   installed on the computer (about 1-2 MB to download). The installers use this
 *   when Bun is there or can be installed.
 * - "executable": the single-file program from a release, with Bun built in (about
 *   100 MB). Used when Bun cannot be used.
 * - "source": `bun run server/src/main.ts` in a clone of the repository.
 */
import { mkdir, writeFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { getProductHomeDirectory } from "./paths.ts";
import { PRODUCT_NAME, PRODUCT_VERSION } from "./product.ts";

/**
 * Where an installed copy notes how to start it, so the editor panel can run
 * `setup` for its Configure buttons. Read by addon/godot_wingman/ui/ai_apps_dialog.gd.
 */
export const INSTALLATION_FILE_NAME = "installation.json";

/** Name of the JavaScript build in a release, as built by scripts/build-binaries.ts. */
export const BUNDLE_ASSET_NAME = `${PRODUCT_NAME}.js`;

export type InstallationKind = "bundle" | "executable" | "source";

/** What an AI app runs to start the MCP server. */
export interface ServerLaunchCommand {
  command: string;
  args: string[];
}

export function getInstallationKind(): InstallationKind {
  if (!/^bun(\.exe)?$/i.test(basename(process.execPath))) {
    return "executable";
  }
  return basename(Bun.main) === BUNDLE_ASSET_NAME ? "bundle" : "source";
}

/** The file that an update replaces: the bundle, or the executable itself. */
export function getInstalledFilePath(): string {
  return getInstallationKind() === "bundle" ? Bun.main : process.execPath;
}

/**
 * The command to put in AI app settings. For the bundle it is the full path of the Bun
 * that runs it now, so AI apps that do not read the person's PATH still find it.
 */
export function getServerLaunchCommand(): ServerLaunchCommand {
  return getInstallationKind() === "bundle"
    ? { command: process.execPath, args: [Bun.main] }
    : { command: process.execPath, args: [] };
}

/**
 * Writes installation.json in the product folder: the launch command and the version.
 * Copies run from source write nothing, so the panel never points AI apps at a clone.
 */
export async function recordInstallation(productHomeDirectory = getProductHomeDirectory()): Promise<void> {
  if (getInstallationKind() === "source") {
    return;
  }
  const launch = getServerLaunchCommand();
  await mkdir(productHomeDirectory, { recursive: true });
  await writeFile(
    join(productHomeDirectory, INSTALLATION_FILE_NAME),
    `${JSON.stringify({ ...launch, version: PRODUCT_VERSION }, null, 2)}\n`,
  );
}
