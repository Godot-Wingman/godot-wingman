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

const CONFIRMATION_TIMEOUT_SECONDS = 180;

export class ToolsetController {
  private readonly registeredToolsByName = new Map<string, RegisteredTool>();
  private readonly enabledToolsetNames = new Set<string>();

  constructor(
    private readonly server: McpServer,
    private readonly toolsets: Toolset[],
    private readonly permissionMode: PermissionMode,
    private readonly getContext: () => ToolContext,
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

  private async runTool(tool: PilotTool, input: Record<string, unknown>): Promise<CallToolResult> {
    const context = this.getContext();
    try {
      if (this.permissionMode === "confirm" && tool.access === "write") {
        const approved = await this.askPersonForApproval(tool, input, context);
        if (!approved) {
          return errorResult(
            "The person at the Godot editor denied this change (permission mode: confirm).",
            "Explain what you want to do and why, or ask them what they would like instead.",
          );
        }
      }
      return await tool.run(input, context);
    } catch (error) {
      return errorToResult(error);
    }
  }

  private async askPersonForApproval(
    tool: PilotTool,
    input: Record<string, unknown>,
    context: ToolContext,
  ): Promise<boolean> {
    const inputDescription = JSON.stringify(input, null, 2);
    const shortenedInput =
      inputDescription.length > 1500
        ? `${inputDescription.slice(0, 1500)}\n... (shortened)`
        : inputDescription;
    const answer = await context.editors.request<{ allowed: boolean }>(
      "confirm_action",
      {
        title: tool.title,
        description: `The AI wants to use "${tool.name}" with:\n\n${shortenedInput}`,
        timeout_seconds: CONFIRMATION_TIMEOUT_SECONDS,
      },
      (CONFIRMATION_TIMEOUT_SECONDS + 10) * 1000,
    );
    return answer.allowed;
  }
}
