/**
 * Core tools that answer "how does Godot work?": the class reference of the installed
 * Godot version, live class information from the editor, and the usage guides.
 */
import { z } from "zod";
import { GUIDES, getGuideNames } from "../../guides/guides.ts";
import { defineTool, errorResult, jsonResult, textResult } from "../../mcp/tool-definition.ts";

export const getClassDocsTool = defineTool({
  name: "get_class_docs",
  title: "Read Godot class documentation",
  description:
    'Returns the documentation of a Godot class for the exact Godot version in use: description, properties, methods with signatures, signals, enums. Pass member for the full text of one method/property/signal. Works for built-in types (Vector2, String), engine classes (CharacterBody2D) and "@GlobalScope" (lerp, clamp, Key enum). Classes from GDExtensions or scripts with class_name are read from the running editor. Check here before using an API you are not sure about.',
  inputShape: {
    class_name: z.string().describe('Class name, for example "Node2D", "Vector3" or "@GlobalScope".'),
    member: z.string().optional().describe('One member, for example "move_and_slide" or "velocity".'),
    language: z
      .enum(["gdscript", "csharp"])
      .optional()
      .describe("Language of code examples. Default: gdscript."),
  },
  access: "read",
  async run(input, context) {
    const documentation = await context.docs.getClassDocs(input.class_name, {
      member: input.member,
      language: input.language,
    });
    if (documentation) {
      return textResult(documentation);
    }
    if (input.member && (await context.docs.hasClass(input.class_name))) {
      return errorResult(
        `${input.class_name} has no member named '${input.member}' (also not inherited).`,
        `Call get_class_docs with only class_name "${input.class_name}" to see all members.`,
      );
    }

    // Not an engine class: maybe a GDExtension class or a script with class_name.
    try {
      const liveClassInformation = await context.editors.request("get_class_info", {
        class_name: input.class_name,
      });
      return jsonResult(liveClassInformation);
    } catch {
      const suggestions = await context.docs.suggestClassNames(input.class_name);
      return errorResult(
        `Unknown class '${input.class_name}'.`,
        suggestions.length > 0
          ? `Did you mean: ${suggestions.join(", ")}?`
          : "Use search_docs to find the right name.",
      );
    }
  },
});

export const searchDocsTool = defineTool({
  name: "search_docs",
  title: "Search Godot documentation",
  description:
    'Searches class names, methods, properties and signals of the installed Godot version. Use it when you know what you want to do but not the exact name, for example "raycast", "tween property" or "play sound". Then read the details with get_class_docs.',
  inputShape: {
    query: z.string().describe("Words to look for."),
    limit: z.number().int().min(1).max(100).optional().describe("Maximum number of results. Default: 20."),
  },
  access: "read",
  async run(input, context) {
    const matches = await context.docs.search(input.query, input.limit ?? 20);
    if (matches.length === 0) {
      return textResult(`Nothing found for '${input.query}'. Try other or fewer words.`);
    }
    const lines = matches.map((match) => {
      const name = match.memberName ? `${match.className}.${match.memberName}` : match.className;
      return `- ${name} (${match.kind})${match.summary ? ` — ${match.summary}` : ""}`;
    });
    return textResult(
      `Godot ${context.docs.version} documentation, best matches first:\n${lines.join("\n")}`,
    );
  },
});

export const getGuideTool = defineTool({
  name: "get_guide",
  title: "Read a usage guide",
  description: `Returns a short guide on how to do things well with these tools. Topics: ${getGuideNames().join(", ")}. Read "workflow" at the start of bigger tasks.`,
  inputShape: {
    topic: z.enum(getGuideNames() as [string, ...string[]]).describe("Guide topic."),
  },
  access: "read",
  async run(input) {
    const guide = GUIDES.find((candidate) => candidate.name === input.topic);
    return guide ? textResult(guide.content) : errorResult(`No guide named '${input.topic}'.`);
  },
});
