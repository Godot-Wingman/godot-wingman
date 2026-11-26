/**
 * End-to-end test with a GDExtension written in Rust (tests/languages/rust-extension):
 * the AI sees the class the extension adds, reads its documentation, adds it to a
 * scene, sets its property and calls its method in the running game.
 *
 * Needs Rust (cargo) and downloads the godot-rust crate, so it only runs when asked:
 *   GODOT_WINGMAN_GDEXTENSION=1 bun test tests/languages/gdextension.test.ts
 * CI runs it every night (.github/workflows/languages.yml).
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { copyFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { parseJson, startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

const isEnabled = process.env.GODOT_WINGMAN_GDEXTENSION === "1";
const crateDirectory = join(import.meta.dir, "rust-extension");
let editor: TestEditor | null = null;

/** File name of the built library on this system. */
function libraryFileName(): string {
  if (process.platform === "win32") return "wingman_extension.dll";
  if (process.platform === "darwin") return "libwingman_extension.dylib";
  return "libwingman_extension.so";
}

async function buildExtension(): Promise<string> {
  const build = Bun.spawn(["cargo", "build"], { cwd: crateDirectory, stdout: "pipe", stderr: "pipe" });
  const exitCode = await build.exited;
  if (exitCode !== 0) {
    throw new Error(`cargo build failed:\n${await new Response(build.stderr).text()}`);
  }
  return join(crateDirectory, "target", "debug", libraryFileName());
}

/** Puts the library and its .gdextension file into the project, as a Rust project would have them. */
async function addExtension(projectPath: string, libraryPath: string): Promise<void> {
  await mkdir(join(projectPath, "bin"), { recursive: true });
  await copyFile(libraryPath, join(projectPath, "bin", libraryFileName()));
  await Bun.write(
    join(projectPath, "wingman_extension.gdextension"),
    `[configuration]
entry_symbol = "gdext_rust_init"
compatibility_minimum = 4.1

[libraries]
linux.debug.x86_64 = "res://bin/libwingman_extension.so"
linux.release.x86_64 = "res://bin/libwingman_extension.so"
windows.debug.x86_64 = "res://bin/wingman_extension.dll"
windows.release.x86_64 = "res://bin/wingman_extension.dll"
macos.debug = "res://bin/libwingman_extension.dylib"
macos.release = "res://bin/libwingman_extension.dylib"
`,
  );
  // The editor loads the extensions listed here when it starts.
  await mkdir(join(projectPath, ".godot"), { recursive: true });
  await Bun.write(join(projectPath, ".godot", "extension_list.cfg"), "res://wingman_extension.gdextension\n");
}

beforeAll(async () => {
  if (!isEnabled) {
    return;
  }
  const libraryPath = await buildExtension();
  editor = await startTestEditor({
    initialToolsets: ["core", "scene", "inspector", "play", "game_inspect", "debug"],
    prepareProject: (projectPath) => addExtension(projectPath, libraryPath),
  });
}, 900_000);

afterAll(async () => {
  await editor?.callTool("stop_game");
  await editor?.stop();
}, 30_000);

describe("GDExtension written in Rust", () => {
  test("the editor lists the loaded extension", async () => {
    if (!editor) return;
    const state = parseJson<{ gdextensions: string[] }>(await editor.callTool("get_editor_state"));
    expect(state.gdextensions).toContain("res://wingman_extension.gdextension");
  });

  test("get_class_docs describes the class the extension adds", async () => {
    if (!editor) return;
    const docs = await editor.callTool("get_class_docs", { class_name: "WingmanGreeter" });
    expect(docs.isError).toBe(false);
    expect(docs.text).toContain("Node2D");
    expect(docs.text).toContain("greeting");
    expect(docs.text).toContain("shout");
    expect(docs.text).toContain("greeted");
  });

  test("the class can be added, edited and used in the running game", async () => {
    if (!editor) return;
    const added = await editor.callTool("add_node", {
      type: "WingmanGreeter",
      name: "Greeter",
      properties: { greeting: "hi from the test" },
    });
    expect(added.isError).toBe(false);
    const properties = await editor.callTool("get_properties", { node_path: "Greeter", names: ["greeting"] });
    expect(properties.text).toContain("hi from the test");
    expect((await editor.callTool("save_scene")).isError).toBe(false);

    expect((await editor.callTool("run_game")).isError).toBe(false);
    const shouted = await editor.callTool("call_game_method", { node_path: "Greeter", method: "shout" });
    expect(shouted.isError).toBe(false);
    expect(shouted.text).toContain("HI FROM THE TEST");
    const logs = await editor.callTool("get_game_logs", { search: "WingmanGreeter is ready" });
    expect(logs.text).toContain("hi from the test");
    await editor.callTool("stop_game");
  }, 300_000);
});
