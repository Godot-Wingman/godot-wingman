/**
 * Where Godot Pilot keeps its files on this computer.
 *
 * The folder must be the same one the Godot addon uses, which is
 * `OS.get_data_dir()/godot-pilot` in GDScript. Godot's data folder is:
 *   Windows: %APPDATA%                         (C:\Users\<name>\AppData\Roaming)
 *   macOS:   ~/Library/Application Support
 *   Linux:   $XDG_DATA_HOME or ~/.local/share
 */
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { HOME_OVERRIDE_ENVIRONMENT_VARIABLE, PRODUCT_NAME } from "./product.ts";

export function getOperatingSystemDataDirectory(): string {
  if (process.platform === "win32") {
    return process.env.APPDATA ?? join(homedir(), "AppData", "Roaming");
  }
  if (process.platform === "darwin") {
    return join(homedir(), "Library", "Application Support");
  }
  return process.env.XDG_DATA_HOME ?? join(homedir(), ".local", "share");
}

export function getProductHomeDirectory(): string {
  const overrideDirectory = process.env[HOME_OVERRIDE_ENVIRONMENT_VARIABLE];
  if (overrideDirectory) {
    return overrideDirectory;
  }
  return join(getOperatingSystemDataDirectory(), PRODUCT_NAME);
}

/** Each running Godot editor with the addon writes a small JSON file here. */
export function getEditorRegistryDirectory(): string {
  return join(getProductHomeDirectory(), "editors");
}

export function getCacheDirectory(): string {
  return join(getProductHomeDirectory(), "cache");
}

/** Settings remembered between runs, for example the Godot executable that worked. */
export function getSettingsFilePath(): string {
  return join(getProductHomeDirectory(), "settings.json");
}

/**
 * Makes two paths comparable: absolute, forward slashes, no trailing slash, and
 * lower case on Windows where paths are case-insensitive.
 * Godot writes project paths like "C:/code/game/", Node writes "C:\code\game".
 */
export function normalizePathForComparison(path: string): string {
  const absolutePath = resolve(path).replaceAll("\\", "/").replace(/\/+$/, "");
  return process.platform === "win32" ? absolutePath.toLowerCase() : absolutePath;
}
