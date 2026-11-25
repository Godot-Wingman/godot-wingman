/**
 * Finds the Godot editors that are running with the addon.
 *
 * Every editor writes `<registry folder>/<process id>.json` when the addon starts and
 * deletes it when it stops. If an editor crashes, its file stays behind; we detect
 * that by checking whether the process still exists and delete the stale file.
 */
import { readdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import { getEditorRegistryDirectory, normalizePathForComparison } from "../paths.ts";

/** Shape of the JSON file written by the addon (addon/godot_pilot/plugin.gd). */
const registryFileSchema = z.object({
  process_id: z.number(),
  port: z.number(),
  token: z.string(),
  project_path: z.string(),
  project_name: z.string(),
  godot_version: z.string(),
  godot_executable: z.string(),
  addon_version: z.string(),
  headless: z.boolean().default(false),
  started_at_unix: z.number(),
});

export interface EditorRegistration {
  processId: number;
  port: number;
  token: string;
  projectPath: string;
  projectName: string;
  godotVersion: string;
  godotExecutable: string;
  addonVersion: string;
  headless: boolean;
  startedAt: Date;
}

export async function readEditorRegistrations(): Promise<EditorRegistration[]> {
  const registryDirectory = getEditorRegistryDirectory();
  let fileNames: string[];
  try {
    fileNames = await readdir(registryDirectory);
  } catch {
    return [];
  }

  const registrations: EditorRegistration[] = [];
  for (const fileName of fileNames.filter((name) => name.endsWith(".json"))) {
    const filePath = join(registryDirectory, fileName);
    const registration = await readRegistrationFile(filePath);
    if (!registration) {
      continue;
    }
    if (!isProcessAlive(registration.processId)) {
      await rm(filePath, { force: true });
      continue;
    }
    registrations.push(registration);
  }

  // Newest first, so "the editor you just opened" wins when we have to guess.
  return registrations.sort((first, second) => second.startedAt.getTime() - first.startedAt.getTime());
}

export function findRegistrationForProject(
  registrations: EditorRegistration[],
  projectPath: string,
): EditorRegistration | undefined {
  const wantedPath = normalizePathForComparison(projectPath);
  return registrations.find(
    (registration) => normalizePathForComparison(registration.projectPath) === wantedPath,
  );
}

async function readRegistrationFile(filePath: string): Promise<EditorRegistration | null> {
  try {
    const fileContent: unknown = await Bun.file(filePath).json();
    const parsed = registryFileSchema.safeParse(fileContent);
    if (!parsed.success) {
      return null;
    }
    const data = parsed.data;
    return {
      processId: data.process_id,
      port: data.port,
      token: data.token,
      projectPath: data.project_path,
      projectName: data.project_name,
      godotVersion: data.godot_version,
      godotExecutable: data.godot_executable,
      addonVersion: data.addon_version,
      headless: data.headless,
      startedAt: new Date(data.started_at_unix * 1000),
    };
  } catch {
    // The editor may be writing the file right now; it will be complete next time.
    return null;
  }
}

/** Sending signal 0 does nothing to the process but fails when it does not exist. */
function isProcessAlive(processId: number): boolean {
  try {
    process.kill(processId, 0);
    return true;
  } catch (error) {
    // EPERM means the process exists but belongs to someone else.
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}
