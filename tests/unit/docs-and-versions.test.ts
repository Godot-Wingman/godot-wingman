import { describe, expect, test } from "bun:test";
import packageJson from "../../package.json" with { type: "json" };
import { getBundledAddonVersion } from "../../server/src/addon/addon-installer.ts";
import { bbcodeToMarkdown, firstSentence } from "../../server/src/docs/bbcode-to-markdown.ts";
import { compareVersions, readVersionFromFileName } from "../../server/src/godot/find-godot-executable.ts";
import { parsePermissionMode } from "../../server/src/mcp/permission-mode.ts";

describe("bbcodeToMarkdown", () => {
  test("converts inline tags", () => {
    expect(bbcodeToMarkdown("Call [method add_child] on [Node] with [param node]. [b]Note:[/b] [code]true[/code]")).toBe(
      "Call `add_child()` on `Node` with `node`. **Note:** `true`",
    );
  });

  test("keeps only the preferred language of code examples", () => {
    const text = "[codeblocks][gdscript]print(1)[/gdscript][csharp]GD.Print(1);[/csharp][/codeblocks]";
    expect(bbcodeToMarkdown(text, "gdscript")).toBe("```gdscript\nprint(1)\n```");
    expect(bbcodeToMarkdown(text, "csharp")).toBe("```csharp\nGD.Print(1);\n```");
  });

  test("turns documentation links into Markdown links", () => {
    expect(bbcodeToMarkdown("[url=$DOCS_URL/a.html]tutorial[/url]")).toBe(
      "[tutorial](https://docs.godotengine.org/en/stable/a.html)",
    );
  });

  test("firstSentence stops at the first full stop", () => {
    expect(firstSentence("Moves the body. Then more text.")).toBe("Moves the body.");
  });
});

describe("versions", () => {
  test("reads Godot versions from download file names", () => {
    expect(readVersionFromFileName("Godot_v4.7.2-stable_win64.exe")).toBe("4.7.2");
    expect(readVersionFromFileName("Godot_v4.5-stable_linux.x86_64")).toBe("4.5");
  });

  test("compares versions numerically", () => {
    expect(compareVersions("4.10", "4.9")).toBeGreaterThan(0);
    expect(compareVersions("4.7.2", "4.7")).toBeGreaterThan(0);
    expect(compareVersions("", "4.0")).toBeLessThan(0);
  });

  test("the addon and the server have the same version", () => {
    expect(getBundledAddonVersion()).toBe(packageJson.version);
  });
});

test("parsePermissionMode accepts the documented modes", () => {
  expect(parsePermissionMode(undefined)).toBe("full");
  expect(parsePermissionMode("readonly")).toBe("read-only");
  expect(parsePermissionMode("Confirm")).toBe("confirm");
  expect(() => parsePermissionMode("yolo")).toThrow();
});
