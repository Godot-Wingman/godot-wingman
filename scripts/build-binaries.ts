/**
 * Compiles the MCP server into one standalone executable per platform with
 * `bun build --compile`. The executables contain Bun itself, the addon and the guides,
 * so people need nothing else installed.
 *
 * Usage: bun run build            (all platforms)
 *        bun run build -- current  (only this computer's platform, faster)
 */
import { join } from "node:path";

const repositoryRoot = join(import.meta.dir, "..");
const entryPoint = join(repositoryRoot, "server", "src", "main.ts");
const outputDirectory = join(repositoryRoot, "dist");

interface BuildTarget {
  bunTarget: string;
  outputName: string;
}

const ALL_TARGETS: BuildTarget[] = [
  { bunTarget: "bun-windows-x64", outputName: "godot-pilot-windows-x64.exe" },
  { bunTarget: "bun-linux-x64", outputName: "godot-pilot-linux-x64" },
  { bunTarget: "bun-linux-arm64", outputName: "godot-pilot-linux-arm64" },
  { bunTarget: "bun-darwin-x64", outputName: "godot-pilot-macos-x64" },
  { bunTarget: "bun-darwin-arm64", outputName: "godot-pilot-macos-arm64" },
];

function currentPlatformTarget(): BuildTarget {
  const platformName =
    { win32: "windows", darwin: "darwin", linux: "linux" }[process.platform as string] ?? "linux";
  const architecture = process.arch === "arm64" ? "arm64" : "x64";
  const extension = process.platform === "win32" ? ".exe" : "";
  const readablePlatform = platformName === "darwin" ? "macos" : platformName;
  return {
    bunTarget: `bun-${platformName}-${architecture}`,
    outputName: `godot-pilot-${readablePlatform}-${architecture}${extension}`,
  };
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
    ],
    { stdout: "inherit", stderr: "inherit" },
  );
  if ((await buildProcess.exited) !== 0) {
    console.error(`Build failed for ${target.bunTarget}.`);
    process.exit(1);
  }
}
console.log(`Built ${targets.length} executable(s) in dist/`);
