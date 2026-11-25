/**
 * Builds the MCP server: tools (grouped in toolsets), guides as resources, and the
 * instructions the AI receives when it connects.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { ApiDocumentation } from "../docs/api-documentation.ts";
import { EditorManager } from "../godot/editor-manager.ts";
import { readEditorRegistrations } from "../godot/editor-registry.ts";
import {
  findBestGodotExecutable,
  getConsoleVariant,
  readGodotVersion,
} from "../godot/find-godot-executable.ts";
import { GUIDES } from "../guides/guides.ts";
import { PRODUCT_NAME, PRODUCT_VERSION } from "../product.ts";
import { ALL_TOOLSETS } from "../tools/toolsets.ts";
import type { PermissionMode } from "./permission-mode.ts";
import { SERVER_INSTRUCTIONS } from "./server-instructions.ts";
import type { ToolContext } from "./tool-definition.ts";
import { type Toolset, ToolsetController } from "./toolset-controller.ts";

export interface CreateServerOptions {
  permissionMode: PermissionMode;
  initialToolsets: string[];
  /** Project to use when several editors are running. */
  preselectedProjectPath?: string;
  /** Replaces the built-in toolsets; used by tests. */
  toolsets?: Toolset[];
}

export interface CreatedServer {
  server: McpServer;
  editors: EditorManager;
  toolsets: ToolsetController;
}

export function createMcpServer(options: CreateServerOptions): CreatedServer {
  const server = new McpServer(
    { name: PRODUCT_NAME, version: PRODUCT_VERSION },
    {
      instructions: SERVER_INSTRUCTIONS,
      capabilities: { tools: { listChanged: true }, resources: {} },
    },
  );

  const editors = new EditorManager();
  if (options.preselectedProjectPath) {
    editors.selectProject(options.preselectedProjectPath);
  }
  const docs = new ApiDocumentation(findGodotForDocumentation);

  // The controller needs the context and the context contains the controller,
  // so the context is created lazily, after both exist.
  let toolContext: ToolContext | null = null;
  const toolsets = new ToolsetController(
    server,
    options.toolsets ?? ALL_TOOLSETS,
    options.permissionMode,
    () => {
      toolContext ??= { editors, docs, toolsets, permissionMode: options.permissionMode };
      return toolContext;
    },
  );
  toolsets.registerAll(options.initialToolsets);

  for (const guide of GUIDES) {
    server.registerResource(
      guide.name,
      `${PRODUCT_NAME}://guides/${guide.name}`,
      { title: guide.title, mimeType: "text/markdown" },
      async (uri) => ({ contents: [{ uri: uri.href, mimeType: "text/markdown", text: guide.content }] }),
    );
  }

  return { server, editors, toolsets };
}

/**
 * Documentation should match the Godot the person uses: prefer the executable of a
 * running editor, otherwise the best one found on the computer.
 */
async function findGodotForDocumentation(): Promise<{ executable: string; version: string }> {
  const [runningEditor] = await readEditorRegistrations();
  if (runningEditor) {
    return {
      executable: getConsoleVariant(runningEditor.godotExecutable),
      version: runningEditor.godotVersion,
    };
  }
  const foundExecutable = await findBestGodotExecutable();
  if (!foundExecutable) {
    throw new Error(
      "Godot documentation needs a Godot executable, and none was found. Open the project with launch_editor (pass godot_executable if Godot is not found), or set GODOT_PATH.",
    );
  }
  const executable = getConsoleVariant(foundExecutable.path);
  return { executable, version: await readGodotVersion(executable) };
}
