/**
 * End-to-end tests of what happens around every change the AI makes: the permission
 * mode chosen in the editor's Godot Wingman panel, the activity list, checkpoints for
 * going back, and helpful errors.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { parseJson, startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

interface ActivityEntry {
  id: number;
  client: string;
  tool: string;
  status: string;
  result: string;
}

interface SessionState {
  editor_mode: string;
  activity: ActivityEntry[];
}

let editor: TestEditor | null = null;

beforeAll(async () => {
  // Nobody can click the approval dialog in a headless editor, so let it give up fast.
  editor = await startTestEditor({
    initialToolsets: ["core", "scene", "project", "filesystem"],
    confirmationTimeoutSeconds: 1,
  });
}, 300_000);

afterAll(async () => {
  await editor?.stop();
}, 30_000);

async function readSessionState(testEditor: TestEditor): Promise<SessionState> {
  return testEditor.requestEditor<SessionState>("get_session_state");
}

async function lastActivityEntry(testEditor: TestEditor): Promise<ActivityEntry | undefined> {
  return (await readSessionState(testEditor)).activity.at(-1);
}

async function readProjectFile(testEditor: TestEditor, path: string): Promise<string | null> {
  const outcome = await testEditor.callTool("read_file", { path });
  return outcome.isError ? null : parseJson<{ content: string }>(outcome).content;
}

describe("activity list", () => {
  test("every change is listed with the AI that made it and how it ended", async () => {
    if (!editor) return;
    const written = await editor.callTool("write_file", { path: "res://notes/first.json", content: "{}" });
    expect(written.isError).toBe(false);
    const entry = await lastActivityEntry(editor);
    expect(entry?.tool).toBe("write_file");
    expect(entry?.client).toBe("godot-wingman-tests");
    expect(entry?.status).toBe("done");
  });

  test("tools that only look are not listed", async () => {
    if (!editor) return;
    const entriesBefore = (await readSessionState(editor)).activity.length;
    await editor.callTool("get_scene_tree");
    expect((await readSessionState(editor)).activity.length).toBe(entriesBefore);
  });
});

describe("going back to before a step", () => {
  test("restores changed files and deletes files created later", async () => {
    if (!editor) return;
    await editor.callTool("write_file", { path: "res://notes/story.txt", content: "first version" });
    await editor.callTool("write_file", { path: "res://notes/story.txt", content: "second version" });
    const secondStep = await lastActivityEntry(editor);
    await editor.callTool("write_file", { path: "res://notes/later.txt", content: "created later" });
    expect(await readProjectFile(editor, "res://notes/story.txt")).toBe("second version");

    const outcome = await editor.requestEditor<{ changed: string[]; removed: string[]; failed: string[] }>(
      "go_back_to_before_step",
      { activity_id: secondStep?.id },
    );
    expect(outcome.changed).toContain("res://notes/story.txt");
    expect(outcome.removed).toContain("res://notes/later.txt");
    expect(outcome.failed).toEqual([]);
    expect(await readProjectFile(editor, "res://notes/story.txt")).toBe("first version");
    expect(await readProjectFile(editor, "res://notes/later.txt")).toBeNull();
  });

  test("restores project settings in the running editor too", async () => {
    if (!editor) return;
    const readDescription = async (testEditor: TestEditor) =>
      parseJson<{ settings: Record<string, unknown> }>(
        await testEditor.callTool("get_project_settings", { names: ["application/config/description"] }),
      ).settings["application/config/description"];
    const originalDescription = await readDescription(editor);
    await editor.callTool("set_project_settings", {
      settings: { "application/config/description": "Changed by the AI" },
    });
    const settingsStep = await lastActivityEntry(editor);
    expect(await readDescription(editor)).toBe("Changed by the AI");

    await editor.requestEditor("go_back_to_before_step", { activity_id: settingsStep?.id });
    expect(await readDescription(editor)).toEqual(originalDescription);
  });
});

describe("permission mode chosen in the editor", () => {
  test("read-only in the editor blocks changes even when the server allows them", async () => {
    if (!editor) return;
    await editor.requestEditor("set_editor_permission_mode", { mode: "read-only" });
    try {
      const blocked = await editor.callTool("write_file", { path: "res://notes/blocked.txt", content: "no" });
      expect(blocked.isError).toBe(true);
      expect(blocked.text).toContain("read-only");
      expect(await readProjectFile(editor, "res://notes/blocked.txt")).toBeNull();
      const stillAllowed = await editor.callTool("get_scene_tree");
      expect(stillAllowed.isError).toBe(false);
    } finally {
      await editor.requestEditor("set_editor_permission_mode", { mode: "full" });
    }
  });

  test("confirm mode refuses the change when nobody answers the dialog", async () => {
    if (!editor) return;
    await editor.requestEditor("set_editor_permission_mode", { mode: "confirm" });
    try {
      const unanswered = await editor.callTool("write_file", {
        path: "res://notes/unanswered.txt",
        content: "no",
      });
      expect(unanswered.isError).toBe(true);
      expect(unanswered.text).toContain("Nobody answered");
      expect((await lastActivityEntry(editor))?.status).toBe("denied");
      expect(await readProjectFile(editor, "res://notes/unanswered.txt")).toBeNull();
    } finally {
      await editor.requestEditor("set_editor_permission_mode", { mode: "full" });
    }
  }, 20_000);
});

describe("helpful errors", () => {
  test("a wrong node path suggests nodes with a similar name", async () => {
    if (!editor) return;
    const outcome = await editor.callTool("get_scene_tree", { node_path: "Characters/player" });
    expect(outcome.isError).toBe(true);
    expect(outcome.text).toContain('Did you mean: "Player"');
  });
});
