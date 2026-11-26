/**
 * End-to-end tests of the news the AI gets at the end of its tool results: when the
 * person undoes or redoes a change, changes things by hand, or goes back to an earlier
 * step, and messages between AIs working in the same editor.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

let editor: TestEditor | null = null;

beforeAll(async () => {
  editor = await startTestEditor({ initialToolsets: ["core", "scene", "filesystem"] });
}, 300_000);

afterAll(async () => {
  await editor?.stop();
}, 30_000);

/**
 * Runs GDScript in the editor like the person would act: straight to the addon, not as
 * an AI tool call.
 */
async function actAsPerson(testEditor: TestEditor, code: string): Promise<void> {
  await testEditor.requestEditor("execute_script", { code });
}

const UNDO_IN_OPEN_SCENE = [
  "var history := undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(scene_root))",
  "history.undo()",
].join("\n");

const REDO_IN_OPEN_SCENE = UNDO_IN_OPEN_SCENE.replace("history.undo()", "history.redo()");

function changeByHand(actionName: string): string {
  return [
    `undo_redo.create_action("${actionName}")`,
    'undo_redo.add_do_property(scene_root, "position", scene_root.position + Vector2(1, 0))',
    'undo_redo.add_undo_property(scene_root, "position", scene_root.position)',
    "undo_redo.commit_action()",
  ].join("\n");
}

/** The news part of a tool result, or "" when there is none. */
function newsOf(texts: string[]): string {
  return texts.find((text) => text.startsWith("News from the Godot editor")) ?? "";
}

describe("news about what the person did", () => {
  test("undoing the AI's change with Ctrl+Z is reported to that AI", async () => {
    if (!editor) return;
    const added = await editor.callTool("add_node", { type: "Node2D", name: "AddedByAi" });
    expect(added.isError).toBe(false);
    await actAsPerson(editor, UNDO_IN_OPEN_SCENE);

    const next = await editor.callTool("get_editor_state");
    const news = newsOf(next.texts);
    expect(news).toContain("The person undid");
    expect(news).toContain("It was your change.");

    // News is delivered once.
    const after = await editor.callTool("get_editor_state");
    expect(newsOf(after.texts)).toBe("");
  });

  test("redo is reported too", async () => {
    if (!editor) return;
    await actAsPerson(editor, REDO_IN_OPEN_SCENE);
    const next = await editor.callTool("get_editor_state");
    expect(newsOf(next.texts)).toContain("The person redid");
  });

  test("changes by hand are reported, several in one line", async () => {
    if (!editor) return;
    // One request: every answer the editor sends carries the news collected so far.
    await actAsPerson(editor, [changeByHand("Move by hand"), changeByHand("Move by hand")].join("\n"));
    const next = await editor.callTool("get_editor_state");
    const news = newsOf(next.texts);
    expect(news).toContain("The person changed things by hand");
    expect(news).toContain('"Move by hand" x2');
  });

  test("the AI's own changes are not reported back to it", async () => {
    if (!editor) return;
    await editor.callTool("add_node", { type: "Node2D", name: "AnotherNode" });
    const next = await editor.callTool("get_editor_state");
    expect(newsOf(next.texts)).toBe("");
  });

  test("going back to before a step lists the restored files", async () => {
    if (!editor) return;
    await editor.callTool("write_file", { path: "res://notes/news.txt", content: "first" });
    const state = await editor.requestEditor<{ activity: { id: number; tool: string }[] }>(
      "get_session_state",
    );
    const writeStep = state.activity.filter((entry) => entry.tool === "write_file").at(-1);
    expect(writeStep).toBeDefined();
    await editor.requestEditor("go_back_to_before_step", { activity_id: writeStep?.id });

    const next = await editor.callTool("get_editor_state");
    const news = newsOf(next.texts);
    expect(news).toContain("went back to before step");
    expect(news).toContain("res://notes/news.txt");
    // Reloading scenes while going back is not reported as changes by hand.
    expect(news).not.toContain("by hand");
  });
});

describe("messages between AIs", () => {
  test("AIs hear when another AI connects, and can tell each other what they do", async () => {
    if (!editor) return;
    const otherAi = await editor.connectOtherAi("second-ai");

    const firstCall = await otherAi.callTool("get_editor_state");
    expect(newsOf(firstCall.texts)).toContain(
      "Other AIs are working in this editor too: godot-wingman-tests",
    );

    const heardAboutIt = await editor.callTool("get_editor_state");
    expect(newsOf(heardAboutIt.texts)).toContain("second-ai connected to this editor");

    const sent = await otherAi.callTool("tell_other_ais", { message: "I am rewriting res://player.gd" });
    expect(sent.isError).toBe(false);
    expect(sent.text).toContain("Sent to godot-wingman-tests");

    const received = await editor.callTool("get_editor_state");
    expect(newsOf(received.texts)).toContain('Message from second-ai: "I am rewriting res://player.gd"');

    // The message is in the activity list, so the person sees it too.
    const state = await editor.requestEditor<{ activity: { tool: string; title: string }[] }>(
      "get_session_state",
    );
    expect(state.activity.at(-1)).toMatchObject({
      tool: "tell_other_ais",
      title: "I am rewriting res://player.gd",
    });
  });

  test("an AI that connects later gets the recent messages", async () => {
    if (!editor) return;
    const lateAi = await editor.connectOtherAi("late-ai");
    const firstCall = await lateAi.callTool("get_editor_state");
    expect(newsOf(firstCall.texts)).toContain("I am rewriting res://player.gd");
  });
});
