/**
 * Copies the Godot addon into a project and turns it on.
 *
 * The addon files are built into this program (see scripts/bundle-addon.ts), so
 * people never download or copy the addon by hand. Installing again updates it:
 * files are rewritten and files from older versions are removed.
 */
import { existsSync } from "node:fs";
import { mkdir, readdir, rm, stat } from "node:fs/promises";
import { dirname, join, relative } from "node:path";
import { ADDON_FOLDER_NAME, ADDON_PLUGIN_CONFIG_RESOURCE_PATH } from "../product.ts";
import { bundledAddonFiles } from "./addon-files.generated.ts";
import { addEnabledEditorPlugin } from "./project-file.ts";

export interface AddonInstallResult {
  addonDirectory: string;
  installedVersion: string;
  previousVersion: string | null;
  filesWritten: number;
  filesRemoved: number;
  pluginWasAlreadyEnabled: boolean;
}

export class NotAGodotProjectError extends Error {
  constructor(projectPath: string) {
    super(`'${projectPath}' is not a Godot project: there is no project.godot file in it.`);
    this.name = "NotAGodotProjectError";
  }
}

export function getProjectFilePath(projectPath: string): string {
  return join(projectPath, "project.godot");
}

export function getAddonDirectory(projectPath: string): string {
  return join(projectPath, "addons", ADDON_FOLDER_NAME);
}

export function getBundledAddonVersion(): string {
  return readVersionFromPluginConfig(bundledAddonFiles["plugin.cfg"] ?? "") ?? "unknown";
}

/** The addon version installed in a project, or null when it is not installed. */
export async function getInstalledAddonVersion(projectPath: string): Promise<string | null> {
  const pluginConfigFile = Bun.file(join(getAddonDirectory(projectPath), "plugin.cfg"));
  if (!(await pluginConfigFile.exists())) {
    return null;
  }
  return readVersionFromPluginConfig(await pluginConfigFile.text());
}

export async function installAddon(projectPath: string): Promise<AddonInstallResult> {
  const projectFilePath = getProjectFilePath(projectPath);
  if (!existsSync(projectFilePath)) {
    throw new NotAGodotProjectError(projectPath);
  }

  const addonDirectory = getAddonDirectory(projectPath);
  const previousVersion = await getInstalledAddonVersion(projectPath);

  let filesWritten = 0;
  for (const [relativeFilePath, fileContent] of Object.entries(bundledAddonFiles)) {
    const targetPath = join(addonDirectory, relativeFilePath);
    await mkdir(dirname(targetPath), { recursive: true });
    const existingFile = Bun.file(targetPath);
    if ((await existingFile.exists()) && (await existingFile.text()) === fileContent) {
      continue;
    }
    await Bun.write(targetPath, fileContent);
    filesWritten++;
  }

  const filesRemoved = await removeFilesFromOlderVersions(addonDirectory);

  const projectFileText = await Bun.file(projectFilePath).text();
  const { text: updatedProjectFileText, changed } = addEnabledEditorPlugin(
    projectFileText,
    ADDON_PLUGIN_CONFIG_RESOURCE_PATH,
  );
  if (changed) {
    await Bun.write(projectFilePath, updatedProjectFileText);
  }

  return {
    addonDirectory,
    installedVersion: getBundledAddonVersion(),
    previousVersion,
    filesWritten,
    filesRemoved,
    pluginWasAlreadyEnabled: !changed,
  };
}

/**
 * Deletes addon files that the current version no longer has. Godot creates
 * "<script>.uid" files next to scripts; those go together with their script.
 */
async function removeFilesFromOlderVersions(addonDirectory: string): Promise<number> {
  let removedCount = 0;
  for (const filePath of await listFilesRecursively(addonDirectory)) {
    const relativeFilePath = relative(addonDirectory, filePath).replaceAll("\\", "/");
    const ownerFilePath = relativeFilePath.replace(/\.(uid|import)$/, "");
    if (relativeFilePath in bundledAddonFiles || ownerFilePath in bundledAddonFiles) {
      continue;
    }
    await rm(filePath, { force: true });
    removedCount++;
  }
  return removedCount;
}

async function listFilesRecursively(directory: string): Promise<string[]> {
  let entryNames: string[];
  try {
    entryNames = await readdir(directory);
  } catch {
    return [];
  }
  const files: string[] = [];
  for (const entryName of entryNames) {
    const entryPath = join(directory, entryName);
    if ((await stat(entryPath)).isDirectory()) {
      files.push(...(await listFilesRecursively(entryPath)));
    } else {
      files.push(entryPath);
    }
  }
  return files;
}

function readVersionFromPluginConfig(pluginConfigText: string): string | null {
  return /^version="([^"]*)"/m.exec(pluginConfigText)?.[1] ?? null;
}
