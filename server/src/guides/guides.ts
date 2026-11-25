/**
 * Usage guides written for the AI. They are Markdown files in server/guides and are
 * built into the program, so the compiled binary needs no extra files.
 * They are available through the get_guide tool and as MCP resources.
 */
import csharpAndGdextensionGuide from "../../guides/csharp-and-gdextension.md" with { type: "text" };
import editorScriptsGuide from "../../guides/editor-scripts.md" with { type: "text" };
import workflowGuide from "../../guides/workflow.md" with { type: "text" };

export interface Guide {
  name: string;
  title: string;
  content: string;
}

export const GUIDES: Guide[] = [
  { name: "workflow", title: "How to work in Godot with these tools", content: workflowGuide },
  { name: "editor-scripts", title: "Writing code for execute_editor_script", content: editorScriptsGuide },
  {
    name: "csharp-and-gdextension",
    title: "C# and GDExtension (Rust, C++) projects",
    content: csharpAndGdextensionGuide,
  },
];

export function getGuideNames(): string[] {
  return GUIDES.map((guide) => guide.name);
}
