/**
 * The Godot class reference, taken from the Godot executable installed on this
 * computer, so it always matches the version the person uses.
 *
 * Godot can print its whole API with documentation as JSON:
 *   godot --headless --dump-extension-api-with-docs
 * We run that once per Godot version, keep the file in the cache folder and answer
 * questions from it ("what does Node2D have?", "how do I rotate a node?").
 * Classes added by GDExtensions (for example Rust code) are not in this file; the
 * live editor's ClassDB knows them (see the get_class_docs tool).
 */
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { getCacheDirectory } from "../paths.ts";
import { bbcodeToMarkdown, type CodeLanguage, firstSentence } from "./bbcode-to-markdown.ts";

/* Shapes of the parts of extension_api.json we read. Only the fields we use are listed. */
interface DumpArgument {
  name: string;
  type: string;
  default_value?: string;
}
interface DumpMethod {
  name: string;
  is_static?: boolean;
  is_vararg?: boolean;
  is_virtual?: boolean;
  is_const?: boolean;
  arguments?: DumpArgument[];
  /** Engine classes describe the return value like this... */
  return_value?: { type: string };
  /** ...and built-in types (Vector2, String...) like this. */
  return_type?: string;
  description?: string;
}
interface DumpProperty {
  name: string;
  type: string;
  description?: string;
}
interface DumpSignal {
  name: string;
  arguments?: DumpArgument[];
  description?: string;
}
interface DumpConstant {
  name: string;
  value: number | string;
  type?: string;
  description?: string;
}
interface DumpEnum {
  name: string;
  is_bitfield?: boolean;
  values: { name: string; value: number; description?: string }[];
}
interface DumpClass {
  name: string;
  inherits?: string;
  brief_description?: string;
  description?: string;
  methods?: DumpMethod[];
  properties?: DumpProperty[];
  /** Built-in types call their properties "members". */
  members?: DumpProperty[];
  signals?: DumpSignal[];
  constants?: DumpConstant[];
  enums?: DumpEnum[];
}
interface ApiDump {
  header: { version_full_name?: string };
  global_enums: DumpEnum[];
  utility_functions: DumpMethod[];
  builtin_classes: DumpClass[];
  classes: DumpClass[];
}

export interface ClassDocsOptions {
  /** Only this member (method, property, signal, constant or enum), with its full description. */
  member?: string;
  language?: CodeLanguage;
}

export interface SearchMatch {
  className: string;
  memberName?: string;
  kind: "class" | "method" | "property" | "signal" | "constant" | "enum";
  summary: string;
  score: number;
}

/** Pseudo class for global functions such as lerp() and global enums such as Key. */
export const GLOBAL_SCOPE_NAME = "@GlobalScope";

export class ApiDocumentation {
  private classesByLowercaseName: Map<string, DumpClass> | null = null;
  private loadedVersion = "";

  /**
   * `findGodot` returns the Godot executable and its version. It is a function so
   * the executable is only searched for when documentation is first needed.
   */
  constructor(private readonly findGodot: () => Promise<{ executable: string; version: string }>) {}

  get version(): string {
    return this.loadedVersion;
  }

  async getClassDocs(className: string, options: ClassDocsOptions = {}): Promise<string | null> {
    const classes = await this.loadClasses();
    const classEntry = classes.get(className.toLowerCase());
    if (!classEntry) {
      return null;
    }
    const language = options.language ?? "gdscript";
    if (options.member) {
      return this.formatMember(classEntry, options.member, language);
    }
    return this.formatClass(classEntry, language);
  }

  async hasClass(className: string): Promise<boolean> {
    return (await this.loadClasses()).has(className.toLowerCase());
  }

  /** Class names that look like `wrongName`, to suggest when a lookup fails. */
  async suggestClassNames(wrongName: string, limit = 5): Promise<string[]> {
    const matches = await this.search(wrongName, 30);
    return [...new Set(matches.map((match) => match.className))].slice(0, limit);
  }

  async search(query: string, limit = 20): Promise<SearchMatch[]> {
    const classes = await this.loadClasses();
    const queryWords = query
      .toLowerCase()
      .split(/[\s.]+/)
      .filter((word) => word.length > 0);
    if (queryWords.length === 0) {
      return [];
    }

    const matches: SearchMatch[] = [];
    for (const classEntry of classes.values()) {
      const classScore = scoreName(classEntry.name, queryWords);
      if (classScore > 0) {
        matches.push({
          className: classEntry.name,
          kind: "class",
          summary: firstSentence(bbcodeToMarkdown(classEntry.brief_description ?? "")),
          score: classScore + 5,
        });
      }
      for (const member of listMembers(classEntry)) {
        const memberScore =
          scoreName(member.name, queryWords) +
          // A query like "sprite texture" matches Sprite2D.texture better than Light2D.texture.
          (classScore > 0 ? classScore / 2 : 0) +
          scoreDescription(member.description ?? "", queryWords);
        if (memberScore > 0) {
          matches.push({
            className: classEntry.name,
            memberName: member.name,
            kind: member.kind,
            summary: firstSentence(bbcodeToMarkdown(member.description ?? "")),
            score: memberScore,
          });
        }
      }
    }
    return matches.sort((first, second) => second.score - first.score).slice(0, limit);
  }

  private formatClass(classEntry: DumpClass, language: CodeLanguage): string {
    const sections: string[] = [];
    const ancestors = this.getAncestorNames(classEntry);
    sections.push(
      `# ${classEntry.name}${ancestors.length > 0 ? ` (inherits ${ancestors.join(" < ")})` : ""}`,
    );
    if (classEntry.brief_description) {
      sections.push(bbcodeToMarkdown(classEntry.brief_description, language));
    }
    if (classEntry.description) {
      sections.push(bbcodeToMarkdown(classEntry.description, language));
    }

    const properties = classEntry.properties ?? classEntry.members ?? [];
    if (properties.length > 0) {
      sections.push(
        `## Properties\n${properties
          .map(
            (property) =>
              `- ${property.name}: ${formatType(property.type)}${summarySuffix(property.description)}`,
          )
          .join("\n")}`,
      );
    }
    const methods = classEntry.methods ?? [];
    if (methods.length > 0) {
      sections.push(
        `## Methods\n${methods.map((method) => `- ${formatMethodSignature(method)}${summarySuffix(method.description)}`).join("\n")}`,
      );
    }
    const signals = classEntry.signals ?? [];
    if (signals.length > 0) {
      sections.push(
        `## Signals\n${signals
          .map(
            (signal) =>
              `- ${signal.name}(${formatArguments(signal.arguments)})${summarySuffix(signal.description)}`,
          )
          .join("\n")}`,
      );
    }
    const enums = classEntry.enums ?? [];
    if (enums.length > 0) {
      sections.push(
        `## Enums\n${enums
          .map(
            (enumEntry) =>
              `- ${enumEntry.name}: ${enumEntry.values.map((value) => `${value.name}=${value.value}`).join(", ")}`,
          )
          .join("\n")}`,
      );
    }
    const constants = classEntry.constants ?? [];
    if (constants.length > 0) {
      sections.push(
        `## Constants\n${constants.map((constant) => `- ${constant.name} = ${constant.value}`).join("\n")}`,
      );
    }
    if (ancestors.length > 0) {
      sections.push(`Inherited members are documented on ${ancestors.join(", ")}.`);
    }
    return sections.join("\n\n");
  }

  /** Looks for the member on the class and then on its ancestors. */
  private formatMember(classEntry: DumpClass, memberName: string, language: CodeLanguage): string | null {
    const wantedName = memberName.toLowerCase().replace(/\(\)$/, "");
    let currentClass: DumpClass | undefined = classEntry;
    while (currentClass) {
      const member = listMembers(currentClass).find(
        (candidate) => candidate.name.toLowerCase() === wantedName,
      );
      if (member) {
        const ownerNote = currentClass === classEntry ? "" : ` (inherited from ${currentClass.name})`;
        return `# ${classEntry.name}.${member.signature}${ownerNote}\n${member.kind}\n\n${bbcodeToMarkdown(member.description ?? "No description.", language)}`;
      }
      currentClass = currentClass.inherits
        ? this.classesByLowercaseName?.get(currentClass.inherits.toLowerCase())
        : undefined;
    }
    return null;
  }

  private getAncestorNames(classEntry: DumpClass): string[] {
    const ancestors: string[] = [];
    let parentName = classEntry.inherits;
    while (parentName) {
      ancestors.push(parentName);
      parentName = this.classesByLowercaseName?.get(parentName.toLowerCase())?.inherits;
    }
    return ancestors;
  }

  private async loadClasses(): Promise<Map<string, DumpClass>> {
    if (this.classesByLowercaseName) {
      return this.classesByLowercaseName;
    }
    const { executable, version } = await this.findGodot();
    const dumpFilePath = await ensureApiDumpFile(executable, version);
    const dump = (await Bun.file(dumpFilePath).json()) as ApiDump;

    const classes = new Map<string, DumpClass>();
    for (const classEntry of [...dump.builtin_classes, ...dump.classes]) {
      classes.set(classEntry.name.toLowerCase(), classEntry);
    }
    classes.set(GLOBAL_SCOPE_NAME.toLowerCase(), {
      name: GLOBAL_SCOPE_NAME,
      brief_description:
        "Global functions (like lerp, clamp, print) and global enums (like Key, MouseButton).",
      methods: dump.utility_functions,
      enums: dump.global_enums,
    });

    this.classesByLowercaseName = classes;
    this.loadedVersion = dump.header.version_full_name ?? version;
    return classes;
  }
}

interface ListedMember {
  name: string;
  kind: Exclude<SearchMatch["kind"], "class">;
  description?: string;
  signature: string;
}

function listMembers(classEntry: DumpClass): ListedMember[] {
  return [
    ...(classEntry.methods ?? []).map((method) => ({
      name: method.name,
      kind: "method" as const,
      description: method.description,
      signature: formatMethodSignature(method),
    })),
    ...(classEntry.properties ?? classEntry.members ?? []).map((property) => ({
      name: property.name,
      kind: "property" as const,
      description: property.description,
      signature: `${property.name}: ${formatType(property.type)}`,
    })),
    ...(classEntry.signals ?? []).map((signal) => ({
      name: signal.name,
      kind: "signal" as const,
      description: signal.description,
      signature: `${signal.name}(${formatArguments(signal.arguments)})`,
    })),
    ...(classEntry.constants ?? []).map((constant) => ({
      name: constant.name,
      kind: "constant" as const,
      description: constant.description,
      signature: `${constant.name} = ${constant.value}`,
    })),
    ...(classEntry.enums ?? []).map((enumEntry) => ({
      name: enumEntry.name,
      kind: "enum" as const,
      description: enumEntry.values.map((value) => `${value.name} = ${value.value}`).join(", "),
      signature: enumEntry.name,
    })),
  ];
}

/** Higher when the name matches the query words more exactly. */
function scoreName(name: string, queryWords: string[]): number {
  const lowercaseName = name.toLowerCase();
  const joinedQuery = queryWords.join("_");
  if (lowercaseName === joinedQuery || lowercaseName === queryWords.join("")) {
    return 20;
  }
  let score = 0;
  for (const word of queryWords) {
    if (lowercaseName === word) {
      score += 10;
    } else if (lowercaseName.startsWith(word)) {
      score += 5;
    } else if (lowercaseName.includes(word)) {
      score += 3;
    }
  }
  return score;
}

function scoreDescription(description: string, queryWords: string[]): number {
  if (queryWords.length < 2) {
    return 0;
  }
  const lowercaseDescription = description.toLowerCase();
  const matchedWordCount = queryWords.filter((word) => lowercaseDescription.includes(word)).length;
  return matchedWordCount === queryWords.length ? 2 : 0;
}

/** "enum::Node.InternalMode" -> "Node.InternalMode", "typedarray::Node" -> "Array[Node]". */
function formatType(type: string): string {
  if (type.startsWith("typedarray::")) {
    return `Array[${type.slice("typedarray::".length)}]`;
  }
  if (type.startsWith("typeddictionary::")) {
    const [keyType, valueType] = type.slice("typeddictionary::".length).split(";");
    return `Dictionary[${keyType}, ${valueType}]`;
  }
  return type.replace(/^(enum|bitfield)::/, "");
}

function formatArguments(argumentList: DumpArgument[] | undefined): string {
  return (argumentList ?? [])
    .map((argument) => {
      const defaultValue = argument.default_value !== undefined ? ` = ${argument.default_value}` : "";
      return `${argument.name}: ${formatType(argument.type)}${defaultValue}`;
    })
    .join(", ");
}

function formatMethodSignature(method: DumpMethod): string {
  const returnType = method.return_value?.type ?? method.return_type ?? "void";
  const qualifiers = [
    method.is_static ? "static" : "",
    method.is_virtual ? "virtual" : "",
    method.is_const ? "const" : "",
  ]
    .filter((qualifier) => qualifier !== "")
    .join(" ");
  const variadicMarker = method.is_vararg ? ", ..." : "";
  return `${method.name}(${formatArguments(method.arguments)}${variadicMarker}) -> ${formatType(returnType)}${qualifiers ? ` [${qualifiers}]` : ""}`;
}

function summarySuffix(description: string | undefined): string {
  if (!description) {
    return "";
  }
  return ` — ${firstSentence(bbcodeToMarkdown(description))}`;
}

/** Creates the API dump for this Godot version once and returns its path. */
async function ensureApiDumpFile(godotExecutable: string, godotVersion: string): Promise<string> {
  // "4.7.2-stable (official)" and "4.7.2.stable.official.ed1daf0bf" are the same version.
  const versionMatch = /(\d+\.\d+(?:\.\d+)?)[.-]?(stable|beta\d*|rc\d*|dev\d*)?/.exec(godotVersion);
  const safeVersionName = versionMatch ? `${versionMatch[1]}-${versionMatch[2] ?? "custom"}` : "unknown";
  const cacheDirectory = join(getCacheDirectory(), "api");
  const dumpFilePath = join(cacheDirectory, `${safeVersionName}.json`);
  if (await Bun.file(dumpFilePath).exists()) {
    return dumpFilePath;
  }

  await mkdir(cacheDirectory, { recursive: true });
  // Godot writes extension_api.json into its working folder, so give it an empty one.
  const workingDirectory = await mkdtemp(join(tmpdir(), "godot-pilot-api-"));
  try {
    const dumpProcess = Bun.spawn([godotExecutable, "--headless", "--dump-extension-api-with-docs"], {
      cwd: workingDirectory,
      stdout: "ignore",
      stderr: "ignore",
    });
    await dumpProcess.exited;
    const producedFilePath = join(workingDirectory, "extension_api.json");
    if (!(await Bun.file(producedFilePath).exists())) {
      throw new Error(`Godot (${godotExecutable}) did not produce the API documentation file.`);
    }
    // Copy instead of rename: the temp folder may be on another drive.
    await Bun.write(dumpFilePath, Bun.file(producedFilePath));
  } finally {
    await rm(workingDirectory, { recursive: true, force: true });
  }
  return dumpFilePath;
}
