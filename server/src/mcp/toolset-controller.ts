/**
 * Turns groups of tools ("toolsets") on and off while the server runs.
 *
 * Godot Pilot has well over a hundred tools. If all of them were visible at once,
 * their descriptions alone would fill a large part of the AI's context. So tools are
 * grouped, and only the groups the AI needs are visible. The AI (or the person) can
 * switch groups with the toggle_toolsets tool; the MCP SDK then tells the client
 * that the tool list changed ("notifications/tools/list_changed").
 */
import type { McpServer, RegisteredTool } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { type EditorNotice, EditorRequestError } from "../godot/editor-connection.ts";
import type { PermissionMode } from "./permission-mode.ts";
import { errorResult, errorToResult, type PilotTool, type ToolContext } from "./tool-definition.ts";

export interface Toolset {
  name: string;
  title: string;
  /** One or two sentences: what the group is for, so the AI knows when to enable it. */
  description: string;
  tools: PilotTool[];
  /** The core toolset cannot be turned off. */
  alwaysEnabled?: boolean;
}

export interface ToolsetSummary {
  name: string;
  title: string;
  description: string;
  enabled: boolean;
  toolNames: string[];
  /** Tools hidden because of the read-only permission mode. */
  hiddenToolNames: string[];
}

const DEFAULT_CONFIRMATION_TIMEOUT_SECONDS = 180;
const FINISH_REPORT_TIMEOUT_MILLISECONDS = 5000;

export interface ToolsetControllerOptions {
  /** How long the approval dialog waits in "confirm" mode. */
  confirmationTimeoutSeconds?: number;
  /** Name of the AI application, shown in the editor next to each change. */
  getAiClientName?: () => string;
}

/** The editor's answer to authorize_tool_call (addon/godot_pilot/session/pilot_session.gd). */
interface EditorAuthorization {
  allowed: boolean;
  activity_id: number;
  mode: string;
  reason: string;
}

interface Authorization {
  allowed: boolean;
  reason: string;
  hint?: string;
  /** Id of the entry in the editor's activity list, when the editor recorded the call. */
  activityId?: number;
}

export class ToolsetController {
  private readonly registeredToolsByName = new Map<string, RegisteredTool>();
  private readonly enabledToolsetNames = new Set<string>();

  constructor(
    private readonly server: McpServer,
    private readonly toolsets: Toolset[],
    private readonly permissionMode: PermissionMode,
    private readonly getContext: () => ToolContext,
    private readonly options: ToolsetControllerOptions = {},
  ) {}

  /** Registers every tool with the MCP server, then enables the requested toolsets. */
  registerAll(initiallyEnabledToolsetNames: string[]): void {
    for (const toolset of this.toolsets) {
      for (const tool of toolset.tools) {
        const registeredTool = this.server.registerTool(
          tool.name,
          {
            title: tool.title,
            description: tool.description,
            inputSchema: tool.inputShape,
            annotations: {
              title: tool.title,
              readOnlyHint: tool.access === "read",
              destructiveHint: tool.destructive,
              openWorldHint: false,
            },
          },
          (input: Record<string, unknown>) => this.runTool(tool, input),
        );
        registeredTool.disable();
        this.registeredToolsByName.set(tool.name, registeredTool);
      }
    }
    const alwaysEnabledNames = this.toolsets
      .filter((toolset) => toolset.alwaysEnabled)
      .map((toolset) => toolset.name);
    this.enable([...alwaysEnabledNames, ...initiallyEnabledToolsetNames]);
  }

  /** Returns the names that were not recognised, so the caller can report them. */
  enable(toolsetNames: string[]): { unknownNames: string[] } {
    const unknownNames: string[] = [];
    for (const toolsetName of toolsetNames) {
      const toolset = this.findToolset(toolsetName);
      if (!toolset) {
        unknownNames.push(toolsetName);
        continue;
      }
      this.enabledToolsetNames.add(toolset.name);
      for (const tool of toolset.tools) {
        if (this.isAllowedByPermissionMode(tool)) {
          this.registeredToolsByName.get(tool.name)?.enable();
        }
      }
    }
    return { unknownNames };
  }

  disable(toolsetNames: string[]): { unknownNames: string[]; refusedNames: string[] } {
    const unknownNames: string[] = [];
    const refusedNames: string[] = [];
    for (const toolsetName of toolsetNames) {
      const toolset = this.findToolset(toolsetName);
      if (!toolset) {
        unknownNames.push(toolsetName);
        continue;
      }
      if (toolset.alwaysEnabled) {
        refusedNames.push(toolset.name);
        continue;
      }
      this.enabledToolsetNames.delete(toolset.name);
      for (const tool of toolset.tools) {
        this.registeredToolsByName.get(tool.name)?.disable();
      }
    }
    return { unknownNames, refusedNames };
  }

  /** Enables exactly these toolsets (plus the always-enabled ones) and disables the rest. */
  setEnabledToolsets(toolsetNames: string[]): { unknownNames: string[] } {
    const toolsetsToDisable = this.toolsets
      .filter((toolset) => !toolset.alwaysEnabled && !toolsetNames.includes(toolset.name))
      .map((toolset) => toolset.name);
    this.disable(toolsetsToDisable);
    return this.enable(toolsetNames);
  }

  isEnabled(toolsetName: string): boolean {
    return this.enabledToolsetNames.has(toolsetName);
  }

  getToolsetNames(): string[] {
    return this.toolsets.map((toolset) => toolset.name);
  }

  list(): ToolsetSummary[] {
    return this.toolsets.map((toolset) => ({
      name: toolset.name,
      title: toolset.title,
      description: toolset.description,
      enabled: this.enabledToolsetNames.has(toolset.name),
      toolNames: toolset.tools
        .filter((tool) => this.isAllowedByPermissionMode(tool))
        .map((tool) => tool.name),
      hiddenToolNames: toolset.tools
        .filter((tool) => !this.isAllowedByPermissionMode(tool))
        .map((tool) => tool.name),
    }));
  }

  private findToolset(toolsetName: string): Toolset | undefined {
    const normalizedName = toolsetName.trim().toLowerCase();
    return this.toolsets.find((toolset) => toolset.name === normalizedName);
  }

  private isAllowedByPermissionMode(tool: PilotTool): boolean {
    return !(this.permissionMode === "read-only" && tool.access === "write");
  }

  /**
   * Tools that only look run directly. Tools that change something first ask the
   * editor: it applies the stricter of the two permission modes (this server's and the
   * one chosen in the Godot Pilot panel), shows the approval dialog in "confirm" mode,
   * takes a checkpoint and lists the change in its activity panel.
   */
  private async runTool(tool: PilotTool, input: Record<string, unknown>): Promise<CallToolResult> {
    const context = this.getContext();
    const result = await this.runToolWithPermission(tool, input, context);
    return addNotices(result, context.editors.takeNotices());
  }

  private async runToolWithPermission(
    tool: PilotTool,
    input: Record<string, unknown>,
    context: ToolContext,
  ): Promise<CallToolResult> {
    try {
      if (tool.access !== "write") {
        return await tool.run(input, context);
      }
      const authorization = await this.authorize(tool, input, context);
      if (!authorization.allowed) {
        return errorResult(authorization.reason, authorization.hint);
      }
      let result: CallToolResult;
      try {
        result = await tool.run(input, context);
      } catch (error) {
        result = errorToResult(error);
      }
      if (authorization.activityId !== undefined) {
        await this.reportFinished(authorization.activityId, result, context);
      }
      return result;
    } catch (error) {
      return errorToResult(error);
    }
  }

  private async authorize(
    tool: PilotTool,
    input: Record<string, unknown>,
    context: ToolContext,
  ): Promise<Authorization> {
    const timeoutSeconds = this.options.confirmationTimeoutSeconds ?? DEFAULT_CONFIRMATION_TIMEOUT_SECONDS;
    try {
      const answer = await context.editors.request<EditorAuthorization>(
        "authorize_tool_call",
        {
          tool: tool.name,
          title: tool.title,
          input,
          server_mode: this.permissionMode,
          client: this.options.getAiClientName?.() ?? "AI",
          timeout_seconds: timeoutSeconds,
        },
        (timeoutSeconds + 15) * 1000,
      );
      if (answer.allowed) {
        return { allowed: true, reason: "", activityId: answer.activity_id };
      }
      return {
        allowed: false,
        reason: answer.reason,
        hint:
          answer.mode === "read-only"
            ? "Only tools that look are allowed now. Tell the person what you would like to change."
            : "Explain what you want to do and why, or ask the person what they would like instead.",
      };
    } catch (error) {
      return this.authorizeWithoutEditor(tool, input, context, error);
    }
  }

  /**
   * The editor could not answer: it is not running, or its addon is older than this
   * server. In "full" mode the tool runs anyway (and reports its own error if it needs
   * the editor). In "confirm" mode nothing may run without the person's approval.
   */
  private async authorizeWithoutEditor(
    tool: PilotTool,
    input: Record<string, unknown>,
    context: ToolContext,
    error: unknown,
  ): Promise<Authorization> {
    if (this.permissionMode !== "confirm") {
      return { allowed: true, reason: "" };
    }
    const isOlderAddon = error instanceof EditorRequestError && error.code === "UNKNOWN_METHOD";
    if (isOlderAddon) {
      const approved = await this.askWithOlderAddon(tool, input, context);
      return approved
        ? { allowed: true, reason: "" }
        : {
            allowed: false,
            reason: "The person at the Godot editor denied this change (permission mode: confirm).",
            hint: "Explain what you want to do and why, or ask them what they would like instead.",
          };
    }
    const message = error instanceof Error ? error.message : String(error);
    return {
      allowed: false,
      reason: `Permission mode "confirm" needs the Godot editor to ask the person, but the editor could not be reached: ${message}`,
      hint: "Call get_status, or launch_editor to open the project.",
    };
  }

  /** Older addons only know the plain confirm_action dialog. */
  private async askWithOlderAddon(
    tool: PilotTool,
    input: Record<string, unknown>,
    context: ToolContext,
  ): Promise<boolean> {
    const timeoutSeconds = this.options.confirmationTimeoutSeconds ?? DEFAULT_CONFIRMATION_TIMEOUT_SECONDS;
    const answer = await context.editors.request<{ allowed: boolean }>(
      "confirm_action",
      {
        title: tool.title,
        description: `The AI wants to use "${tool.name}" with:

${JSON.stringify(input, null, 2)}`,
        timeout_seconds: timeoutSeconds,
      },
      (timeoutSeconds + 10) * 1000,
    );
    return answer.allowed;
  }

  /**
   * Tells the editor's activity panel how the call ended. Waited for (it takes a few
   * milliseconds) so the record is complete even when the AI disconnects right after;
   * a failure is ignored because the tool result itself is what matters.
   */
  private async reportFinished(
    activityId: number,
    result: CallToolResult,
    context: ToolContext,
  ): Promise<void> {
    const firstText = result.content.find((item) => item.type === "text");
    await context.editors
      .request(
        "finish_tool_call",
        {
          activity_id: activityId,
          succeeded: result.isError !== true,
          result: firstText && "text" in firstText ? firstText.text : "",
        },
        FINISH_REPORT_TIMEOUT_MILLISECONDS,
      )
      .catch(() => {
        // The editor may have closed meanwhile; the tool result itself is what matters.
      });
  }
}

/**
 * Adds the editor's news (undo, changes by hand, going back, messages from other AIs)
 * at the end of a tool result, which is the only place the AI is sure to read it.
 */
export function addNotices(result: CallToolResult, notices: EditorNotice[]): CallToolResult {
  if (notices.length === 0) {
    return result;
  }
  const lines = notices.map((notice) => `- ${notice.time} ${notice.text}`);
  const text = ["News from the Godot editor since your last tool call:", ...lines].join("\n");
  return { ...result, content: [...result.content, { type: "text", text }] };
}
