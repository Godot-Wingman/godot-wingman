/**
 * Predefined selections of toolsets. Names that do not exist yet are ignored, so a
 * profile can mention toolsets that arrive in later versions.
 */
export interface ToolsetProfile {
  description: string;
  toolsets: string[] | "all";
}

export const DEFAULT_TOOLSET_NAMES = ["core", "scene", "inspector", "script", "project"];

export const TOOLSET_PROFILES: Record<string, ToolsetProfile> = {
  minimal: {
    description: "Only the core tools (status, editor scripts, logs, screenshots, docs).",
    toolsets: ["core"],
  },
  default: {
    description: "Everyday editing: scenes, inspector, scripts, project settings.",
    toolsets: DEFAULT_TOOLSET_NAMES,
  },
  edit: {
    description:
      "General editing (signals, resources, files, viewport) without playtesting or the specialised toolsets (animation, tilemap, ui, 3d...).",
    toolsets: [
      "core",
      "scene",
      "inspector",
      "script",
      "project",
      "signals",
      "resources",
      "filesystem",
      "viewport",
    ],
  },
  "2d": {
    description:
      "Building and testing a 2D game: editing, signals, resources, tilemaps, animation, UI and playtesting.",
    toolsets: [
      "core",
      "scene",
      "inspector",
      "script",
      "project",
      "signals",
      "resources",
      "filesystem",
      "animation",
      "tilemap",
      "ui",
      "play",
      "input",
      "game_inspect",
    ],
  },
  "3d": {
    description:
      "Building and testing a 3D game: editing, 3D helpers, materials and shaders, animation, UI and playtesting.",
    toolsets: [
      "core",
      "scene",
      "inspector",
      "script",
      "project",
      "signals",
      "resources",
      "filesystem",
      "viewport",
      "3d",
      "shader",
      "animation",
      "ui",
      "play",
      "input",
      "game_inspect",
    ],
  },
  play: {
    description: "Playtesting: run the game, send real input, inspect it live, read errors.",
    toolsets: ["core", "scene", "script", "play", "input", "game_inspect", "debug"],
  },
  all: {
    description: "Every toolset. Uses the most context.",
    toolsets: "all",
  },
};
