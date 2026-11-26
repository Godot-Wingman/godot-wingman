/**
 * Smoke tests with a real editor window: what headless tests cannot show. Screenshots,
 * renders, the Godot Pilot panel, the approval dialog and a game in its own window.
 *
 * They need a screen, so they only run when GODOT_PILOT_WINDOWED=1 is set:
 *   GODOT_PILOT_WINDOWED=1 bun test tests/windowed
 * On Linux CI they run inside a virtual screen (xvfb-run).
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

const isEnabled = process.env.GODOT_PILOT_WINDOWED === "1";
let editor: TestEditor | null = null;

beforeAll(async () => {
  if (!isEnabled) {
    return;
  }
  editor = await startTestEditor({
    windowed: true,
    initialToolsets: ["core", "scene", "viewport", "filesystem", "play", "game_inspect"],
  });
}, 300_000);

afterAll(async () => {
  await editor?.callTool("stop_game");
  await editor?.stop();
}, 30_000);

/** Runs GDScript in the editor without going through the tools (and their approval). */
async function runInEditor<Result>(testEditor: TestEditor, code: string): Promise<Result> {
  const answer = await testEditor.requestEditor<{ result: Result }>("execute_script", { code });
  return answer.result;
}

describe("seeing the editor", () => {
  test("take_editor_screenshot works, also when the editor has been idle", async () => {
    if (!editor) return;
    const first = await editor.callTool("take_editor_screenshot", { max_size: 640 });
    expect(first.isError).toBe(false);
    expect(first.imageCount).toBe(1);
    // An idle editor draws no new frames; the screenshot must not wait for one forever.
    await Bun.sleep(2000);
    const second = await editor.callTool("take_editor_screenshot", { max_size: 640 });
    expect(second.imageCount).toBe(1);
  }, 30_000);

  test("render_view renders the open scene", async () => {
    if (!editor) return;
    const render = await editor.callTool("render_view", { max_size: 480 });
    expect(render.isError).toBe(false);
    expect(render.imageCount).toBe(1);
  }, 30_000);

  test("the Godot Pilot panel is in the editor", async () => {
    if (!editor) return;
    const found = await runInEditor<boolean>(
      editor,
      'return editor.get_base_control().find_child("GodotPilotDock", true, false) != null',
    );
    expect(found).toBe(true);
  });
});

describe("approval dialog", () => {
  test("shows the change, fits on the screen, and can allow a tool for the session", async () => {
    if (!editor) return;
    await editor.requestEditor("set_editor_permission_mode", { mode: "confirm" });
    try {
      const pendingWrite = editor.callTool("write_file", {
        path: "res://notes/approved.txt",
        content: "first line\nsecond line",
      });
      await Bun.sleep(1500);
      const dialog = await runInEditor<{ fits: boolean; has_text_box: boolean; title: string } | null>(
        editor,
        [
          "for child in editor.get_base_control().get_children():",
          "\tif child is ConfirmationDialog and child.visible:",
          "\t\tvar screen_size := DisplayServer.screen_get_usable_rect(child.current_screen).size",
          '\t\tvar text_boxes := child.find_children("*", "TextEdit", true, false)',
          '\t\tvar result := {"fits": child.size.x <= screen_size.x and child.size.y <= screen_size.y, "has_text_box": not text_boxes.is_empty(), "title": child.title}',
          '\t\tchild.custom_action.emit(&"allow_for_session")',
          "\t\treturn result",
          "return null",
        ].join("\n"),
      );
      expect(dialog?.fits).toBe(true);
      expect(dialog?.has_text_box).toBe(true);
      const written = await pendingWrite;
      expect(written.isError).toBe(false);

      // Allowed for the session: the next call does not ask again.
      const second = await editor.callTool("write_file", { path: "res://notes/second.txt", content: "ok" });
      expect(second.isError).toBe(false);
    } finally {
      await editor.requestEditor("set_editor_permission_mode", { mode: "full" });
    }
  }, 60_000);
});

describe("playing in a window", () => {
  test("take_game_screenshot captures the running game", async () => {
    if (!editor) return;
    const started = await editor.callTool("run_game");
    expect(started.isError).toBe(false);
    const screenshot = await editor.callTool("take_game_screenshot", { max_size: 480 });
    expect(screenshot.isError).toBe(false);
    expect(screenshot.imageCount).toBe(1);
    await editor.callTool("stop_game");
  }, 120_000);
});
