/**
 * Pictures the person attaches in the Godot Wingman chat reach the AI as images at the
 * end of its tool result (server/src/mcp/toolset-controller.ts).
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { EditorNotice } from "../../server/src/godot/editor-connection.ts";
import { addNotices } from "../../server/src/mcp/toolset-controller.ts";

/** A 1x1 PNG. */
const PNG_BYTES = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);

let folder = "";

beforeAll(async () => {
  folder = await mkdtemp(join(tmpdir(), "wingman-chat-"));
  await writeFile(join(folder, "picture.png"), PNG_BYTES);
});

afterAll(async () => {
  await rm(folder, { recursive: true, force: true });
});

function chatNotice(attachments: EditorNotice["attachments"]): EditorNotice {
  return { time: "12:00:00", kind: "message", text: "Message from the person", message_id: 1, attachments };
}

describe("pictures attached in the chat", () => {
  test("are added to the tool result as images after the news text", () => {
    const result = addNotices({ content: [{ type: "text", text: "done" }] }, [
      chatNotice([
        { kind: "image", path: join(folder, "picture.png") },
        { kind: "file", path: "res://player.gd" },
      ]),
    ]);
    expect(result.content.map((item) => item.type)).toEqual(["text", "text", "image"]);
    const image = result.content[2] as { data: string; mimeType: string };
    expect(image.mimeType).toBe("image/png");
    expect(Buffer.from(image.data, "base64").equals(PNG_BYTES)).toBe(true);
  });

  test("a picture that is gone is skipped, the text still names it", () => {
    const result = addNotices({ content: [] }, [
      chatNotice([{ kind: "image", path: join(folder, "gone.png") }]),
    ]);
    expect(result.content.map((item) => item.type)).toEqual(["text"]);
  });

  test("news without attachments adds only text", () => {
    const result = addNotices({ content: [] }, [
      { time: "12:00:00", kind: "undo", text: "The person undid" },
    ]);
    expect(result.content).toEqual([
      {
        type: "text",
        text: "News from the Godot editor since your last tool call:\n- 12:00:00 The person undid",
      },
    ]);
  });
});
