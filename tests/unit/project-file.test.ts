import { describe, expect, test } from "bun:test";
import { addEnabledEditorPlugin, parsePackedStringArray } from "../../server/src/addon/project-file.ts";

const PLUGIN = "res://addons/godot_pilot/plugin.cfg";

describe("addEnabledEditorPlugin", () => {
  test("adds the section when the project has no plugins", () => {
    const { text, changed } = addEnabledEditorPlugin(
      'config_version=5\n\n[application]\n\nconfig/name="Game"\n',
      PLUGIN,
    );
    expect(changed).toBe(true);
    expect(text).toContain(`[editor_plugins]\n\nenabled=PackedStringArray("${PLUGIN}")`);
    expect(text).toContain('config/name="Game"');
  });

  test("keeps other enabled plugins", () => {
    const original =
      '[editor_plugins]\n\nenabled=PackedStringArray("res://addons/other/plugin.cfg")\n\n[rendering]\n';
    const { text } = addEnabledEditorPlugin(original, PLUGIN);
    expect(text).toContain(`enabled=PackedStringArray("res://addons/other/plugin.cfg", "${PLUGIN}")`);
    expect(text).toContain("[rendering]");
  });

  test("changes nothing when the plugin is already enabled", () => {
    const original = `[editor_plugins]\n\nenabled=PackedStringArray("${PLUGIN}")\n`;
    expect(addEnabledEditorPlugin(original, PLUGIN)).toEqual({ text: original, changed: false });
  });

  test("keeps Windows line endings", () => {
    const { text } = addEnabledEditorPlugin("[editor_plugins]\r\n\r\n[other]\r\n", PLUGIN);
    expect(text).toContain("\r\n");
    expect(text).not.toMatch(/[^\r]\n/);
  });
});

test("parsePackedStringArray reads quoted items", () => {
  expect(parsePackedStringArray('PackedStringArray("a", "b c")')).toEqual(["a", "b c"]);
  expect(parsePackedStringArray("PackedStringArray()")).toEqual([]);
});
