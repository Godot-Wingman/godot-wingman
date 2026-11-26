/**
 * Starts a real Godot editor (headless) on a copy of test-project, plus an MCP client
 * connected to our server, so tests exercise the whole chain:
 *   test -> MCP client -> MCP server -> WebSocket -> Godot addon -> editor.
 *
 * Godot is found like in real use (GODOT_PATH, common folders...). When no Godot is
 * available, `startTestEditor` returns null and the tests are skipped.
 */
import { cp, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { findBestGodotExecutable, getConsoleVariant } from "../../server/src/godot/find-godot-executable.ts";
import { launchEditor } from "../../server/src/godot/launch-editor.ts";
import { createMcpServer } from "../../server/src/mcp/create-mcp-server.ts";
import type { PermissionMode } from "../../server/src/mcp/permission-mode.ts";
import { HOME_OVERRIDE_ENVIRONMENT_VARIABLE } from "../../server/src/product.ts";

const repositoryRoot = join(import.meta.dir, "..", "..");

export interface ToolCallOutcome {
  text: string;
  isError: boolean;
  imageCount: number;
}

export interface TestEditor {
  projectPath: string;
  callTool(name: string, toolArguments?: Record<string, unknown>): Promise<ToolCallOutcome>;
  listToolNames(): Promise<string[]>;
  /** Sends a request straight to the addon, bypassing the tools (for checking editor state). */
  requestEditor<Result = unknown>(method: string, params?: object): Promise<Result>;
  stop(): Promise<void>;
}

export interface StartTestEditorOptions {
  permissionMode?: PermissionMode;
  initialToolsets?: string[];
  confirmationTimeoutSeconds?: number;
}

export async function startTestEditor(options: StartTestEditorOptions = {}): Promise<TestEditor | null> {
  const godot = await findBestGodotExecutable();
  if (!godot) {
    console.warn("No Godot executable found (set GODOT_PATH): skipping editor tests.");
    return null;
  }

  const temporaryRoot = await mkdtemp(join(tmpdir(), "godot-pilot-test-"));
  const homeDirectory = join(temporaryRoot, "home");
  const projectPath = join(temporaryRoot, "project");
  await cp(join(repositoryRoot, "test-project"), projectPath, {
    recursive: true,
    filter: (sourcePath) => !/[\\/](\.godot|addons)([\\/]|$)/.test(sourcePath),
  });
  process.env[HOME_OVERRIDE_ENVIRONMENT_VARIABLE] = homeDirectory;
  // Games started by the test editor run without a window too (no screen on CI machines).
  const projectFilePath = join(projectPath, "project.godot");
  const projectFileText = await Bun.file(projectFilePath).text();
  await Bun.write(
    projectFilePath,
    `${projectFileText}
[editor]

run/main_run_args="--headless"
`,
  );

  const launchResult = await launchEditor({
    projectPath,
    godotExecutable: getConsoleVariant(godot.path),
    headless: true,
    waitSeconds: 180,
    environment: { [HOME_OVERRIDE_ENVIRONMENT_VARIABLE]: homeDirectory },
  });

  const { server, editors } = createMcpServer({
    permissionMode: options.permissionMode ?? "full",
    initialToolsets: options.initialToolsets ?? ["core", "scene", "inspector", "script", "project"],
    confirmationTimeoutSeconds: options.confirmationTimeoutSeconds,
  });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  const client = new Client({ name: "godot-pilot-tests", version: "0.0.0" });
  await client.connect(clientTransport);

  // The editor reopens the main scene a moment after the addon is ready; wait for it so
  // the first test does not run against an empty editor.
  for (let attempt = 0; attempt < 40; attempt++) {
    const stateResult = await client.callTool({ name: "get_editor_state", arguments: {} });
    const stateText = (stateResult.content as { text?: string }[])[0]?.text ?? "{}";
    if ((JSON.parse(stateText) as { edited_scene?: string | null }).edited_scene) {
      break;
    }
    await Bun.sleep(250);
  }

  return {
    projectPath,
    async callTool(name, toolArguments = {}) {
      const result = await client.callTool({ name, arguments: toolArguments }, undefined, {
        timeout: 120_000,
      });
      const content = (result.content ?? []) as { type: string; text?: string }[];
      return {
        text: content
          .filter((item) => item.type === "text")
          .map((item) => item.text ?? "")
          .join("\n"),
        isError: result.isError === true,
        imageCount: content.filter((item) => item.type === "image").length,
      };
    },
    requestEditor(method, params = {}) {
      return editors.request(method, params);
    },
    async listToolNames() {
      const { tools } = await client.listTools();
      return tools.map((tool) => tool.name);
    },
    async stop() {
      editors.closeAll();
      await client.close();
      try {
        process.kill(launchResult.registration.processId);
      } catch {
        // Already gone.
      }
      // Windows keeps files locked for a moment after the process ends.
      await Bun.sleep(1000);
      await rm(temporaryRoot, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 }).catch(
        () => {},
      );
    },
  };
}

/** Parses the JSON text of a tool result. */
export function parseJson<Shape = Record<string, unknown>>(outcome: ToolCallOutcome): Shape {
  return JSON.parse(outcome.text) as Shape;
}
