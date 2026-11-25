/**
 * Small settings file remembered between runs (for example which Godot executable
 * worked last time). Reading never fails: a missing or broken file means "no settings".
 */
import { mkdir } from "node:fs/promises";
import { dirname } from "node:path";
import { z } from "zod";
import { getSettingsFilePath } from "./paths.ts";

const settingsSchema = z.object({
  godotExecutable: z.string().optional(),
});

export type Settings = z.infer<typeof settingsSchema>;

export async function readSettings(): Promise<Settings> {
  try {
    const fileContent: unknown = await Bun.file(getSettingsFilePath()).json();
    const parsedSettings = settingsSchema.safeParse(fileContent);
    return parsedSettings.success ? parsedSettings.data : {};
  } catch {
    return {};
  }
}

export async function updateSettings(changes: Partial<Settings>): Promise<void> {
  const currentSettings = await readSettings();
  const settingsFilePath = getSettingsFilePath();
  await mkdir(dirname(settingsFilePath), { recursive: true });
  await Bun.write(settingsFilePath, JSON.stringify({ ...currentSettings, ...changes }, null, 2));
}
