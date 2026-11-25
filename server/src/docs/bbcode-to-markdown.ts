/**
 * Godot writes its class reference in a BBCode dialect ("[b]bold[/b]",
 * "[method add_child]", "[codeblocks]..."). AI models read Markdown best, so we
 * convert it. Only the tags used by the class reference are handled.
 */

const GODOT_DOCS_URL = "https://docs.godotengine.org/en/stable";

export type CodeLanguage = "gdscript" | "csharp";

export function bbcodeToMarkdown(text: string, preferredLanguage: CodeLanguage = "gdscript"): string {
  let converted = text.replaceAll("$DOCS_URL", GODOT_DOCS_URL);

  // [codeblocks] holds one example per language; keep only the preferred one.
  converted = converted.replace(
    /\[codeblocks\]([\s\S]*?)\[\/codeblocks\]/g,
    (_wholeMatch, blocks: string) => {
      const languageBlock = new RegExp(
        `\\[${preferredLanguage}\\]([\\s\\S]*?)\\[\\/${preferredLanguage}\\]`,
      ).exec(blocks);
      const anyBlock = /\[(gdscript|csharp)\]([\s\S]*?)\[\/\1\]/.exec(blocks);
      const code = languageBlock?.[1] ?? anyBlock?.[2] ?? "";
      const language = languageBlock ? preferredLanguage : (anyBlock?.[1] ?? "");
      return `\n\`\`\`${language}\n${code.trim()}\n\`\`\`\n`;
    },
  );
  converted = converted.replace(
    /\[codeblock(?: lang=(\w+))?\]([\s\S]*?)\[\/codeblock\]/g,
    (_wholeMatch, language: string | undefined, code: string) =>
      `\n\`\`\`${language ?? ""}\n${code.trim()}\n\`\`\`\n`,
  );

  converted = converted
    .replace(/\[code\]([\s\S]*?)\[\/code\]/g, "`$1`")
    .replace(/\[kbd\]([\s\S]*?)\[\/kbd\]/g, "`$1`")
    .replace(/\[b\]([\s\S]*?)\[\/b\]/g, "**$1**")
    .replace(/\[i\]([\s\S]*?)\[\/i\]/g, "*$1*")
    .replace(/\[u\]([\s\S]*?)\[\/u\]/g, "$1")
    .replace(/\[url=([^\]]+)\]([\s\S]*?)\[\/url\]/g, "[$2]($1)")
    .replace(/\[url\]([\s\S]*?)\[\/url\]/g, "$1")
    .replace(/\[method ([^\]]+)\]/g, "`$1()`")
    .replace(
      /\[(?:member|signal|constant|enum|param|annotation|operator|constructor|theme_item) ([^\]]+)\]/g,
      "`$1`",
    )
    .replace(/\[\/?(?:center|color[^\]]*|font[^\]]*)\]/g, "")
    .replace(/\[br\]/g, "\n")
    .replace(/\[lb\]/g, "[")
    .replace(/\[rb\]/g, "]")
    // A bare class name in brackets, like [Node2D] or [@GlobalScope].
    .replace(/\[(@?[A-Z][A-Za-z0-9_]*)\]/g, "`$1`");

  return converted.trim();
}

/** The first sentence of a description, short enough for a one-line summary. */
export function firstSentence(markdown: string, maximumLength = 180): string {
  const singleLine = markdown.split("\n")[0]?.trim() ?? "";
  const sentenceEnd = singleLine.search(/\.(\s|$)/);
  const sentence = sentenceEnd === -1 ? singleLine : singleLine.slice(0, sentenceEnd + 1);
  return sentence.length > maximumLength ? `${sentence.slice(0, maximumLength - 1)}…` : sentence;
}
