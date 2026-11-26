/**
 * Core tools for getting started: status, starting the editor, installing the addon,
 * choosing an editor, switching toolsets on and off, and updating Godot Pilot.
 */
import { resolve } from "node:path";
import { z } from "zod";
import { getBundledAddonVersion, installAddon } from "../../addon/addon-installer.ts";
import { findRegistrationForProject } from "../../godot/editor-registry.ts";
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
    "Copies the Godot Pilot addon into a project (res://addons/godot_pilot) and enables it in project.godot. launch_editor does this automatically; use this tool to update the addon in a project. An editor that already has the project open must be restarted (or the plugin turned off and on in Project Settings > Plugins) to load the new version.",
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

export const updateGodotPilotTool = defineTool({
  name: "update_godot_pilot",
  title: "Update Godot Pilot",
  description:
    "Downloads the newest Godot Pilot release from GitHub, checks its SHA-256 checksum and installs it in place of this program. Only call it when the person agreed to update. The new version runs after the person restarts the AI app (or reconnects the MCP server); then launch_editor updates the addon in the project.",
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
