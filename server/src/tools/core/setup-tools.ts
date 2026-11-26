/**
 * Core tools for getting started: status, creating a project, starting the editor, installing the addon,
 * choosing an editor, switching toolsets on and off, and updating Godot Wingman.
 */
import { resolve } from "node:path";
import { z } from "zod";
import { getBundledAddonVersion, installAddon } from "../../addon/addon-installer.ts";
import { CreateProjectError, createProject, RENDERERS } from "../../godot/create-project.ts";
import { findRegistrationForProject } from "../../godot/editor-registry.ts";
import { findBestGodotExecutable, readGodotVersion } from "../../godot/find-godot-executable.ts";
import { launchEditor } from "../../godot/launch-editor.ts";
import { describePermissionMode } from "../../mcp/permission-mode.ts";
import { defineTool, errorResult, jsonResult, textResult } from "../../mcp/tool-definition.ts";
import { PRODUCT_DISPLAY_NAME, PRODUCT_VERSION } from "../../product.ts";
import { installNewestRelease } from "../../updates/updates.ts";
import { TOOLSET_PROFILES } from "../toolset-profiles.ts";

export const getStatusTool = defineTool({
  name: "get_status",
  title: "Get status",
  description:
    "Shows which Godot editors are running with the addon, which one the tools use, the permission mode and the enabled toolsets. Call this first in a new conversation, and whenever a tool says it cannot reach the editor.",
  inputShape: {},
  access: "read",
  async run(_input, context) {
    const editors = await context.editors.listEditors();
    const bundledAddonVersion = getBundledAddonVersion();
    const lines = [
      `${PRODUCT_DISPLAY_NAME} ${PRODUCT_VERSION}`,
      `Permission mode: ${describePermissionMode(context.permissionMode)}`,
      "",
    ];

    if (editors.length === 0) {
      lines.push(
        "No Godot editor with the addon is running.",
        "Next step: call launch_editor with the folder that contains project.godot.",
      );
    } else {
      lines.push("Running editors:");
      const selectedProject = context.editors.selectedProject;
      for (const editor of editors) {
        const isSelected =
          (selectedProject !== null && findRegistrationForProject([editor], selectedProject) !== undefined) ||
          (selectedProject === null && editors.length === 1);
        const markers = [
          isSelected ? "USED BY TOOLS" : "",
          editor.headless ? "headless (no screenshots)" : "",
          editor.addonVersion !== bundledAddonVersion
            ? `addon ${editor.addonVersion} is outdated: run install_addon, then restart the editor`
            : "",
        ].filter((marker) => marker !== "");
        lines.push(
          `- ${editor.projectName || "(unnamed project)"} | ${editor.projectPath} | Godot ${editor.godotVersion}${markers.length > 0 ? ` | ${markers.join(" | ")}` : ""}`,
        );
      }
      if (editors.length > 1 && selectedProject === null) {
        lines.push("Several editors are running: call select_editor to choose one.");
      }
    }

    const toolsets = context.toolsets.list();
    lines.push(
      "",
      `Enabled toolsets: ${toolsets
        .filter((toolset) => toolset.enabled)
        .map((toolset) => toolset.name)
        .join(", ")}`,
      `Other toolsets: ${toolsets
        .filter((toolset) => !toolset.enabled)
        .map((toolset) => toolset.name)
        .join(", ")} (see list_toolsets, enable with toggle_toolsets)`,
    );
    return textResult(lines.join("\n"));
  },
});

export const createProjectTool = defineTool({
  name: "create_project",
  title: "Create a new Godot project",
  description:
    'Creates a new, empty Godot project in a folder (new or empty), like "Create" in the Godot project manager, then opens it in the editor with the addon. Use it when the person wants to start a new game. renderer: "forward_plus" (default, best looking, desktop), "mobile" (phones, simpler 3D), "compatibility" (oldest hardware and the web; choose it for browser games).',
  inputShape: {
    project_path: z
      .string()
      .describe('Folder for the new project, for example "C:/games/space-shooter". Created if missing.'),
    name: z
      .string()
      .optional()
      .describe("Project name shown in Godot and the window title. Default: the folder name."),
    renderer: z.enum(RENDERERS).optional().describe('Default: "forward_plus".'),
    allow_non_empty_folder: z
      .boolean()
      .optional()
      .describe("Create it in a folder that already has files. Only when the person agreed."),
    open_editor: z.boolean().optional().describe("Open the new project in the editor. Default: true."),
    godot_executable: z
      .string()
      .optional()
      .describe("Full path of Godot, if it cannot be found automatically."),
    headless: z
      .boolean()
      .optional()
      .describe("Open the editor without a window (automation). Default: false."),
  },
  access: "setup",
  async run(input, context) {
    const godot = await findBestGodotExecutable(input.godot_executable);
    if (!godot) {
      return errorResult(
        "Could not find Godot on this computer.",
        "Ask the person where Godot is and pass godot_executable, or tell them to download Godot 4.5 or newer from godotengine.org.",
      );
    }
    try {
      const created = await createProject({
        projectPath: input.project_path,
        name: input.name,
        renderer: input.renderer,
        godotVersion: await readGodotVersion(godot.path),
        allowNonEmptyFolder: input.allow_non_empty_folder,
      });
      if (input.open_editor === false) {
        return jsonResult({
          created: created.projectPath,
          files: created.files,
          next_step: "Call launch_editor to open it.",
        });
      }
      const launchResult = await launchEditor({
        projectPath: created.projectPath,
        godotExecutable: godot.path,
        headless: input.headless,
      });
      context.editors.selectProject(launchResult.registration.projectPath);
      return jsonResult({
        created: created.projectPath,
        files: created.files,
        status: "opened in the editor and connected",
        godot_version: launchResult.registration.godotVersion,
        next_step:
          "The project is empty: create a main scene (create_scene), set it as the main scene (project setting application/run/main_scene), then build the game.",
      });
    } catch (error) {
      if (error instanceof CreateProjectError) {
        return errorResult(error.message, error.hint);
      }
      throw error;
    }
  },
});

export const launchEditorTool = defineTool({
  name: "launch_editor",
  title: "Open project in Godot",
  description:
    "Opens a Godot project in the editor and waits until the AI connection is ready. Installs or updates the addon in the project automatically. If the project is already open, it just selects it. The first opening of a big project can take minutes while Godot imports assets.",
  inputShape: {
    project_path: z.string().describe("Folder that contains project.godot."),
    godot_executable: z
      .string()
      .optional()
      .describe("Full path of the Godot executable. Only needed when Godot cannot be found automatically."),
    headless: z
      .boolean()
      .optional()
      .describe("Run without a window (for automation). Screenshots do not work headless. Default: false."),
    wait_seconds: z
      .number()
      .int()
      .min(5)
      .max(900)
      .optional()
      .describe("How long to wait for the editor. Default: 120."),
  },
  access: "setup",
  async run(input, context) {
    const launchResult = await launchEditor({
      projectPath: input.project_path,
      godotExecutable: input.godot_executable,
      headless: input.headless,
      waitSeconds: input.wait_seconds,
    });
    context.editors.selectProject(launchResult.registration.projectPath);
    const registration = launchResult.registration;
    return jsonResult({
      status: launchResult.alreadyRunning ? "already running, now selected" : "started and connected",
      project: registration.projectName,
      project_path: registration.projectPath,
      godot_version: registration.godotVersion,
      headless: registration.headless,
      addon: launchResult.addonInstall
        ? {
            version: launchResult.addonInstall.installedVersion,
            previous_version: launchResult.addonInstall.previousVersion,
          }
        : "already installed",
      next_step: "Call get_editor_state to see the open scene, or take_editor_screenshot to see the editor.",
    });
  },
});

export const installAddonTool = defineTool({
  name: "install_addon",
  title: "Install or update the addon",
  description:
    "Copies the Godot Wingman addon into a project (res://addons/godot_wingman) and enables it in project.godot. launch_editor does this automatically; use this tool to update the addon in a project. An editor that already has the project open must be restarted (or the plugin turned off and on in Project Settings > Plugins) to load the new version.",
  inputShape: {
    project_path: z.string().describe("Folder that contains project.godot."),
  },
  access: "setup",
  async run(input, context) {
    const installResult = await installAddon(resolve(input.project_path));
    const runningEditor = findRegistrationForProject(await context.editors.listEditors(), input.project_path);
    return jsonResult({
      installed_version: installResult.installedVersion,
      previous_version: installResult.previousVersion,
      files_written: installResult.filesWritten,
      old_files_removed: installResult.filesRemoved,
      addon_folder: installResult.addonDirectory,
      editor_restart_needed:
        runningEditor !== undefined && installResult.filesWritten > 0
          ? "Yes: this project is open in an editor. Restart it, or turn the plugin off and on in Project Settings > Plugins."
          : "No",
    });
  },
});

export const updateGodotWingmanTool = defineTool({
  name: "update_godot_wingman",
  title: "Update Godot Wingman",
  description:
    "Downloads the newest Godot Wingman release from GitHub, checks its SHA-256 checksum and installs it in place of this program. Only call it when the person agreed to update. The new version runs after the person restarts the AI app (or reconnects the MCP server); then launch_editor updates the addon in the project.",
  inputShape: {},
  access: "setup",
  async run() {
    const outcome = await installNewestRelease();
    return textResult(outcome.message);
  },
});

export const selectEditorTool = defineTool({
  name: "select_editor",
  title: "Choose which editor to use",
  description:
    "Chooses which running Godot editor the tools talk to, when several projects are open. Use the project path shown by get_status.",
  inputShape: {
    project_path: z.string().describe("Project folder of the editor to use."),
  },
  access: "read",
  async run(input, context) {
    const registration = findRegistrationForProject(await context.editors.listEditors(), input.project_path);
    if (!registration) {
      return errorResult(
        `No running editor has the project '${input.project_path}' open.`,
        "Call get_status to see the running editors, or launch_editor to open the project.",
      );
    }
    context.editors.selectProject(registration.projectPath);
    return textResult(
      `Tools now use the editor of '${registration.projectName}' (${registration.projectPath}).`,
    );
  },
});

export const listToolsetsTool = defineTool({
  name: "list_toolsets",
  title: "List toolsets",
  description:
    "Lists every group of tools with a description and whether it is enabled. Tools are grouped so that only the ones you need take up space; enable a group with toggle_toolsets when you need it.",
  inputShape: {},
  access: "read",
  async run(_input, context) {
    const lines = context.toolsets.list().map((toolset) => {
      const state = toolset.enabled ? "ENABLED" : "disabled";
      const hiddenNote =
        toolset.hiddenToolNames.length > 0
          ? ` (hidden by read-only mode: ${toolset.hiddenToolNames.join(", ")})`
          : "";
      return `- ${toolset.name} [${state}, ${toolset.toolNames.length} tools]: ${toolset.description}${hiddenNote}`;
    });
    const profileLines = Object.entries(TOOLSET_PROFILES).map(
      ([profileName, profile]) => `- ${profileName}: ${profile.description}`,
    );
    return textResult(
      `Toolsets:\n${lines.join("\n")}\n\nProfiles (enable several at once):\n${profileLines.join("\n")}`,
    );
  },
});

export const toggleToolsetsTool = defineTool({
  name: "toggle_toolsets",
  title: "Enable or disable toolsets",
  description:
    'Turns groups of tools on or off. Example: {"enable": ["animation"]} before animating, {"disable": ["animation"]} when done. A profile replaces the whole selection, for example {"profile": "play"} for playtesting. Your tool list updates right after this call.',
  inputShape: {
    enable: z.array(z.string()).optional().describe("Toolset names to turn on."),
    disable: z
      .array(z.string())
      .optional()
      .describe("Toolset names to turn off. The core toolset always stays on."),
    profile: z
      .enum(Object.keys(TOOLSET_PROFILES) as [string, ...string[]])
      .optional()
      .describe("Use a predefined selection instead of enable/disable."),
  },
  access: "read",
  async run(input, context) {
    const messages: string[] = [];
    if (input.profile) {
      const profile = TOOLSET_PROFILES[input.profile];
      const toolsetNames =
        profile?.toolsets === "all" ? context.toolsets.getToolsetNames() : (profile?.toolsets ?? []);
      context.toolsets.setEnabledToolsets(
        toolsetNames.filter((name) => context.toolsets.getToolsetNames().includes(name)),
      );
      messages.push(`Profile '${input.profile}' applied.`);
    }
    if (input.disable && input.disable.length > 0) {
      const { unknownNames, refusedNames } = context.toolsets.disable(input.disable);
      if (unknownNames.length > 0) {
        messages.push(`Unknown toolsets: ${unknownNames.join(", ")}.`);
      }
      if (refusedNames.length > 0) {
        messages.push(`Always enabled, not changed: ${refusedNames.join(", ")}.`);
      }
    }
    if (input.enable && input.enable.length > 0) {
      const { unknownNames } = context.toolsets.enable(input.enable);
      if (unknownNames.length > 0) {
        messages.push(`Unknown toolsets: ${unknownNames.join(", ")}. Call list_toolsets for the names.`);
      }
    }
    const enabledNames = context.toolsets
      .list()
      .filter((toolset) => toolset.enabled)
      .map((toolset) => toolset.name);
    messages.push(`Enabled now: ${enabledNames.join(", ")}.`);
    return textResult(messages.join("\n"));
  },
});
