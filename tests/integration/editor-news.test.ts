/**
 * End-to-end tests of the news the AI gets at the end of its tool results: when the
 * person undoes or redoes a change, changes things by hand, or goes back to an earlier
 * step, messages between AIs working in the same editor, and the chat between the
 * person and the AIs in the Godot Wingman panel.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
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

    // The message is in the panel's Messages list, so the person sees it too.
    const state = await editor.requestEditor<{ messages: { sender: string; text: string }[] }>(
      "get_session_state",
    );
    expect(state.messages.at(-1)).toMatchObject({
      sender: "second-ai",
      text: "I am rewriting res://player.gd",
    });
  });

  test("each AI has its own permission mode and can be renamed", async () => {
    if (!editor) return;
    const plannerAi = await editor.connectOtherAi("planner-ai");
    await plannerAi.callTool("get_editor_state");
    type Connection = { connection_id: number; name: string; mode: string };
    const readConnections = async (testEditor: TestEditor) =>
      (await testEditor.requestEditor<{ connections: Connection[] }>("get_session_state")).connections;
    const planner = (await readConnections(editor)).find((connection) => connection.name === "planner-ai");
    expect(planner).toBeDefined();

    await editor.requestEditor("set_editor_permission_mode", {
      mode: "read-only",
      connection_id: planner?.connection_id,
    });
    try {
      const blocked = await plannerAi.callTool("write_file", {
        path: "res://notes/planner.txt",
        content: "no",
      });
      expect(blocked.isError).toBe(true);
      expect(blocked.text).toContain("read-only");
      const allowed = await editor.callTool("write_file", {
        path: "res://notes/main-ai.txt",
        content: "yes",
      });
      expect(allowed.isError).toBe(false);
      // The AI hears about its new mode with its next tool result, here the blocked one.
      const told = await plannerAi.callTool("get_editor_state");
      expect(newsOf([...blocked.texts, ...told.texts])).toContain("read-only, you may only look");
    } finally {
      await editor.requestEditor("set_editor_permission_mode", { mode: "full" });
    }

    await editor.requestEditor("rename_ai", { connection_id: planner?.connection_id, name: "Planner" });
    const renamed = (await readConnections(editor)).find(
      (connection) => connection.connection_id === planner?.connection_id,
    );
    expect(renamed?.name).toBe("Planner");
    expect(newsOf((await editor.callTool("get_editor_state")).texts)).toContain(
      'planner-ai is now called "Planner"',
    );
    expect(newsOf((await plannerAi.callTool("get_editor_state")).texts)).toContain(
      'The person named you "Planner"',
    );
    await plannerAi.close();
  }, 60_000);

  test("an AI that connects later gets the recent messages", async () => {
    if (!editor) return;
    const lateAi = await editor.connectOtherAi("late-ai");
    const firstCall = await lateAi.callTool("get_editor_state");
    expect(newsOf(firstCall.texts)).toContain("I am rewriting res://player.gd");
  });
});

type ChatMessage = {
  id: number;
  sender: string;
  from_id: number;
  to_id: number;
  text: string;
  attachments: { kind: string; path: string }[];
  read_by: Record<string, string>;
};
type SessionState = {
  connections: { connection_id: number; name: string }[];
  messages: ChatMessage[];
};

/** A 1x1 PNG. */
const PNG_BYTES = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);

describe("chat with the person", () => {
  async function readState(testEditor: TestEditor): Promise<SessionState> {
    return testEditor.requestEditor<SessionState>("get_session_state");
  }

  async function connectionIdOf(testEditor: TestEditor, name: string): Promise<number> {
    const connection = (await readState(testEditor)).connections.find((candidate) => candidate.name === name);
    expect(connection).toBeDefined();
    return connection?.connection_id ?? -1;
  }

  test("a message to one AI reaches only that AI and shows as read", async () => {
    if (!editor) return;
    const bystander = await editor.connectOtherAi("bystander-ai");
    await bystander.callTool("get_editor_state");
    const mainId = await connectionIdOf(editor, "godot-wingman-tests");
    await editor.requestEditor("send_chat_message_as_person", {
      to: mainId,
      text: "Please check res://main.tscn",
      attachments: [{ kind: "file", path: "res://main.tscn" }],
    });

    const next = await editor.callTool("get_editor_state");
    const news = newsOf(next.texts);
    expect(news).toContain(
      'Message from the person at the editor, only to you: "Please check res://main.tscn"',
    );
    expect(news).toContain("Attached: file res://main.tscn.");
    expect(news).toContain("reply_to_person");
    expect(newsOf((await bystander.callTool("get_editor_state")).texts)).not.toContain("Please check");

    const sent = (await readState(editor)).messages.find(
      (message) => message.text === "Please check res://main.tscn",
    );
    expect(sent?.to_id).toBe(mainId);
    expect(Object.keys(sent?.read_by ?? {})).toEqual([String(mainId)]);
    await bystander.close();
  }, 60_000);

  test("reply_to_person shows the answer in the chat", async () => {
    if (!editor) return;
    const reply = await editor.callTool("reply_to_person", {
      message: "Checked it: **all good**.",
      files: ["res://main.tscn"],
    });
    expect(reply.isError).toBe(false);
    const mainId = await connectionIdOf(editor, "godot-wingman-tests");
    // Find it by text: an AI leaving can be listed after it.
    const answer = (await readState(editor)).messages.find(
      (message) => message.text === "Checked it: **all good**.",
    );
    expect(answer).toMatchObject({ from_id: mainId, to_id: 0, text: "Checked it: **all good**." });
    expect(answer?.attachments).toEqual([{ kind: "file", path: "res://main.tscn" }]);
  });

  test("a listening AI gets the message right away, with attached pictures", async () => {
    if (!editor) return;
    const listener = await editor.connectOtherAi("listener-ai");
    await listener.callTool("get_editor_state");
    const listenerId = await connectionIdOf(editor, "listener-ai");

    const quiet = await listener.callTool("wait_for_person_message", { timeout_seconds: 5 });
    expect(quiet.text).toContain("No message yet");

    const picturePath = join(editor.projectPath, "chat-picture.png");
    await writeFile(picturePath, PNG_BYTES);
    const startedAt = Date.now();
    const waiting = listener.callTool("wait_for_person_message", { timeout_seconds: 60 });
    await Bun.sleep(500);
    await editor.requestEditor("send_chat_message_as_person", {
      to: listenerId,
      text: "Make the sky darker",
      attachments: [{ kind: "image", path: picturePath }],
    });
    const heard = await waiting;
    expect(Date.now() - startedAt).toBeLessThan(20_000);
    expect(heard.text).toContain("The person wrote to you");
    expect(newsOf(heard.texts)).toContain('"Make the sky darker"');
    expect(heard.imageCount).toBe(1);
    await listener.close();
  }, 120_000);

  test("the chat is kept in the project's .godot folder", async () => {
    if (!editor) return;
    // Saved at the end of the frame after a change; the next request comes after it.
    await editor.callTool("get_editor_state");
    const saved = JSON.parse(
      await readFile(join(editor.projectPath, ".godot", "godot_wingman", "chat.json"), "utf8"),
    ) as { messages: ChatMessage[] };
    expect(saved.messages.map((message) => message.text)).toContain("Make the sky darker");
  });

  test("Markdown from the AIs becomes BBCode and code blocks", async () => {
    if (!editor) return;
    const outcome = await editor.requestEditor<{
      result: { type: string; bbcode?: string; code?: string }[];
    }>("execute_script", {
      code: [
        'var markdown := load("res://addons/godot_wingman/ui/markdown_text.gd")',
        'return markdown.to_parts("## Done\\n- **bold** and `code` in res://player.gd\\n- [link](https://godotengine.org)\\n\\n```gdscript\\nvar a = [1]\\n```\\nAfter [x]", {}, 16)',
      ].join("\n"),
    });
    const parts = outcome.result;
    expect(parts.map((part) => part.type)).toEqual(["text", "code", "text"]);
    expect(parts[0]?.bbcode).toContain("[font_size=19][b]Done[/b][/font_size]");
    expect(parts[0]?.bbcode).toContain("[ul]");
    expect(parts[0]?.bbcode).toContain("[b]bold[/b]");
    expect(parts[0]?.bbcode).toContain("[code]code[/code]");
    expect(parts[0]?.bbcode).toContain("[url=res://player.gd]");
    expect(parts[0]?.bbcode).toContain("[url=https://godotengine.org]");
    expect(parts[1]?.code).toBe("var a = [1]");
    // A "[" written by the AI is shown as text, not read as a BBCode tag.
    expect(parts[2]?.bbcode).toBe("After [lb]x]");
  });
});
