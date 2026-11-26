/**
 * End-to-end tests of the playtesting toolsets: the editor starts the real game, and the
 * tests play it with real input events and look inside it, like a person testing.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { join } from "node:path";
import { parseJson, startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

let editor: TestEditor | null = null;

beforeAll(async () => {
  editor = await startTestEditor({ initialToolsets: ["core", "play", "input", "game_inspect", "debug"] });
  if (editor) {
    const started = await editor.callTool("run_game");
    if (started.isError) {
      throw new Error(`run_game failed: ${started.text}`);
    }
  }
}, 300_000);

afterAll(async () => {
  await editor?.callTool("stop_game");
  await editor?.stop();
}, 30_000);

async function readPlayerX(testEditor: TestEditor): Promise<number> {
  const properties = parseJson<{ values: { position: string } }>(
    await testEditor.callTool("get_game_properties", { node_path: "Player", names: ["position"] }),
  );
  const match = /Vector2\(([-\d.e]+),/.exec(properties.values.position);
  return Number(match?.[1]);
}

describe("playing the game", () => {
  test("get_game_state and get_game_tree describe the running game", async () => {
    if (!editor) return;
    const state = parseJson<{ current_scene: string; paused: boolean }>(
      await editor.callTool("get_game_state"),
    );
    expect(state.current_scene).toBe("res://main.tscn");
    expect(state.paused).toBe(false);
    const tree = parseJson<{ tree: string }>(await editor.callTool("get_game_tree"));
    expect(tree.tree).toContain("Player (CharacterBody2D) at Vector2(100, 200)");
  });

  test("the game bridge leaves project.godot as soon as the game runs", async () => {
    if (!editor) return;
    // An export made while the game runs must not list the bridge as an autoload.
    const projectFile = await Bun.file(join(editor.projectPath, "project.godot")).text();
    expect(projectFile).not.toContain("GodotWingmanGameBridge");
  });

  test("holding the Right key moves the player like a real key press", async () => {
    if (!editor) return;
    const startX = await readPlayerX(editor);
    const pressed = await editor.callTool("press_input", { input: "key:Right", hold_seconds: 0.5 });
    expect(pressed.isError).toBe(false);
    const endX = await readPlayerX(editor);
    // SPEED is 200 px/s, so half a second moves the player about 100 px.
    expect(endX - startX).toBeGreaterThan(50);
    expect(endX - startX).toBeLessThan(160);
  });

  test("input_sequence plays timed steps", async () => {
    if (!editor) return;
    const startX = await readPlayerX(editor);
    const outcome = parseJson<{ performed: string[] }>(
      await editor.callTool("input_sequence", {
        steps: [{ press: "key:Left" }, { wait_seconds: 0.3 }, { release: "key:Left" }],
      }),
    );
    expect(outcome.performed).toHaveLength(3);
    expect(await readPlayerX(editor)).toBeLessThan(startX);
  });

  test("input_sequence waits for game conditions and releases held keys when a step fails", async () => {
    if (!editor) return;
    const startX = await readPlayerX(editor);
    const outcome = parseJson<{ performed: string[] }>(
      await editor.callTool("input_sequence", {
        steps: [
          { press: "key:Right" },
          { wait_until: `node("Player").position.x > ${startX + 40}`, timeout_seconds: 5 },
          { release: "key:Right" },
        ],
      }),
    );
    expect(outcome.performed[1]).toContain("waited until");
    expect(await readPlayerX(editor)).toBeGreaterThan(startX + 40);

    const failed = await editor.callTool("input_sequence", {
      steps: [{ press: "key:Right" }, { wait_until: "false", timeout_seconds: 0.3 }],
    });
    expect(failed.isError).toBe(true);
    expect(failed.text).toContain("released key:Right");
    const stoppedX = await readPlayerX(editor);
    await editor.callTool("wait_game", { seconds: 0.3 });
    expect(await readPlayerX(editor)).toBeCloseTo(stoppedX, 0);
  });

  test("wait_until returns once a condition becomes true", async () => {
    if (!editor) return;
    const result = parseJson<{ met: boolean }>(
      await editor.callTool("wait_until", {
        condition: 'node("Player") != null and scene.name == "Main"',
        timeout_seconds: 5,
      }),
    );
    expect(result.met).toBe(true);
    const timedOut = parseJson<{ met: boolean }>(
      await editor.callTool("wait_until", { condition: "false", timeout_seconds: 0.5 }),
    );
    expect(timedOut.met).toBe(false);
  });

  test("pause_game and step_frames control time", async () => {
    if (!editor) return;
    await editor.callTool("pause_game", { paused: true });
    const stepped = parseJson<{ stepped_frames: number; paused: boolean }>(
      await editor.callTool("step_frames", { count: 5 }),
    );
    expect(stepped).toEqual({ stepped_frames: 5, paused: true });
    await editor.callTool("pause_game", { paused: false });
  });

  test("execute_game_script and set_game_properties work on live nodes", async () => {
    if (!editor) return;
    await editor.callTool("set_game_properties", {
      node_path: "Label",
      properties: { text: "Changed live" },
    });
    const result = parseJson<{ result: string; printed: string[] }>(
      await editor.callTool("execute_game_script", {
        code: 'print("from the game")\nreturn node("Label").text',
      }),
    );
    expect(result.result).toBe("Changed live");
    expect(result.printed).toContain("from the game");
  });

  test("get_game_logs and get_performance read diagnostics", async () => {
    if (!editor) return;
    const logs = parseJson<{ captured: boolean; entries: { message: string }[] }>(
      await editor.callTool("get_game_logs", { search: "from the game" }),
    );
    expect(logs.captured).toBe(true);
    expect(logs.entries.length).toBeGreaterThan(0);
    const performance = await editor.callTool("get_performance");
    expect(performance.text).toContain("nodes:");
  });

  test("take_game_screenshot explains that headless games have no picture", async () => {
    if (!editor) return;
    const outcome = await editor.callTool("take_game_screenshot");
    expect(outcome.isError).toBe(true);
    expect(outcome.text).toContain("NO_DISPLAY");
  });
});
