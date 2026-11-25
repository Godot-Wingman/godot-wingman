/**
 * End-to-end tests of the editing toolsets (scene, inspector, script, project, signals,
 * resources, filesystem, viewport) against a real, headless Godot editor.
 * The tests run in order and build on each other, like a person working in the editor.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { ALL_TOOLSETS } from "../../server/src/tools/toolsets.ts";
import { parseJson, startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

let editor: TestEditor | null = null;

beforeAll(async () => {
  editor = await startTestEditor({ initialToolsets: ALL_TOOLSETS.map((toolset) => toolset.name) });
}, 240_000);

afterAll(async () => {
  await editor?.stop();
}, 30_000);

describe("scene and inspector", () => {
  test("get_scene_tree shows nodes with scripts", async () => {
    if (!editor) return;
    const tree = parseJson<{ tree: string }>(await editor.callTool("get_scene_tree"));
    expect(tree.tree).toContain("Main (Node2D)");
    expect(tree.tree).toContain("Player (CharacterBody2D) script=res://player.gd");
  });

  test("add_node creates a node with converted property values", async () => {
    if (!editor) return;
    const added = await editor.callTool("add_node", {
      parent_path: "Player",
      type: "Sprite2D",
      name: "Hat",
      properties: { position: [10, -20], modulate: "#ff0000" },
    });
    expect(added.isError).toBe(false);
    const properties = parseJson<{ properties: string[] }>(
      await editor.callTool("get_properties", { node_path: "Player/Hat", names: ["position", "modulate"] }),
    );
    expect(properties.properties).toContain("position: Vector2 = Vector2(10, -20)");
    expect(properties.properties.join("\n")).toContain("Color(1, 0, 0, 1)");
  });

  test("set_properties creates sub-resources and edits their properties", async () => {
    if (!editor) return;
    const outcome = await editor.callTool("set_properties", {
      node_path: "Player/CollisionShape2D",
      properties: { shape: "CircleShape2D" },
    });
    expect(outcome.isError).toBe(false);
    const radius = await editor.callTool("set_properties", {
      node_path: "Player/CollisionShape2D",
      properties: { "shape:radius": 24 },
    });
    expect(parseJson<{ changed: Record<string, unknown> }>(radius).changed["shape:radius"]).toBe(24);
  });

  test("set_properties rejects unknown properties and suggests names", async () => {
    if (!editor) return;
    const outcome = await editor.callTool("set_properties", { node_path: "Player", properties: { postion: [1, 2] } });
    expect(outcome.isError).toBe(true);
    expect(outcome.text).toContain("position");
  });

  test("changes can be undone like Ctrl+Z", async () => {
    if (!editor) return;
    await editor.callTool("set_properties", { node_path: "Label", properties: { text: "Changed" } });
    await editor.callTool("execute_editor_script", {
      code: "undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(scene_root)).undo()",
    });
    const properties = parseJson<{ properties: string[] }>(
      await editor.callTool("get_properties", { node_path: "Label", names: ["text"] }),
    );
    expect(properties.properties).toContain('text: String = "Hello"');
  });

  test("batch_edit runs several operations in order", async () => {
    if (!editor) return;
    const outcome = parseJson<{ completed: number }>(
      await editor.callTool("batch_edit", {
        operations: [
          { action: "add_node", type: "Node2D", name: "Coins" },
          { action: "add_node", type: "Sprite2D", name: "Coin", parent_path: "Coins" },
          { action: "duplicate_node", node_path: "Coins/Coin", new_name: "Coin2" },
          { action: "set_properties", node_path: "Coins/Coin2", properties: { position: [64, 0] } },
          { action: "rename_node", node_path: "Coins", new_name: "Pickups" },
        ],
      }),
    );
    expect(outcome.completed).toBe(5);
    const tree = parseJson<{ tree: string }>(await editor.callTool("get_scene_tree", { node_path: "Pickups" }));
    expect(tree.tree).toContain("Coin2 (Sprite2D)");
  });

  test("move_node and delete_nodes change the tree", async () => {
    if (!editor) return;
    const moved = await editor.callTool("move_node", { node_path: "Pickups/Coin", new_parent_path: "." });
    expect(moved.isError).toBe(false);
    await editor.callTool("delete_nodes", { node_paths: ["Coin"] });
    const tree = parseJson<{ tree: string }>(await editor.callTool("get_scene_tree"));
    expect(tree.tree).not.toMatch(/^ {2}Coin \(/m);
  });

  test("save_scene writes the new nodes to the file", async () => {
    if (!editor) return;
    expect((await editor.callTool("save_scene")).isError).toBe(false);
    const file = parseJson<{ content: string }>(await editor.callTool("read_file", { path: "res://main.tscn" }));
    expect(file.content).toContain('name="Hat"');
    expect(file.content).toContain("CircleShape2D");
  });
});

describe("scripts and signals", () => {
  test("create_script attaches a valid script", async () => {
    if (!editor) return;
    const created = parseJson<{ valid: boolean; attached_to: string }>(
      await editor.callTool("create_script", {
        path: "res://scripts/main.gd",
        content: "extends Node2D\n\n\nfunc _ready() -> void:\n\tprint(\"ready\")\n",
        attach_to: ".",
      }),
    );
    expect(created.valid).toBe(true);
    expect(created.attached_to).toBe(".");
  });

  test("edit_script reports parse errors with line numbers", async () => {
    if (!editor) return;
    const edited = parseJson<{ valid: boolean; problems: { line: number }[] }>(
      await editor.callTool("edit_script", {
        path: "res://scripts/main.gd",
        old_text: '\tprint("ready")',
        new_text: "\tvar broken = ",
      }),
    );
    expect(edited.valid).toBe(false);
    expect(edited.problems[0]?.line).toBe(5);
    await editor.callTool("edit_script", { path: "res://scripts/main.gd", old_text: "\tvar broken = ", new_text: "\tpass" });
  });

  test("connect_signal adds the handler method to the script", async () => {
    if (!editor) return;
    await editor.callTool("add_node", { type: "Button", name: "StartButton" });
    const connected = parseJson<{ method_created_in_script: boolean }>(
      await editor.callTool("connect_signal", {
        from_node: "StartButton",
        signal: "pressed",
        to_node: ".",
        method: "_on_start_pressed",
      }),
    );
    expect(connected.method_created_in_script).toBe(true);
    const script = parseJson<{ content: string }>(await editor.callTool("read_script", { path: "res://scripts/main.gd" }));
    expect(script.content).toContain("func _on_start_pressed() -> void:");
    const signals = parseJson<{ signals: { signal: string; connected_to?: string[] }[] }>(
      await editor.callTool("list_signals", { node_path: "StartButton", only_connected: true }),
    );
    expect(signals.signals[0]?.connected_to?.[0]).toBe("_on_start_pressed() on .");
  });
});

describe("project, resources and files", () => {
  test("set_input_action creates an action with keys and buttons", async () => {
    if (!editor) return;
    await editor.callTool("set_input_action", { name: "jump", events: ["key:Space", "joy_button:a"] });
    const inputMap = parseJson<{ actions: Record<string, { events: string[] }> }>(await editor.callTool("get_input_map"));
    expect(inputMap.actions.jump?.events).toEqual(["key:Space", "joy_button:a"]);
  });

  test("set_project_settings changes and saves settings", async () => {
    if (!editor) return;
    await editor.callTool("set_project_settings", { settings: { "display/window/size/viewport_width": 1280 } });
    const settings = parseJson<{ settings: Record<string, unknown> }>(
      await editor.callTool("get_project_settings", { names: ["display/window/size/viewport_width"] }),
    );
    expect(settings.settings["display/window/size/viewport_width"]).toBe(1280);
  });

  test("create_resource saves a material and reads it back", async () => {
    if (!editor) return;
    await editor.callTool("create_resource", {
      type: "StandardMaterial3D",
      path: "res://materials/grass.tres",
      properties: { albedo_color: "#3a7d44", roughness: 0.8 },
    });
    const material = parseJson<{ properties: string[] }>(
      await editor.callTool("get_resource_properties", { path: "res://materials/grass.tres" }),
    );
    expect(material.properties.join("\n")).toContain("roughness: float");
  });

  test("list_files, search_project and move_file work on project files", async () => {
    if (!editor) return;
    const files = parseJson<{ files: string[] }>(await editor.callTool("list_files", { filter: "*.tscn" }));
    expect(files.files.some((entry) => entry.startsWith("res://main.tscn"))).toBe(true);

    const search = parseJson<{ matches: string[] }>(await editor.callTool("search_project", { query: "SPEED" }));
    expect(search.matches.some((match) => match.startsWith("res://player.gd:"))).toBe(true);

    await editor.callTool("write_file", { path: "res://data/levels.json", content: '{"levels": 3}' });
    const moved = parseJson<{ to: string }>(
      await editor.callTool("move_file", { from: "res://data/levels.json", to: "res://data/level_list.json" }),
    );
    expect(moved.to).toBe("res://data/level_list.json");
  });

  test("render_view explains that headless editors cannot render", async () => {
    if (!editor) return;
    const outcome = await editor.callTool("render_view");
    expect(outcome.isError).toBe(true);
    expect(outcome.text).toContain("NO_DISPLAY");
  });
});
