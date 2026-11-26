/**
 * Compiles the MCP server into one standalone executable per platform with
 * `bun build --compile`. The executables contain Bun itself, the addon and the guides,
 * so people need nothing else installed.
 *
 * Usage: bun run build            (all platforms)
 *        bun run build -- current  (only this computer's platform, faster)
 */
import { join } from "node:path";
import packageJson from "../package.json" with { type: "json" };

const repositoryRoot = join(import.meta.dir, "..");
const entryPoint = join(repositoryRoot, "server", "src", "main.ts");
const outputDirectory = join(repositoryRoot, "dist");

interface BuildTarget {
  bunTarget: string;
  outputName: string;
}

const ALL_TARGETS: BuildTarget[] = [
  { bunTarget: "bun-windows-x64", outputName: "godot-wingman-windows-x64.exe" },
  { bunTarget: "bun-linux-x64", outputName: "godot-wingman-linux-x64" },
  { bunTarget: "bun-linux-arm64", outputName: "godot-wingman-linux-arm64" },
  { bunTarget: "bun-darwin-x64", outputName: "godot-wingman-macos-x64" },
  { bunTarget: "bun-darwin-arm64", outputName: "godot-wingman-macos-arm64" },
];

function currentPlatformTarget(): BuildTarget {
  const platformName =
    { win32: "windows", darwin: "darwin", linux: "linux" }[process.platform as string] ?? "linux";
  const architecture = process.arch === "arm64" ? "arm64" : "x64";
  const extension = process.platform === "win32" ? ".exe" : "";
  const readablePlatform = platformName === "darwin" ? "macos" : platformName;
  return {
    bunTarget: `bun-${platformName}-${architecture}`,
    outputName: `godot-wingman-${readablePlatform}-${architecture}${extension}`,
  };
}

/**
 * Name, description and version shown in the Windows file properties, so the program
 * does not look like an unknown file.
 */
function windowsDetails(target: BuildTarget): string[] {
  if (!target.bunTarget.startsWith("bun-windows")) {
    return [];
  }
  const numericVersion = `${packageJson.version.replace(/[^0-9.].*$/, "")}.0`;
  return [
    "--windows-title=Godot Wingman",
    "--windows-publisher=Godot Wingman",
    "--windows-description=Godot Wingman: lets AI apps use the Godot editor",
    `--windows-version=${numericVersion}`,
    "--windows-copyright=AGPL-3.0, Godot Wingman contributors",
  ];
}

const onlyCurrentPlatform = process.argv.includes("current");
const targets = onlyCurrentPlatform ? [currentPlatformTarget()] : ALL_TARGETS;

for (const target of targets) {
  const outputPath = join(outputDirectory, target.outputName);
  const buildProcess = Bun.spawn(
    [
      "bun",
      "build",
      entryPoint,
      "--compile",
      "--minify",
      `--target=${target.bunTarget}`,
      "--outfile",
      outputPath,
      ...windowsDetails(target),
    ],
    { stdout: "inherit", stderr: "inherit" },
  );
  if ((await buildProcess.exited) !== 0) {
    console.error(`Build failed for ${target.bunTarget}.`);
    process.exit(1);
  }
}
console.log(`Built ${targets.length} executable(s) in dist/`);
