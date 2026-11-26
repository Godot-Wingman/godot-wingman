/**
 * The "shader" toolset (.gdshader files and ShaderMaterial values), the "audio" toolset
 * (buses and sound files), the import option tools of the "filesystem" toolset, and the
 * "export" toolset (presets, templates and building the game).
 */
import { mkdir } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";
import { z } from "zod";
import { getConsoleVariant } from "../../godot/find-godot-executable.ts";
import { defineEditorTool, defineTool, errorResult, jsonResult } from "../../mcp/tool-definition.ts";
import { nodePathField, resourcePathField } from "../shared-schemas.ts";

const materialLocationShape = {
  node_path: nodePathField.optional().describe("A node with a ShaderMaterial..."),
  property: z
    .string()
    .optional()
    .describe('...in this property. Default: "material" (2D) or "material_override" (3D).'),
  path: resourcePathField.optional().describe("Or: a .gdshader, or a ShaderMaterial .tres file."),
};

export const writeShaderTool = defineEditorTool({
  name: "write_shader",
  title: "Write shader",
  description:
    'Creates or replaces a .gdshader file (Godot shading language, close to GLSL), reports compile errors when the editor has a renderer, and can put it on a node in a new ShaderMaterial. Without code it starts from a template. Example: {"path": "res://shaders/flash.gdshader", "code": "shader_type canvas_item;\\nuniform vec4 flash_color : source_color = vec4(1.0);\\nuniform float amount : hint_range(0.0, 1.0) = 0.0;\\nvoid fragment() {\\n\\tvec4 base = texture(TEXTURE, UV);\\n\\tCOLOR = vec4(mix(base.rgb, flash_color.rgb, amount), base.a);\\n}", "assign_to": {"node_path": "Player/Sprite2D"}}.',
  inputShape: {
    path: resourcePathField.describe("Must end in .gdshader."),
    code: z.string().optional(),
    template: z.enum(["canvas_item", "spatial", "particles", "sky", "fog"]).optional(),
    assign_to: z.object({ node_path: nodePathField, property: z.string().optional() }).optional(),
  },
  access: "write",
  editorMethod: "write_shader",
});

export const getShaderInfoTool = defineEditorTool({
  name: "get_shader_info",
  title: "Get shader info",
  description:
    "Shows a shader's type and uniforms (type, hints, default), and for a ShaderMaterial the values it sets. Read the code itself with read_file.",
  inputShape: materialLocationShape,
  access: "read",
  editorMethod: "get_shader_info",
});

export const setShaderParametersTool = defineEditorTool({
  name: "set_shader_parameters",
  title: "Set shader parameters",
  description:
    'Sets uniform values of a ShaderMaterial (on a node or in a file). Values follow the uniform type: numbers, [x, y], colors "#ff8800" for source_color, "res://..." for textures. Undoable.',
  inputShape: { ...materialLocationShape, parameters: z.record(z.string(), z.unknown()) },
  access: "write",
  editorMethod: "set_shader_parameters",
});

export const SHADER_TOOLS = [writeShaderTool, getShaderInfoTool, setShaderParametersTool];

export const getAudioBusesTool = defineEditorTool({
  name: "get_audio_buses",
  title: "Get audio buses",
  description: "Lists the audio buses (Master, Music, SFX...) with volume, mute, solo, send and effects.",
  inputShape: {},
  access: "read",
  editorMethod: "get_audio_buses",
});

export const editAudioBusesTool = defineEditorTool({
  name: "edit_audio_buses",
  title: "Edit audio buses",
  description:
    'Adds, removes and changes audio buses and their effects, in order, then saves the bus layout file. Example: {"operations": [{"action": "add", "bus": "Music", "volume_db": -6}, {"action": "add", "bus": "SFX"}, {"action": "add_effect", "bus": "SFX", "effect": "AudioEffectReverb", "properties": {"wet": 0.2}}]}. Sound players choose a bus with their "bus" property.',
  inputShape: {
    operations: z
      .array(
        z.object({
          action: z.enum(["add", "remove", "set", "add_effect", "remove_effect"]),
          bus: z.string(),
          rename: z.string().optional(),
          volume_db: z.number().optional(),
          mute: z.boolean().optional(),
          solo: z.boolean().optional(),
          bypass_effects: z.boolean().optional(),
          send: z.string().optional().describe("Bus this one feeds into. Default Master."),
          effect: z.string().optional().describe("AudioEffect class for add_effect."),
          properties: z.record(z.string(), z.unknown()).optional(),
          effect_index: z.number().int().optional().describe("For remove_effect."),
        }),
      )
      .min(1),
  },
  access: "write",
  editorMethod: "edit_audio_buses",
});

export const getAudioFileInfoTool = defineEditorTool({
  name: "get_audio_file_info",
  title: "Get sound file info",
  description: "Length, format, loop settings and import options of a sound file (.ogg, .wav, .mp3).",
  inputShape: { path: resourcePathField },
  access: "read",
  editorMethod: "get_audio_file_info",
});

export const AUDIO_TOOLS = [getAudioBusesTool, editAudioBusesTool, getAudioFileInfoTool];

export const getImportOptionsTool = defineEditorTool({
  name: "get_import_options",
  title: "Get import options",
  description:
    "Shows how an asset is imported (the Import dock): texture compression and mipmaps, sound looping, 3D model scale and materials...",
  inputShape: { path: resourcePathField },
  access: "read",
  editorMethod: "get_import_options",
});

export const setImportOptionsTool = defineEditorTool({
  name: "set_import_options",
  title: "Set import options",
  description:
    'Changes import options of an asset and reimports it, like the Import dock\'s Reimport button. Examples: looping music {"path": "res://music.ogg", "options": {"loop": true}}; a wav: {"edit/loop_mode": 1}. Option names come from get_import_options. (Pixel-art filtering is the project setting rendering/textures/canvas_textures/default_texture_filter.)',
  inputShape: { path: resourcePathField, options: z.record(z.string(), z.unknown()) },
  access: "write",
  editorMethod: "set_import_options",
  timeoutSeconds: 120,
});

export const IMPORT_TOOLS = [getImportOptionsTool, setImportOptionsTool];

export const listExportPresetsTool = defineEditorTool({
  name: "list_export_presets",
  title: "List export presets",
  description:
    "Lists the export presets (platform, output path) and checks that the export templates for this Godot version are installed.",
  inputShape: {},
  access: "read",
  editorMethod: "list_export_presets",
});

export const addExportPresetTool = defineEditorTool({
  name: "add_export_preset",
  title: "Add export preset",
  description:
    'Adds an export preset for a platform with default options. export_path is relative to the project folder, e.g. "build/windows/game.exe".',
  inputShape: {
    platform: z.enum(["Windows Desktop", "Linux", "macOS", "Web", "Android", "iOS"]),
    name: z.string().optional().describe("Default: the platform name."),
    export_path: z.string().optional(),
    runnable: z.boolean().optional(),
  },
  access: "write",
  editorMethod: "add_export_preset",
});

const EXPORT_MODE_FLAGS = {
  release: "--export-release",
  debug: "--export-debug",
  pack: "--export-pack",
} as const;
const ANSI_ESCAPE_PATTERN = new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*m`, "g");
const OUTPUT_TAIL_LINE_COUNT = 40;

interface ExportPresetList {
  presets: { name: string; platform: string; export_path: string }[];
  export_templates: { installed: boolean; folder: string };
}

export const exportProjectTool = defineTool({
  name: "export_project",
  title: "Export (build) the game",
  description:
    "Builds the game with an export preset, in a separate headless Godot process, and reports the result. Open scenes are saved first. release is the finished game, debug keeps debugging on, pack only makes the .pck/.zip of game data. release and debug need installed export templates (list_export_presets).",
  inputShape: {
    preset: z.string().describe("Export preset name (list_export_presets)."),
    mode: z.enum(["release", "debug", "pack"]).optional(),
    output_path: z
      .string()
      .optional()
      .describe("Relative to the project folder. Default: the preset's export_path."),
    timeout_seconds: z.number().int().min(10).max(3600).optional().describe("Default 600."),
  },
  access: "write",
  async run(input, context) {
    const registration = await context.editors.getActiveRegistration();
    const presetList = await context.editors.request<ExportPresetList>("list_export_presets");
    const preset = presetList.presets.find((candidate) => candidate.name === input.preset);
    if (!preset) {
      const names = presetList.presets.map((candidate) => candidate.name).join(", ") || "none";
      return errorResult(
        `There is no export preset named "${input.preset}".`,
        `Presets: ${names}. Add one with add_export_preset.`,
      );
    }
    // A pack holds only the game data, so it needs no templates.
    if (input.mode !== "pack" && !presetList.export_templates.installed) {
      return errorResult(
        "The export templates for this Godot version are not installed.",
        "Install them in the editor: Editor > Manage Export Templates > Download and Install. Then try again.",
        { expected_folder: presetList.export_templates.folder },
      );
    }
    const outputPath = input.output_path ?? preset.export_path;
    if (!outputPath) {
      return errorResult(
        "The preset has no export path.",
        'Pass output_path, e.g. "build/windows/game.exe".',
      );
    }
    await context.editors.request("save_all_scenes");

    const absoluteOutputPath = isAbsolute(outputPath)
      ? outputPath
      : resolve(registration.projectPath, outputPath);
    await mkdir(dirname(absoluteOutputPath), { recursive: true });
    const godotProcess = Bun.spawn(
      [
        getConsoleVariant(registration.godotExecutable),
        "--headless",
        "--path",
        registration.projectPath,
        EXPORT_MODE_FLAGS[input.mode ?? "release"],
        preset.name,
        absoluteOutputPath,
      ],
      { stdout: "pipe", stderr: "pipe" },
    );
    const timeoutMilliseconds = (input.timeout_seconds ?? 600) * 1000;
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      godotProcess.kill();
    }, timeoutMilliseconds);
    const [standardOutput, standardError, exitCode] = await Promise.all([
      new Response(godotProcess.stdout).text(),
      new Response(godotProcess.stderr).text(),
      godotProcess.exited,
    ]);
    clearTimeout(timer);

    const outputLines = `${standardOutput}\n${standardError}`
      .replace(ANSI_ESCAPE_PATTERN, "")
      .split(/\r?\n/)
      .filter((line) => line.trim() !== "");
    const errorLines = outputLines.filter((line) => /\bERROR\b|error:/i.test(line));
    const outputFile = Bun.file(absoluteOutputPath);
    const outputExists = await outputFile.exists();
    const report = {
      preset: preset.name,
      platform: preset.platform,
      output: absoluteOutputPath,
      output_size_bytes: outputExists ? outputFile.size : null,
      exit_code: exitCode,
      errors: errorLines.slice(-20),
      log_tail: outputLines.slice(-OUTPUT_TAIL_LINE_COUNT),
    };
    if (timedOut) {
      return errorResult(
        `The export did not finish within ${timeoutMilliseconds / 1000} seconds and was stopped.`,
        "Pass a larger timeout_seconds for big projects.",
        report,
      );
    }
    if (exitCode !== 0 || !outputExists) {
      return errorResult(
        "The export failed.",
        "Read errors and log_tail. Common causes: missing templates, a wrong preset option, or a script error.",
        report,
      );
    }
    return jsonResult(report);
  },
});

export const EXPORT_TOOLS = [listExportPresetsTool, addExportPresetTool, exportProjectTool];
