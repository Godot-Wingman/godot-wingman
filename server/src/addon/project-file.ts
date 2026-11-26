/**
 * Small, careful edits to a Godot `project.godot` file.
 *
 * The file looks like an INI file:
 *
 *   [editor_plugins]
 *
 *   enabled=PackedStringArray("res://addons/a/plugin.cfg", "res://addons/b/plugin.cfg")
 *
 * We only touch the one line we need and leave everything else exactly as it was.
 */

const EDITOR_PLUGINS_SECTION = "[editor_plugins]";
const ENABLED_PLUGINS_KEY = "enabled=";

/** Adds `pluginConfigPath` to the list of enabled editor plugins. */
export function addEnabledEditorPlugin(
  projectFileText: string,
  pluginConfigPath: string,
): { text: string; changed: boolean } {
  const lineBreak = projectFileText.includes("\r\n") ? "\r\n" : "\n";
  const lines = projectFileText.split(/\r?\n/);
  const sectionLineIndex = lines.findIndex((line) => line.trim() === EDITOR_PLUGINS_SECTION);

  if (sectionLineIndex === -1) {
    const trimmedText = projectFileText.replace(/\s+$/, "");
    const addedSection = [
      "",
      "",
      EDITOR_PLUGINS_SECTION,
      "",
      `${ENABLED_PLUGINS_KEY}${formatPackedStringArray([pluginConfigPath])}`,
      "",
    ].join(lineBreak);
    return { text: trimmedText + addedSection, changed: true };
  }

  const sectionEndIndex = findSectionEnd(lines, sectionLineIndex);
  for (let lineIndex = sectionLineIndex + 1; lineIndex < sectionEndIndex; lineIndex++) {
    const line = lines[lineIndex] ?? "";
    if (!line.startsWith(ENABLED_PLUGINS_KEY)) {
      continue;
    }
    const enabledPlugins = parsePackedStringArray(line.slice(ENABLED_PLUGINS_KEY.length));
    if (enabledPlugins.includes(pluginConfigPath)) {
      return { text: projectFileText, changed: false };
    }
    lines[lineIndex] =
      `${ENABLED_PLUGINS_KEY}${formatPackedStringArray([...enabledPlugins, pluginConfigPath])}`;
    return { text: lines.join(lineBreak), changed: true };
  }

  // The section exists but has no "enabled=" line yet.
  lines.splice(
    sectionLineIndex + 1,
    0,
    "",
    `${ENABLED_PLUGINS_KEY}${formatPackedStringArray([pluginConfigPath])}`,
  );
  return { text: lines.join(lineBreak), changed: true };
}

/** Removes `pluginConfigPath` from the list of enabled editor plugins, if it is there. */
export function removeEnabledEditorPlugin(
  projectFileText: string,
  pluginConfigPath: string,
): { text: string; changed: boolean } {
  const lineBreak = projectFileText.includes("\r\n") ? "\r\n" : "\n";
  const lines = projectFileText.split(/\r?\n/);
  const sectionLineIndex = lines.findIndex((line) => line.trim() === EDITOR_PLUGINS_SECTION);
  if (sectionLineIndex === -1) {
    return { text: projectFileText, changed: false };
  }
  const sectionEndIndex = findSectionEnd(lines, sectionLineIndex);
  for (let lineIndex = sectionLineIndex + 1; lineIndex < sectionEndIndex; lineIndex++) {
    const line = lines[lineIndex] ?? "";
    if (!line.startsWith(ENABLED_PLUGINS_KEY)) {
      continue;
    }
    const enabledPlugins = parsePackedStringArray(line.slice(ENABLED_PLUGINS_KEY.length));
    if (!enabledPlugins.includes(pluginConfigPath)) {
      return { text: projectFileText, changed: false };
    }
    const remainingPlugins = enabledPlugins.filter((plugin) => plugin !== pluginConfigPath);
    lines[lineIndex] = `${ENABLED_PLUGINS_KEY}${formatPackedStringArray(remainingPlugins)}`;
    return { text: lines.join(lineBreak), changed: true };
  }
  return { text: projectFileText, changed: false };
}

export function isEditorPluginEnabled(projectFileText: string, pluginConfigPath: string): boolean {
  return addEnabledEditorPlugin(projectFileText, pluginConfigPath).changed === false;
}

/** Index of the first line after the section that starts at `sectionLineIndex`. */
function findSectionEnd(lines: string[], sectionLineIndex: number): number {
  for (let lineIndex = sectionLineIndex + 1; lineIndex < lines.length; lineIndex++) {
    if (/^\[.+\]\s*$/.test(lines[lineIndex] ?? "")) {
      return lineIndex;
    }
  }
  return lines.length;
}

/** `PackedStringArray("a", "b")` -> ["a", "b"]. */
export function parsePackedStringArray(value: string): string[] {
  return [...value.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((match) => (match[1] ?? "").replaceAll('\\"', '"'));
}

function formatPackedStringArray(items: string[]): string {
  return `PackedStringArray(${items.map((item) => `"${item.replaceAll('"', '\\"')}"`).join(", ")})`;
}
