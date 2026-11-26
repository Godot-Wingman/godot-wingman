/**
 * End-to-end tests of the phase 4 toolsets (animation, tilemap, ui, 3d, shader, audio,
 * import options, export) against a real, headless Godot editor. The tests run in order
 * and build on each other; the 3D tests come last because they open a new 3D scene.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { join } from "node:path";
import { ALL_TOOLSETS } from "../../server/src/tools/toolsets.ts";
import { startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

let editor: TestEditor | null = null;

beforeAll(async () => {
  editor = await startTestEditor({ initialToolsets: ALL_TOOLSETS.map((toolset) => toolset.name) });
}, 240_000);

afterAll(async () => {
  await editor?.stop();
}, 30_000);

async function callAndExpectSuccess(
  name: string,
  toolArguments: Record<string, unknown> = {},
): Promise<string> {
  if (!editor) throw new Error("No editor");
  const outcome = await editor.callTool(name, toolArguments);
  if (outcome.isError) {
    throw new Error(`${name} failed: ${outcome.text}`);
  }
  return outcome.text;
}

describe("animation", () => {
  test("create_animation makes tracks and keys that get_animation shows", async () => {
    if (!editor) return;
    await callAndExpectSuccess("add_node", { type: "AnimationPlayer", name: "AnimationPlayer" });
    const created = JSON.parse(
      await callAndExpectSuccess("create_animation", {
        node_path: "AnimationPlayer",
        animation: "bounce",
        length: 1,
        loop_mode: "linear",
        tracks: [
          {
            path: "Player:position",
            keys: [
              { time: 0, value: [100, 200] },
              { time: 1, value: [300, 200] },
            ],
          },
          { path: "Label:visible", update_mode: "discrete", keys: [{ time: 0.5, value: false }] },
        ],
      }),
    );
    expect(created.tracks).toBe(2);
    const animation = JSON.parse(
      await callAndExpectSuccess("get_animation", { node_path: "AnimationPlayer", animation: "bounce" }),
    );
    expect(animation.loop_mode).toBe("linear");
    expect(animation.tracks[0].path).toBe("Player:position");
    expect(animation.tracks[0].keys).toEqual(["0.0: Vector2(100, 200)", "1.0: Vector2(300, 200)"]);
    expect(animation.tracks[1].update_mode).toBe("discrete");
  });

  test("preview_animation shows the pose at a moment", async () => {
    if (!editor) return;
    const preview = JSON.parse(
      await callAndExpectSuccess("preview_animation", {
        node_path: "AnimationPlayer",
        animation: "bounce",
        time: 0.5,
      }),
    );
    expect(preview.values["Player:position"]).toBe("Vector2(200, 200)");
    await callAndExpectSuccess("preview_animation", {
      node_path: "AnimationPlayer",
      animation: "bounce",
      time: 0,
    });
  });

  test("edit_animation removes keys and checks value types", async () => {
    if (!editor) return;
    await callAndExpectSuccess("edit_animation", {
      node_path: "AnimationPlayer",
      animation: "bounce",
      remove_keys: [{ path: "Player:position", time: 1 }],
    });
    const animation = JSON.parse(
      await callAndExpectSuccess("get_animation", { node_path: "AnimationPlayer", animation: "bounce" }),
    );
    expect(animation.tracks[0].keys).toHaveLength(1);
    const wrongValue = await editor.callTool("edit_animation", {
      node_path: "AnimationPlayer",
      animation: "bounce",
      tracks: [{ path: "Player:position", keys: [{ time: 0.2, value: "not a vector" }] }],
    });
    expect(wrongValue.isError).toBe(true);
    expect(wrongValue.text).toContain("Vector2");
  });

  test("setup_animation_state_machine builds states and transitions", async () => {
    if (!editor) return;
    await callAndExpectSuccess("create_animation", {
      node_path: "AnimationPlayer",
      animation: "idle",
      length: 0.5,
    });
    await callAndExpectSuccess("add_node", { type: "AnimationTree", name: "AnimationTree" });
    const tree = JSON.parse(
      await callAndExpectSuccess("setup_animation_state_machine", {
        node_path: "AnimationTree",
        animation_player: "AnimationPlayer",
        states: [
          { name: "Idle", animation: "idle" },
          { name: "Bounce", animation: "bounce" },
        ],
        start_state: "Idle",
        transitions: [
          { from: "Idle", to: "Bounce", condition: "jumping" },
          { from: "Bounce", to: "Idle", switch_mode: "at_end" },
        ],
      }),
    );
    expect(tree.states).toContain("Idle (AnimationNodeAnimation) plays idle");
    expect(tree.transitions.join("\n")).toContain(
      "Idle -> Bounce (immediate, advance auto, condition jumping)",
    );
    expect(tree.transitions.join("\n")).toContain("Start -> Idle");
    expect(Object.keys(tree.parameters)).toContain("parameters/conditions/jumping");
    const listed = JSON.parse(await callAndExpectSuccess("list_animations"));
    expect(listed.players[0].animations.join("\n")).toContain("bounce (1.0 s, loop linear, 2 tracks)");
  });
});

describe("tilemap", () => {
  test("create_tileset makes tiles from a tile sheet and skips empty cells", async () => {
    if (!editor) return;
    // A 48x16 sheet: two colored tiles and one fully transparent tile.
    await callAndExpectSuccess("execute_editor_script", {
      code: [
        "var image := Image.create(48, 16, false, Image.FORMAT_RGBA8)",
        "image.fill_rect(Rect2i(0, 0, 16, 16), Color.RED)",
        "image.fill_rect(Rect2i(16, 0, 16, 16), Color.BLUE)",
        'ResourceSaver.save(ImageTexture.create_from_image(image), "res://tiles.res")',
      ].join("\n"),
    });
    await callAndExpectSuccess("add_node", { type: "TileMapLayer", name: "Ground" });
    const tileset = JSON.parse(
      await callAndExpectSuccess("create_tileset", {
        texture: "res://tiles.res",
        tile_size: [16, 16],
        collision: true,
        path: "res://tiles/world.tres",
        assign_to: "Ground",
      }),
    );
    expect(tileset.grid_size).toEqual([3, 1]);
    expect(tileset.tiles).toBeGreaterThanOrEqual(2);
    const information = JSON.parse(await callAndExpectSuccess("get_tilemap_info", { node_path: "Ground" }));
    expect(information.physics_layers).toBe(1);
    expect(information.sources[0].tiles).toContain("0,0");
  });

  test("set_tiles places rows and single tiles that get_tiles draws as a grid", async () => {
    if (!editor) return;
    const placed = JSON.parse(
      await callAndExpectSuccess("set_tiles", {
        node_path: "Ground",
        rectangles: [{ from: [0, 1], to: [4, 1], atlas: [0, 0] }],
        cells: [{ cell: [2, 0], atlas: [1, 0] }],
      }),
    );
    expect(placed.used_cells).toBe(6);
    const tiles = JSON.parse(await callAndExpectSuccess("get_tiles", { node_path: "Ground" }));
    expect(tiles.grid).toBe("..A..\nBBBBB");
    expect(tiles.legend).toEqual({ A: "source 0 atlas 1,0", B: "source 0 atlas 0,0" });
    const missingTile = await editor.callTool("set_tiles", {
      node_path: "Ground",
      cells: [{ cell: [0, 0], atlas: [9, 9] }],
    });
    expect(missingTile.isError).toBe(true);
    expect(missingTile.text).toContain("TILE_NOT_FOUND");
  });
});

describe("ui", () => {
  test("build_ui creates a whole menu in one call", async () => {
    if (!editor) return;
    await callAndExpectSuccess("add_node", { type: "CanvasLayer", name: "HUD" });
    const built = JSON.parse(
      await callAndExpectSuccess("build_ui", {
        parent_path: "HUD",
        nodes: [
          {
            type: "MarginContainer",
            name: "Menu",
            layout_preset: "full_rect",
            children: [
              {
                type: "VBoxContainer",
                name: "Items",
                children: [
                  {
                    type: "Label",
                    name: "Title",
                    properties: { text: "My Game" },
                    theme_overrides: { font_sizes: { font_size: 40 } },
                  },
                  { type: "Button", name: "Play", properties: { text: "Play" } },
                ],
              },
            ],
          },
        ],
      }),
    );
    expect(built.created).toContain("HUD/Menu/Items/Play (Button)");
    const layout = JSON.parse(await callAndExpectSuccess("get_ui_layout", { node_path: "HUD" }));
    const layoutText = layout.layout.join("\n");
    expect(layoutText).toContain("HUD/Menu (MarginContainer)");
    expect(layoutText).toContain("anchors=full_rect");
    expect(layoutText).toContain('text="Play"');
  });

  test("set_theme_overrides changes looks and lists valid item names on mistakes", async () => {
    if (!editor) return;
    const changed = JSON.parse(
      await callAndExpectSuccess("set_theme_overrides", {
        node_path: "HUD/Menu/Items/Title",
        colors: { font_color: "#ffcc00" },
      }),
    );
    expect(Object.keys(changed.changed)).toContain("theme_override_colors/font_color");
    const wrongItem = await editor.callTool("set_theme_overrides", {
      node_path: "HUD/Menu/Items/Title",
      colors: { text_color: "red" },
    });
    expect(wrongItem.isError).toBe(true);
    expect(wrongItem.text).toContain("font_color");
  });
});

describe("shader", () => {
  test("write_shader creates a shader, puts it on a node, and its uniforms can be set", async () => {
    if (!editor) return;
    const written = JSON.parse(
      await callAndExpectSuccess("write_shader", {
        path: "res://shaders/tint.gdshader",
        template: "canvas_item",
        assign_to: { node_path: "Player/Sprite2D" },
      }),
    );
    expect(written.uniforms).toContain("vec4 tint : source_color = vec4(1.0)");
    expect(written.assigned_to).toBe("Player/Sprite2D.material");
    await callAndExpectSuccess("set_shader_parameters", {
      node_path: "Player/Sprite2D",
      parameters: { tint: "#ff0000" },
    });
    const information = JSON.parse(
      await callAndExpectSuccess("get_shader_info", { node_path: "Player/Sprite2D" }),
    );
    expect(information.shader_type).toBe("canvas_item");
    expect(information.material_values.tint).toBe("Color(1, 0, 0, 1)");
    const unknownUniform = await editor.callTool("set_shader_parameters", {
      node_path: "Player/Sprite2D",
      parameters: { glow: 1 },
    });
    expect(unknownUniform.text).toContain("tint");
  });
});

describe("audio and import options", () => {
  test("edit_audio_buses adds buses and effects", async () => {
    if (!editor) return;
    const buses = JSON.parse(
      await callAndExpectSuccess("edit_audio_buses", {
        operations: [
          { action: "add", bus: "Music", volume_db: -6 },
          { action: "add_effect", bus: "Music", effect: "AudioEffectReverb", properties: { wet: 0.3 } },
        ],
      }),
    );
    const musicBus = buses.buses.find((bus: { name: string }) => bus.name === "Music");
    expect(musicBus.volume_db).toBe(-6);
    expect(musicBus.effects).toEqual(["0: AudioEffectReverb"]);
    expect(buses.layout_file).toBe("res://default_bus_layout.tres");
  });

  test("get_audio_file_info describes a sound", async () => {
    if (!editor) return;
    await callAndExpectSuccess("execute_editor_script", {
      code: [
        "var sound := AudioStreamWAV.new()",
        "sound.mix_rate = 22050",
        "sound.data = PackedByteArray()",
        "sound.data.resize(22050)",
        'ResourceSaver.save(sound, "res://beep.tres")',
      ].join("\n"),
    });
    const information = JSON.parse(
      await callAndExpectSuccess("get_audio_file_info", { path: "res://beep.tres" }),
    );
    expect(information.class).toBe("AudioStreamWAV");
    expect(information.mix_rate).toBe(22050);
  });

  test("reimport_files imports new images in a folder the editor has not scanned yet", async () => {
    if (!editor) return;
    await callAndExpectSuccess("execute_editor_script", {
      code: [
        'DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://new_art"))',
        "var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)",
        "image.fill(Color.GREEN)",
        'image.save_png("res://new_art/green.png")',
      ].join("\n"),
    });
    const imported = JSON.parse(
      await callAndExpectSuccess("reimport_files", { paths: ["res://new_art/green.png"] }),
    );
    expect(imported.imported["res://new_art/green.png"]).toBe("CompressedTexture2D");
  });

  test("set_import_options changes how an image is imported", async () => {
    if (!editor) return;
    const options = JSON.parse(
      await callAndExpectSuccess("get_import_options", { path: "res://new_art/green.png" }),
    );
    expect(options.importer).toBe("texture");
    expect(options.options["mipmaps/generate"]).toBe(false);
    const changed = JSON.parse(
      await callAndExpectSuccess("set_import_options", {
        path: "res://new_art/green.png",
        options: { "mipmaps/generate": true },
      }),
    );
    expect(changed.changed["mipmaps/generate"]).toBe(true);
  });
});

describe("export", () => {
  test("add_export_preset and list_export_presets manage presets", async () => {
    if (!editor) return;
    await callAndExpectSuccess("add_export_preset", {
      platform: "Linux",
      export_path: "build/linux/game.x86_64",
    });
    const presets = JSON.parse(await callAndExpectSuccess("list_export_presets"));
    expect(presets.presets).toEqual([
      { name: "Linux", platform: "Linux", export_path: "build/linux/game.x86_64", runnable: true },
    ]);
    expect(typeof presets.export_templates.installed).toBe("boolean");
  });

  test("export_project builds a pack in a separate Godot process", async () => {
    if (!editor) return;
    const report = JSON.parse(
      await callAndExpectSuccess("export_project", {
        preset: "Linux",
        mode: "pack",
        output_path: "build/game.pck",
      }),
    );
    expect(report.exit_code).toBe(0);
    expect(report.output_size_bytes).toBeGreaterThan(0);
    // The export loads the addon too, but must not start a second AI bridge.
    expect(report.log_tail.join("\n")).not.toContain("ready for AI connections");
    // Nothing of the addon may end up in the game: no file, no autoload, no plugin code.
    const packText = new TextDecoder("latin1").decode(
      await Bun.file(join(editor.projectPath, "build", "game.pck")).arrayBuffer(),
    );
    expect(packText).toContain("main.tscn");
    // Only the editor_plugins setting may name the addon; games ignore editor plugins.
    expect(packText).not.toMatch(/godot_pilot\/[\w/]+\.(gd|gdc|remap|tscn|tres)\b/);
    expect(packText).not.toContain("GodotPilotGameBridge");
  }, 180_000);

  test("export_project explains missing export templates", async () => {
    if (!editor) return;
    const presets = JSON.parse(await callAndExpectSuccess("list_export_presets"));
    if (presets.export_templates.installed) return;
    const outcome = await editor.callTool("export_project", {
      preset: "Linux",
      output_path: "build/linux/game.x86_64",
    });
    expect(outcome.isError).toBe(true);
    expect(outcome.text).toContain("export templates");
  });
});

describe("3d", () => {
  test("add_mesh adds a box inside a static body with a matching shape", async () => {
    if (!editor) return;
    await callAndExpectSuccess("create_scene", {
      path: "res://world.tscn",
      root_type: "Node3D",
      root_name: "World",
    });
    const added = JSON.parse(
      await callAndExpectSuccess("add_mesh", {
        shape: "box",
        name: "Floor",
        size: [10, 1, 4],
        position: [0, -0.5, 0],
        color: "#3a7d44",
        body: "static",
      }),
    );
    expect(added.class).toBe("StaticBody3D");
    expect(added.children[1]).toContain("BoxShape3D size (10.0, 1.0, 4.0)");
    const bounds = JSON.parse(await callAndExpectSuccess("get_bounds", { node_path: "Floor" }));
    expect(bounds.size).toEqual([10, 1, 4]);
    expect(bounds.min).toEqual([-5, -1, -2]);
  });

  test("generate_collision makes shapes from meshes", async () => {
    if (!editor) return;
    await callAndExpectSuccess("add_mesh", { shape: "sphere", name: "Rock", position: [2, 0.5, 0] });
    const collision = JSON.parse(
      await callAndExpectSuccess("generate_collision", { node_path: "Rock", shape: "convex" }),
    );
    expect(collision.shapes).toHaveLength(1);
    expect(collision.body).toBe("Rock/StaticBody");
  });

  test("look_at aims a camera and setup_environment adds sky and sun", async () => {
    if (!editor) return;
    await callAndExpectSuccess("add_node", { type: "Camera3D", name: "Camera3D" });
    const aimed = JSON.parse(
      await callAndExpectSuccess("look_at", {
        node_path: "Camera3D",
        position: [0, 5, 5],
        target: [0, 0, 0],
      }),
    );
    expect(aimed.rotation_degrees[0]).toBeCloseTo(-45, 1);
    expect(aimed.distance_to_target).toBeCloseTo(7.071, 2);
    const environment = JSON.parse(await callAndExpectSuccess("setup_environment", { preset: "sunset" }));
    expect(environment.world_environment).toBe("added WorldEnvironment");
    expect(environment.sun).toBe("added Sun (DirectionalLight3D)");
    const again = JSON.parse(await callAndExpectSuccess("setup_environment", { preset: "night" }));
    expect(again.sun).toBe("updated Sun");
  });
});
