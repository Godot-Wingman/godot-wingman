/**
 * Opens a Godot project in the editor, with the addon installed and enabled,
 * and waits until the addon reports that it is ready.
 */
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { type AddonInstallResult, getProjectFilePath, installAddon } from "../addon/addon-installer.ts";
import { updateSettings } from "../settings.ts";
import {
  type EditorRegistration,
  findRegistrationForProject,
  readEditorRegistrations,
} from "./editor-registry.ts";
import { findBestGodotExecutable, getWindowedVariant } from "./find-godot-executable.ts";

const REGISTRY_POLL_INTERVAL_MILLISECONDS = 500;

export interface LaunchEditorOptions {
  projectPath: string;
  godotExecutable?: string;
  /** Run without a window. Useful for automation and tests; screenshots do not work. */
  headless?: boolean;
  /** The first start of a big project imports every asset and can take minutes. */
  waitSeconds?: number;
  extraArguments?: string[];
  /** Passed to the Godot process, for example GODOT_PILOT_HOME in tests. */
  environment?: Record<string, string>;
}

export interface LaunchEditorResult {
  registration: EditorRegistration;
  alreadyRunning: boolean;
  addonInstall: AddonInstallResult | null;
  godotExecutable: string;
}

export class LaunchEditorError extends Error {
  constructor(
    message: string,
    readonly hint?: string,
  ) {
    super(message);
    this.name = "LaunchEditorError";
  }
}

export async function launchEditor(options: LaunchEditorOptions): Promise<LaunchEditorResult> {
  const projectPath = resolve(options.projectPath);
  if (!existsSync(getProjectFilePath(projectPath))) {
    throw new LaunchEditorError(
      `'${projectPath}' is not a Godot project (no project.godot).`,
      "Pass the folder that contains project.godot. To start a new game, create that folder with a project.godot file first.",
    );
  }

  const runningRegistration = findRegistrationForProject(await readEditorRegistrations(), projectPath);
  if (runningRegistration) {
    return {
      registration: runningRegistration,
      alreadyRunning: true,
      addonInstall: null,
      godotExecutable: runningRegistration.godotExecutable,
    };
  }

  const addonInstall = await installAddon(projectPath);

  const foundExecutable = await findBestGodotExecutable(options.godotExecutable);
  if (!foundExecutable) {
    throw new LaunchEditorError(
      "Could not find Godot on this computer.",
      "Pass godot_executable with the full path of the Godot executable, or set the GODOT_PATH environment variable.",
    );
  }
  const godotExecutable = options.headless ? foundExecutable.path : getWindowedVariant(foundExecutable.path);

  const editorArguments = ["--editor", "--path", projectPath, ...(options.extraArguments ?? [])];
  if (options.headless) {
    editorArguments.unshift("--headless");
  }
  // Detached and unreferenced: the editor keeps running when this server stops.
  const editorProcess = spawn(godotExecutable, editorArguments, {
    detached: true,
    stdio: "ignore",
    env: { ...process.env, ...options.environment },
  });
  editorProcess.unref();

  const registration = await waitForEditorRegistration(projectPath, options.waitSeconds ?? 120);
  if (!registration) {
    throw new LaunchEditorError(
      `Godot started but the addon did not report back within ${options.waitSeconds ?? 120} seconds.`,
      "The project may still be importing assets: call get_status in a moment. If the editor shows an error, the addon may be disabled in Project Settings > Plugins.",
    );
  }

  await updateSettings({ godotExecutable: foundExecutable.path });
  return { registration, alreadyRunning: false, addonInstall, godotExecutable };
}

async function waitForEditorRegistration(
  projectPath: string,
  waitSeconds: number,
): Promise<EditorRegistration | null> {
  const deadline = Date.now() + waitSeconds * 1000;
  while (Date.now() < deadline) {
    const registration = findRegistrationForProject(await readEditorRegistrations(), projectPath);
    if (registration) {
      return registration;
    }
    await Bun.sleep(REGISTRY_POLL_INTERVAL_MILLISECONDS);
  }
  return null;
}
