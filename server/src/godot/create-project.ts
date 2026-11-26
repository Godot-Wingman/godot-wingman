/**
 * Creates a new, empty Godot project: the same files Godot's project manager writes
 * for "Create" (project.godot, .gitignore, .gitattributes, .editorconfig), so the AI can
 * start a game from nothing without the person clicking through the project manager.
 */
import { existsSync } from "node:fs";
import { mkdir, readdir, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { getProjectFilePath } from "../addon/addon-installer.ts";

/** Godot's three renderers. Forward+ is the default of the project manager. */
export const RENDERERS = ["forward_plus", "mobile", "compatibility"] as const;
export type Renderer = (typeof RENDERERS)[number];

/** How each renderer is written in project.godot. */
const RENDERER_SETTINGS: Record<Renderer, { feature: string; settings: string[] }> = {
  forward_plus: { feature: "Forward Plus", settings: [] },
  mobile: { feature: "Mobile", settings: ['renderer/rendering_method="mobile"'] },
  compatibility: {
    feature: "GL Compatibility",
    settings: [
      'renderer/rendering_method="gl_compatibility"',
      'renderer/rendering_method.mobile="gl_compatibility"',
    ],
  },
};

export interface CreateProjectOptions {
  projectPath: string;
  /** Shown in the editor and the game window title. Default: the folder name. */
  name?: string;
  renderer?: Renderer;
  /** Version of the Godot that will open it, for example "4.7.2.stable.official". */
  godotVersion: string;
  /** Create the project in a folder that already has files in it. */
  allowNonEmptyFolder?: boolean;
}

export class CreateProjectError extends Error {
  constructor(
    message: string,
    readonly hint: string,
  ) {
    super(message);
    this.name = "CreateProjectError";
  }
}

/** Returns the absolute project folder and the files written. */
export async function createProject(
  options: CreateProjectOptions,
): Promise<{ projectPath: string; files: string[] }> {
  const projectPath = resolve(options.projectPath);
  if (existsSync(getProjectFilePath(projectPath))) {
    throw new CreateProjectError(
      `'${projectPath}' already contains a Godot project.`,
      "Open it with launch_editor instead.",
    );
  }
  if (existsSync(projectPath) && !options.allowNonEmptyFolder) {
    const entries = (await readdir(projectPath)).filter((entry) => entry !== ".git");
    if (entries.length > 0) {
      throw new CreateProjectError(
        `'${projectPath}' is not empty (${entries.slice(0, 5).join(", ")}${entries.length > 5 ? ", ..." : ""}).`,
        "Choose an empty or new folder. If the person wants the project in this folder anyway, pass allow_non_empty_folder: true.",
      );
    }
  }

  const versionMatch = /^(\d+)\.(\d+)/.exec(options.godotVersion);
  const featureVersion = versionMatch ? `${versionMatch[1]}.${versionMatch[2]}` : "";
  const renderer = RENDERER_SETTINGS[options.renderer ?? "forward_plus"];
  const features = [featureVersion, renderer.feature].filter((feature) => feature !== "");
  const name = (options.name ?? basename(projectPath)).replaceAll('"', '\\"');

  const projectFileLines = [
    "; Engine configuration file.",
    "; It's best edited using the editor UI and not directly,",
    "; since the parameters that go here are not all obvious.",
    ";",
    "; Format:",
    ";   [section] ; section goes between []",
    ";   param=value ; assign values to parameters",
    "",
    "config_version=5",
    "",
    "[application]",
    "",
    `config/name="${name}"`,
    `config/features=PackedStringArray(${features.map((feature) => `"${feature}"`).join(", ")})`,
    "",
  ];
  if (renderer.settings.length > 0) {
    projectFileLines.push("[rendering]", "", ...renderer.settings, "");
  }

  const files: Record<string, string> = {
    "project.godot": projectFileLines.join("\n"),
    ".gitignore": "# Godot 4+ specific ignores\n.godot/\n/android/\n",
    ".gitattributes": "# Normalize EOL for all files that Git considers text files.\n* text=auto eol=lf\n",
    ".editorconfig": "root = true\n\n[*]\ncharset = utf-8\n",
  };
  await mkdir(projectPath, { recursive: true });
  for (const [fileName, content] of Object.entries(files)) {
    await writeFile(join(projectPath, fileName), content);
  }
  return { projectPath, files: Object.keys(files) };
}
