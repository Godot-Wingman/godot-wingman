/**
 * How a tool is described in this project, plus helpers to build tool results.
 *
 * Every tool says what it may do (`access`), so the permission modes can hide or
 * guard it:
 * - "read":  only looks (scene tree, logs, screenshots, docs).
 * - "write": changes the project or the editor (can usually be undone with Ctrl+Z).
 * - "setup": installs the addon or starts the editor; allowed in every mode because
 *            nothing else works without it.
 */
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import type { z } from "zod";
import type { ApiDocumentation } from "../docs/api-documentation.ts";
import { EditorRequestError } from "../godot/editor-connection.ts";
import type { EditorManager } from "../godot/editor-manager.ts";
import type { PermissionMode } from "./permission-mode.ts";
import type { ToolsetController } from "./toolset-controller.ts";

export type ToolAccess = "read" | "write" | "setup";

/** Everything a tool may need while it runs. */
export interface ToolContext {
  editors: EditorManager;
  docs: ApiDocumentation;
  toolsets: ToolsetController;
  permissionMode: PermissionMode;
}

export interface PilotTool {
  name: string;
  title: string;
  /** Written for the AI: when to use the tool, what it returns, an example. */
  description: string;
  inputShape: z.ZodRawShape;
  access: ToolAccess;
  /** Deletes or overwrites something in a way that may be hard to undo. */
  destructive: boolean;
  run(input: Record<string, unknown>, context: ToolContext): Promise<CallToolResult>;
}

interface ToolDefinitionInput<Shape extends z.ZodRawShape> {
  name: string;
  title: string;
  description: string;
  inputShape: Shape;
  access: ToolAccess;
  destructive?: boolean;
  run(input: z.infer<z.ZodObject<Shape>>, context: ToolContext): Promise<CallToolResult>;
}

/**
 * Defines a tool with a typed `run` function. The MCP SDK validates the input
 * against `inputShape` before `run` is called, which is why the cast below is safe.
 */
export function defineTool<Shape extends z.ZodRawShape>(definition: ToolDefinitionInput<Shape>): PilotTool {
  return {
    ...definition,
    destructive: definition.destructive ?? false,
    run: (input, context) => definition.run(input as z.infer<z.ZodObject<Shape>>, context),
  };
}

export function textResult(text: string): CallToolResult {
  return { content: [{ type: "text", text }] };
}

/** Compact JSON: indentation would cost the AI tokens without adding information. */
export function jsonResult(value: unknown): CallToolResult {
  return textResult(JSON.stringify(value));
}

export function imageResult(base64Data: string, mimeType: string, caption?: string): CallToolResult {
  const content: CallToolResult["content"] = [{ type: "image", data: base64Data, mimeType }];
  if (caption) {
    content.push({ type: "text", text: caption });
  }
  return { content };
}

export function errorResult(message: string, hint?: string, details?: unknown): CallToolResult {
  const lines = [message];
  if (hint) {
    lines.push(`Hint: ${hint}`);
  }
  if (details !== undefined && details !== null) {
    lines.push(`Details: ${JSON.stringify(details)}`);
  }
  return { content: [{ type: "text", text: lines.join("\n") }], isError: true };
}

/** Turns any thrown error into a tool result the AI can learn from. */
export function errorToResult(error: unknown): CallToolResult {
  if (error instanceof EditorRequestError) {
    return errorResult(`[${error.code}] ${error.message}`, error.hint, error.details);
  }
  if (error instanceof Error) {
    const hint = "hint" in error && typeof error.hint === "string" ? error.hint : undefined;
    return errorResult(error.message, hint);
  }
  return errorResult(String(error));
}

/** Sends a request to the editor and returns the answer as JSON. */
export async function forwardToEditor(
  context: ToolContext,
  method: string,
  params: object = {},
  timeoutMilliseconds?: number,
): Promise<CallToolResult> {
  const result = await context.editors.request(method, params, timeoutMilliseconds);
  return jsonResult(result);
}

interface EditorToolDefinitionInput<Shape extends z.ZodRawShape> {
  name: string;
  title: string;
  description: string;
  inputShape: Shape;
  access: ToolAccess;
  destructive?: boolean;
  /** Name of the request handler in the Godot addon. */
  editorMethod: string;
  timeoutSeconds?: number;
}

/**
 * Most tools only check their input and pass it on to the addon, which does the work
 * inside the editor. This builds such a tool without repeating the forwarding code.
 */
export function defineEditorTool<Shape extends z.ZodRawShape>(
  definition: EditorToolDefinitionInput<Shape>,
): PilotTool {
  const timeoutMilliseconds = definition.timeoutSeconds ? definition.timeoutSeconds * 1000 : undefined;
  return defineTool({
    ...definition,
    run: (input, context) => forwardToEditor(context, definition.editorMethod, input, timeoutMilliseconds),
  });
}
