/**
 * End-to-end test with a C# project: the AI writes a C# script, it is built, attached
 * to a node, and runs in the game.
 *
 * Needs the .NET build of Godot and the .NET SDK, so it only runs when asked:
 *   GODOT_WINGMAN_CSHARP=1 GODOT_PATH=/path/to/Godot_mono bun test tests/languages/csharp.test.ts
 * CI runs it every night (.github/workflows/languages.yml).
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { join } from "node:path";
import { parseJson, startTestEditor, type TestEditor } from "../helpers/test-editor.ts";

const isEnabled = process.env.GODOT_WINGMAN_CSHARP === "1";
const ASSEMBLY_NAME = "WingmanCSharpTest";
let editor: TestEditor | null = null;

const MOVER_SCRIPT = `using Godot;

public partial class Mover : Node2D
{
    [Export]
    public float Speed { get; set; } = 42.0f;

    public override void _Ready()
    {
        GD.Print("Mover is ready in C#");
    }

    public string Describe()
    {
        return $"Mover with speed {Speed}";
    }
}
`;

/** The C# project file a .NET editor creates with "Create C# solution". */
async function addCSharpProjectFiles(projectPath: string, godotVersion: string): Promise<void> {
  await Bun.write(
    join(projectPath, `${ASSEMBLY_NAME}.csproj`),
    `<Project Sdk="Godot.NET.Sdk/${godotVersion}">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
`,
  );
  const projectFilePath = join(projectPath, "project.godot");
  const projectFile = await Bun.file(projectFilePath).text();
  await Bun.write(projectFilePath, `${projectFile}\n[dotnet]\n\nproject/assembly_name="${ASSEMBLY_NAME}"\n`);
}

async function buildCSharp(projectPath: string): Promise<void> {
  const build = Bun.spawn(["dotnet", "build", join(projectPath, `${ASSEMBLY_NAME}.csproj`)], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const exitCode = await build.exited;
  if (exitCode !== 0) {
    throw new Error(`dotnet build failed:\n${await new Response(build.stdout).text()}`);
  }
}

beforeAll(async () => {
  if (!isEnabled) {
    return;
  }
  const godotVersion = process.env.GODOT_WINGMAN_CSHARP_SDK_VERSION ?? "4.7.2";
  editor = await startTestEditor({
    initialToolsets: ["core", "scene", "inspector", "script", "play", "game_inspect", "debug"],
    godotExecutable: process.env.GODOT_PATH,
    prepareProject: (projectPath) => addCSharpProjectFiles(projectPath, godotVersion),
  });
}, 600_000);

afterAll(async () => {
  await editor?.callTool("stop_game");
  await editor?.stop();
}, 30_000);

describe("C# project", () => {
  test("the editor reports that C# is available", async () => {
    if (!editor) return;
    const state = parseJson<{ csharp_available: boolean }>(await editor.callTool("get_editor_state"));
    expect(state.csharp_available).toBe(true);
  });

  test("C# documentation can be asked for", async () => {
    if (!editor) return;
    const docs = await editor.callTool("get_class_docs", { class_name: "Node2D", language: "csharp" });
    expect(docs.isError).toBe(false);
  });

  test("a C# script written by the AI is built, attached and runs in the game", async () => {
    if (!editor) return;
    const created = await editor.callTool("create_script", { path: "res://Mover.cs", content: MOVER_SCRIPT });
    expect(created.isError).toBe(false);

    await buildCSharp(editor.projectPath);

    expect((await editor.callTool("add_node", { type: "Node2D", name: "Mover" })).isError).toBe(false);
    const attached = await editor.callTool("attach_script", {
      node_path: "Mover",
      script_path: "res://Mover.cs",
    });
    expect(attached.isError).toBe(false);
    expect((await editor.callTool("save_scene")).isError).toBe(false);

    expect((await editor.callTool("run_game")).isError).toBe(false);
    const described = await editor.callTool("call_game_method", { node_path: "Mover", method: "Describe" });
    expect(described.isError).toBe(false);
    expect(described.text).toContain("Mover with speed 42");

    const logs = await editor.callTool("get_game_logs", { search: "ready in C#" });
    expect(logs.text).toContain("Mover is ready in C#");
    await editor.callTool("stop_game");
  }, 300_000);
});
