/**
 * Names and versions of the product, kept in one place.
 *
 * Versions 0.1 to 0.3 were called Godot Pilot. A rename means changing this file, the addon
 * folder name (addon/godot_wingman) and the matching constants in the addon's
 * bridge/editor_registry_file.gd.
 */
import packageJson from "../../package.json" with { type: "json" };

/** Used for folders, file names and the MCP server name. */
export const PRODUCT_NAME = "godot-wingman";

/** Shown to people. */
export const PRODUCT_DISPLAY_NAME = "Godot Wingman";

export const PRODUCT_VERSION: string = packageJson.version;

/** Folder of the addon inside a Godot project: res://addons/<this>. */
export const ADDON_FOLDER_NAME = "godot_wingman";

export const ADDON_PLUGIN_CONFIG_RESOURCE_PATH = `res://addons/${ADDON_FOLDER_NAME}/plugin.cfg`;

/** Moves all of our files (editor registry, caches, settings) to another folder. Used by tests. */
export const HOME_OVERRIDE_ENVIRONMENT_VARIABLE = "GODOT_WINGMAN_HOME";

/** Points to a Godot executable when it cannot be found automatically. */
export const GODOT_PATH_ENVIRONMENT_VARIABLE = "GODOT_PATH";

/** GitHub repository ("owner/name") whose releases are checked for updates. */
export const PRODUCT_REPOSITORY = "Godot-wingman/godot-wingman";
