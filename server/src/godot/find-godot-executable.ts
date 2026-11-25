/**
 * Finds Godot executables installed on this computer.
 *
 * Godot is usually not "installed": people download a zip and run the file from any
 * folder. So we look in several places, in this order:
 * 1. an explicit path given to the tool,
 * 2. the GODOT_PATH environment variable,
 * 3. the executable remembered in settings.json (the last one that worked),
 * 4. executables of editors that are running or ran recently,
 * 5. `godot` / `godot4` on the PATH,
 * 6. common download folders (Desktop, Downloads, ~/Godot, Program Files, Steam...).
 * The newest version wins when several are found in the same step.
 */
import { existsSync } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { GODOT_PATH_ENVIRONMENT_VARIABLE } from "../product.ts";
import { readSettings } from "../settings.ts";
import { readEditorRegistrations } from "./editor-registry.ts";

export interface FoundGodotExecutable {
  path: string;
  /** Version read from the file name, for example "4.7.2". Empty when unknown. */
  versionFromFileName: string;
  /** Where we found it, for messages like "found in Downloads". */
  source: string;
}

const MAX_FOLDER_SEARCH_DEPTH = 3;

export async function findGodotExecutables(explicitPath?: string): Promise<FoundGodotExecutable[]> {
  const candidates: FoundGodotExecutable[] = [];
  const addCandidate = (path: string, source: string) => {
    const resolvedPath = resolveMacApplicationBundle(path);
    if (existsSync(resolvedPath) && !candidates.some((candidate) => candidate.path === resolvedPath)) {
      candidates.push({
        path: resolvedPath,
        versionFromFileName: readVersionFromFileName(resolvedPath),
        source,
      });
    }
  };

  if (explicitPath) {
    addCandidate(explicitPath, "given path");
  }
  const environmentPath = process.env[GODOT_PATH_ENVIRONMENT_VARIABLE];
  if (environmentPath) {
    addCandidate(environmentPath, `${GODOT_PATH_ENVIRONMENT_VARIABLE} environment variable`);
  }
  const rememberedPath = (await readSettings()).godotExecutable;
  if (rememberedPath) {
    addCandidate(rememberedPath, "last used");
  }
  for (const registration of await readEditorRegistrations()) {
    addCandidate(registration.godotExecutable, "running editor");
  }
  for (const commandName of ["godot", "godot4", "Godot"]) {
    const pathOnSystem = Bun.which(commandName);
    if (pathOnSystem) {
      addCandidate(pathOnSystem, "PATH");
    }
  }

  const foundInFolders: FoundGodotExecutable[] = [];
  for (const folder of getCommonInstallFolders()) {
    for (const executablePath of await searchFolderForGodot(folder, MAX_FOLDER_SEARCH_DEPTH)) {
      foundInFolders.push({
        path: executablePath,
        versionFromFileName: readVersionFromFileName(executablePath),
        source: folder,
      });
    }
  }
  foundInFolders.sort((first, second) =>
    compareVersions(second.versionFromFileName, first.versionFromFileName),
  );
  for (const found of foundInFolders) {
    addCandidate(found.path, found.source);
  }

  return candidates;
}

export async function findBestGodotExecutable(explicitPath?: string): Promise<FoundGodotExecutable | null> {
  const [bestCandidate] = await findGodotExecutables(explicitPath);
  return bestCandidate ?? null;
}

/**
 * On Windows, Godot ships two files: "Godot_v4.x_win64.exe" (no console output)
 * and "Godot_v4.x_win64_console.exe". Command-line work needs the console one.
 */
export function getConsoleVariant(executablePath: string): string {
  if (process.platform !== "win32" || executablePath.endsWith("_console.exe")) {
    return executablePath;
  }
  const consolePath = executablePath.replace(/\.exe$/i, "_console.exe");
  return existsSync(consolePath) ? consolePath : executablePath;
}

/** The opposite of getConsoleVariant: the editor should open without a console window. */
export function getWindowedVariant(executablePath: string): string {
  if (process.platform !== "win32" || !executablePath.endsWith("_console.exe")) {
    return executablePath;
  }
  const windowedPath = executablePath.replace(/_console\.exe$/i, ".exe");
  return existsSync(windowedPath) ? windowedPath : executablePath;
}

/** Runs `godot --version` and returns something like "4.7.2.stable.official.ed1daf0bf". */
export async function readGodotVersion(executablePath: string): Promise<string> {
  const versionProcess = Bun.spawn([getConsoleVariant(executablePath), "--version"], {
    stdout: "pipe",
    stderr: "ignore",
  });
  const output = await new Response(versionProcess.stdout).text();
  await versionProcess.exited;
  const versionLine = output
    .trim()
    .split("\n")
    .map((line) => line.trim())
    .findLast((line) => /^\d+\.\d+/.test(line));
  return versionLine ?? "";
}

/** "Godot_v4.7.2-stable_win64.exe" -> "4.7.2". */
export function readVersionFromFileName(executablePath: string): string {
  const versionMatch = /v?(\d+\.\d+(?:\.\d+)?)/.exec(basename(executablePath));
  return versionMatch?.[1] ?? "";
}

/** Compares "4.7.2" and "4.10" as version numbers. Unknown versions sort last. */
export function compareVersions(firstVersion: string, secondVersion: string): number {
  const firstParts = firstVersion.split(".").map(Number);
  const secondParts = secondVersion.split(".").map(Number);
  for (let partIndex = 0; partIndex < Math.max(firstParts.length, secondParts.length); partIndex++) {
    const difference = (firstParts[partIndex] ?? -1) - (secondParts[partIndex] ?? -1);
    if (difference !== 0) {
      return difference;
    }
  }
  return 0;
}

function getCommonInstallFolders(): string[] {
  const home = homedir();
  const folders = [
    join(home, "Godot"),
    join(home, "godot"),
    join(home, "Desktop"),
    join(home, "Downloads"),
    join(home, "Applications"),
    join(home, ".local", "bin"),
  ];
  if (process.platform === "win32") {
    folders.push(
      "C:\\Godot",
      join(process.env.ProgramFiles ?? "C:\\Program Files", "Godot"),
      join(process.env.LOCALAPPDATA ?? join(home, "AppData", "Local"), "Godot"),
      join(home, "scoop", "apps", "godot", "current"),
      join(
        process.env["ProgramFiles(x86)"] ?? "C:\\Program Files (x86)",
        "Steam",
        "steamapps",
        "common",
        "Godot Engine",
      ),
    );
  } else if (process.platform === "darwin") {
    folders.push(
      "/Applications",
      join(home, "Library", "Application Support", "Steam", "steamapps", "common", "Godot Engine"),
    );
  } else {
    folders.push(
      "/usr/local/bin",
      "/opt",
      join(home, ".steam", "steam", "steamapps", "common", "Godot Engine"),
    );
  }
  return folders;
}

async function searchFolderForGodot(folder: string, remainingDepth: number): Promise<string[]> {
  let entries: string[];
  try {
    entries = await readdir(folder);
  } catch {
    return [];
  }

  const found: string[] = [];
  for (const entryName of entries) {
    const entryPath = join(folder, entryName);
    if (isGodotExecutableName(entryName)) {
      found.push(entryPath);
      continue;
    }
    if (remainingDepth > 1 && /godot/i.test(entryName)) {
      const entryStats = await stat(entryPath).catch(() => null);
      if (entryStats?.isDirectory()) {
        found.push(...(await searchFolderForGodot(entryPath, remainingDepth - 1)));
      }
    }
  }
  return found;
}

function isGodotExecutableName(fileName: string): boolean {
  if (process.platform === "win32") {
    // Prefer the windowed exe; the console variant is found from it when needed.
    return (
      /^godot.*\.exe$/i.test(fileName) &&
      !/_console\.exe$/i.test(fileName) &&
      !/mono_?glue|uninstall/i.test(fileName)
    );
  }
  if (process.platform === "darwin") {
    return /^godot.*\.app$/i.test(fileName);
  }
  return /^godot[^/]*(x86_64|arm64|x86_32|\.64|\.32)?$/i.test(fileName) && !fileName.endsWith(".zip");
}

/** On macOS the real executable is inside the .app bundle. */
function resolveMacApplicationBundle(path: string): string {
  if (process.platform === "darwin" && path.endsWith(".app")) {
    return join(path, "Contents", "MacOS", "Godot");
  }
  return path;
}

export function describeExecutable(found: FoundGodotExecutable): string {
  const version = found.versionFromFileName ? ` ${found.versionFromFileName}` : "";
  return `Godot${version} at ${found.path} (${found.source}, folder ${dirname(found.path)})`;
}
