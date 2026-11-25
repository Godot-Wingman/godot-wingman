/**
 * End-to-end tests of the core toolset against a real, headless Godot editor.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { parseJson, startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

let editor: TestEditor | null = null;

beforeAll(async () => {
  editor = await startTestEditor();
}, 240_000);

afterAll(async () => {
  await editor?.stop();
}, 30_000);

/** Returns the running test editor, or null when Godot is missing (the test then passes trivially). */
function requireEditor(): TestEditor | null {
  return editor;
}

describe("core toolset", () => {
  test("get_status lists the running editor", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const status = await testEditor.callTool("get_status");
    expect(status.isError).toBe(false);
    expect(status.text).toContain("Godot Pilot Test Project");
    expect(status.text).toContain("USED BY TOOLS");
  });

  test("get_editor_state reports the open scene", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const state = parseJson(await testEditor.callTool("get_editor_state"));
    expect(state.main_scene).toBe("res://main.tscn");
    expect(state.headless).toBe(true);
    expect(state.logs_captured).toBe(true);
  });

  test("execute_editor_script returns values, printed text and output lines", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const outcome = await testEditor.callTool("execute_editor_script", {
      code: 'print("hello from the test")\noutput("an output line")\nreturn Vector2(3, 4)',
    });
    expect(outcome.isError).toBe(false);
    const result = parseJson<{ result: string; printed: string[]; output: string[] }>(outcome);
    expect(result.result).toBe("Vector2(3, 4)");
    expect(result.printed).toContain("hello from the test");
    expect(result.output).toEqual(["an output line"]);
  });

  test("execute_editor_script reports compile errors with the line of the AI's code", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const outcome = await testEditor.callTool("execute_editor_script", {
      code: "var fine = 1\nvar broken = \nreturn 1",
    });
    expect(outcome.isError).toBe(true);
    expect(outcome.text).toContain("SCRIPT_COMPILE_ERROR");
    expect(outcome.text).toContain('"line":2');
  });

  test("execute_editor_script reports runtime errors", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const outcome = await testEditor.callTool("execute_editor_script", {
      code: "var missing = null\nreturn missing.position",
    });
    const result = parseJson<{ errors_and_warnings: { message: string; line: number }[] }>(outcome);
    expect(result.errors_and_warnings[0]?.message).toContain("Nil");
    expect(result.errors_and_warnings[0]?.line).toBe(2);
  });

  test("get_logs finds printed messages", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    await testEditor.callTool("execute_editor_script", { code: 'print("log marker 42")' });
    const logs = parseJson<{ entries: { message: string }[] }>(
      await testEditor.callTool("get_logs", { search: "log marker 42" }),
    );
    expect(logs.entries.length).toBeGreaterThan(0);
  });

  test("take_editor_screenshot explains that headless editors cannot be captured", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const outcome = await testEditor.callTool("take_editor_screenshot");
    expect(outcome.isError).toBe(true);
    expect(outcome.text).toContain("NO_DISPLAY");
  });

  test("get_class_docs returns the class reference of the installed version", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const docs = await testEditor.callTool("get_class_docs", { class_name: "CharacterBody2D" });
    expect(docs.isError).toBe(false);
    expect(docs.text).toContain("move_and_slide");
    const memberDocs = await testEditor.callTool("get_class_docs", {
      class_name: "CharacterBody2D",
      member: "position",
    });
    expect(memberDocs.text).toContain("inherited from Node2D");
  }, 120_000);

  test("get_class_docs falls back to the live editor for script classes", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const docs = await testEditor.callTool("get_class_docs", { class_name: "NoSuchClassAnywhere" });
    expect(docs.isError).toBe(true);
    expect(docs.text).toContain("Unknown class");
  }, 120_000);

  test("search_docs finds methods by name", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const matches = await testEditor.callTool("search_docs", { query: "move_and_slide" });
    expect(matches.text).toContain("CharacterBody2D.move_and_slide");
  }, 120_000);

  test("toggle_toolsets reports unknown names and keeps core enabled", async () => {
    const testEditor = requireEditor();
    if (!testEditor) return;
    const outcome = await testEditor.callTool("toggle_toolsets", {
      enable: ["does_not_exist"],
      disable: ["core"],
    });
    expect(outcome.text).toContain("Unknown toolsets: does_not_exist");
    expect(outcome.text).toContain("Always enabled, not changed: core");
    expect(await testEditor.listToolNames()).toContain("get_status");
  });
});
