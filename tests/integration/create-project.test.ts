/**
 * Creating a new Godot project from nothing (create_project): the files are written,
 * a real Godot opens them without complaint, and the addon connects.
 */
import { afterAll, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CreateProjectError, createProject } from "../../server/src/godot/create-project.ts";
import {
  findBestGodotExecutable,
  getConsoleVariant,
  readGodotVersion,
} from "../../server/src/godot/find-godot-executable.ts";
import { launchEditor } from "../../server/src/godot/launch-editor.ts";
import { HOME_OVERRIDE_ENVIRONMENT_VARIABLE } from "../../server/src/product.ts";

const temporaryRoot = await mkdtemp(join(tmpdir(), "godot-pilot-create-"));
const startedProcessIds: number[] = [];

afterAll(async () => {
  for (const processId of startedProcessIds) {
    try {
      process.kill(processId);
    } catch {
      // Already gone.
    }
  }
  await Bun.sleep(1000);
  await rm(temporaryRoot, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 }).catch(() => {});
}, 30_000);

describe("create_project", () => {
  test("writes project.godot with the name, the Godot version and the renderer", async () => {
    const projectPath = join(temporaryRoot, "space-shooter");
    const created = await createProject({
      projectPath,
      name: "Space Shooter",
      renderer: "compatibility",
      godotVersion: "4.7.2.stable.official",
    });
    expect(created.files).toContain("project.godot");
    const projectFile = await readFile(join(projectPath, "project.godot"), "utf8");
    expect(projectFile).toContain('config/name="Space Shooter"');
    expect(projectFile).toContain('config/features=PackedStringArray("4.7", "GL Compatibility")');
    expect(projectFile).toContain('renderer/rendering_method="gl_compatibility"');
    expect(await readFile(join(projectPath, ".gitignore"), "utf8")).toContain(".godot/");
  });

  test("refuses a folder that already has a project or other files", async () => {
    const projectPath = join(temporaryRoot, "space-shooter");
    await expect(createProject({ projectPath, godotVersion: "4.7" })).rejects.toBeInstanceOf(CreateProjectError);

    const busyFolder = join(temporaryRoot, "busy");
    await mkdir(busyFolder, { recursive: true });
    await writeFile(join(busyFolder, "notes.txt"), "mine");
    await expect(createProject({ projectPath: busyFolder, godotVersion: "4.7" })).rejects.toThrow("is not empty");
    const allowed = await createProject({
      projectPath: busyFolder,
      godotVersion: "4.7",
      allowNonEmptyFolder: true,
    });
    expect(allowed.files).toContain("project.godot");
  });

  test("a real Godot opens the new project and the addon connects", async () => {
    const godot = await findBestGodotExecutable();
    if (!godot) return;
    const homeDirectory = join(temporaryRoot, "home");
    process.env[HOME_OVERRIDE_ENVIRONMENT_VARIABLE] = homeDirectory;
    const projectPath = join(temporaryRoot, "new-game");
    await createProject({ projectPath, name: "New Game", godotVersion: await readGodotVersion(godot.path) });

    const launched = await launchEditor({
      projectPath,
      godotExecutable: getConsoleVariant(godot.path),
      headless: true,
      waitSeconds: 180,
      environment: { [HOME_OVERRIDE_ENVIRONMENT_VARIABLE]: homeDirectory },
    });
    startedProcessIds.push(launched.registration.processId);
    expect(launched.registration.projectName).toBe("New Game");
  }, 240_000);
});
