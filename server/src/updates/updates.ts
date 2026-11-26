/**
 * Finding and installing new versions of Godot Pilot.
 *
 * - Checking: at most once a day, the server asks GitHub for the list of releases of
 *   this project (a plain download, like opening the releases page; nothing about the
 *   person or their project is sent). When a newer version exists, the AI is told
 *   with its next tool result and can offer the update. Turn it off with
 *   --no-update-check or GODOT_PILOT_NO_UPDATE_CHECK=1.
 * - Installing (the update_godot_pilot tool, or `godot-pilot update`): downloads the
 *   executable for this computer from the newest release, checks it against the
 *   release's SHA256SUMS file, and swaps it in. A running program cannot be
 *   overwritten on Windows, but it can be renamed, so the old file is moved aside and
 *   deleted at the next start. The new version runs from the next start on.
 */
import { createHash } from "node:crypto";
import { chmod, mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { getProductHomeDirectory } from "../paths.ts";
import { PRODUCT_NAME, PRODUCT_REPOSITORY, PRODUCT_VERSION } from "../product.ts";

export const NO_UPDATE_CHECK_ENVIRONMENT_VARIABLE = "GODOT_PILOT_NO_UPDATE_CHECK";
const RELEASES_URL = `https://api.github.com/repos/${PRODUCT_REPOSITORY}/releases?per_page=20`;
const CHECK_INTERVAL_MILLISECONDS = 24 * 60 * 60 * 1000;
/** The AI mentions an available version again after this long, if it was not installed. */
const REMINDER_INTERVAL_MILLISECONDS = 7 * 24 * 60 * 60 * 1000;
const REQUEST_TIMEOUT_MILLISECONDS = 10_000;
const CHECKSUMS_ASSET_NAME = "SHA256SUMS";

export interface ReleaseAsset {
  name: string;
  downloadUrl: string;
}

export interface Release {
  version: string;
  pageUrl: string;
  assets: ReleaseAsset[];
}

/** Remembered in <data>/godot-pilot/update-check.json between runs. */
interface UpdateCheckRecord {
  checkedAtMilliseconds: number;
  newestRelease: Release | null;
  /** Version the AI was last told about, and when. */
  announcedVersion?: string;
  announcedAtMilliseconds?: number;
}

/** What `fetch` looks like, so tests can answer without the internet. */
export type Fetcher = (url: string, init?: RequestInit) => Promise<Response>;

export interface UpdateOptions {
  fetcher?: Fetcher;
  nowMilliseconds?: number;
  /** Ask GitHub even when the last check was less than a day ago. */
  ignoreCachedCheck?: boolean;
  currentVersion?: string;
}

/**
 * Compares "0.2.0", "v0.10.1", "1.0.0-beta.2". Returns a negative number when first is
 * older, 0 when equal, positive when newer. A version with a suffix ("-beta") is older
 * than the same version without one.
 */
export function compareVersions(firstVersion: string, secondVersion: string): number {
  const parse = (version: string) => {
    const [mainPart = "", suffix = ""] = version.trim().replace(/^v/i, "").split("-", 2);
    return { numbers: mainPart.split(".").map((part) => Number.parseInt(part, 10) || 0), suffix };
  };
  const first = parse(firstVersion);
  const second = parse(secondVersion);
  for (let index = 0; index < Math.max(first.numbers.length, second.numbers.length); index++) {
    const difference = (first.numbers[index] ?? 0) - (second.numbers[index] ?? 0);
    if (difference !== 0) {
      return difference;
    }
  }
  if (first.suffix === second.suffix) {
    return 0;
  }
  if (first.suffix === "") {
    return 1;
  }
  if (second.suffix === "") {
    return -1;
  }
  return first.suffix.localeCompare(second.suffix, "en", { numeric: true });
}

/** Name of the executable for a platform in a release, as built by scripts/build-binaries.ts. */
export function getReleaseAssetName(
  platform: string = process.platform,
  architecture: string = process.arch,
): string {
  const platformName = { win32: "windows", darwin: "macos", linux: "linux" }[platform] ?? "linux";
  const architectureName = architecture === "arm64" ? "arm64" : "x64";
  const extension = platform === "win32" ? ".exe" : "";
  return `${PRODUCT_NAME}-${platformName}-${architectureName}${extension}`;
}

/** True for the single-file executable from a release; false when running from source with Bun. */
export function isRunningAsExecutable(): boolean {
  return !/^bun(\.exe)?$/i.test(basename(process.execPath));
}

export function isUpdateCheckDisabled(): boolean {
  const value = process.env[NO_UPDATE_CHECK_ENVIRONMENT_VARIABLE];
  return value !== undefined && value !== "" && value !== "0";
}

/** Asks GitHub for the newest release, drafts left out. Throws when GitHub cannot be reached. */
export async function fetchNewestRelease(fetcher: Fetcher = fetch): Promise<Release | null> {
  const response = await fetcher(RELEASES_URL, {
    headers: { Accept: "application/vnd.github+json", "User-Agent": PRODUCT_NAME },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MILLISECONDS),
  });
  if (!response.ok) {
    throw new Error(`GitHub answered ${response.status} for the list of releases.`);
  }
  const releases = (await response.json()) as {
    tag_name: string;
    html_url: string;
    draft: boolean;
    assets: { name: string; browser_download_url: string }[];
  }[];
  let newestRelease: Release | null = null;
  for (const release of releases) {
    if (release.draft) {
      continue;
    }
    const version = release.tag_name.replace(/^v/i, "");
    if (newestRelease === null || compareVersions(version, newestRelease.version) > 0) {
      newestRelease = {
        version,
        pageUrl: release.html_url,
        assets: release.assets.map((asset) => ({
          name: asset.name,
          downloadUrl: asset.browser_download_url,
        })),
      };
    }
  }
  return newestRelease;
}

/**
 * The newer release the AI should mention now, or null: none exists, it was mentioned
 * less than a week ago, the check is turned off, or GitHub could not be reached.
 * Never throws; a failed check is simply tried again the next day.
 */
export async function findUpdateToAnnounce(options: UpdateOptions = {}): Promise<Release | null> {
  if (isUpdateCheckDisabled()) {
    return null;
  }
  const now = options.nowMilliseconds ?? Date.now();
  const currentVersion = options.currentVersion ?? PRODUCT_VERSION;
  const record = await readUpdateCheckRecord();
  let newestRelease = record?.newestRelease ?? null;
  const isCheckDue =
    options.ignoreCachedCheck === true ||
    record === null ||
    now - record.checkedAtMilliseconds > CHECK_INTERVAL_MILLISECONDS;
  if (isCheckDue) {
    try {
      newestRelease = await fetchNewestRelease(options.fetcher);
    } catch {
      // Offline, or GitHub refused: keep what we knew.
    }
    await writeUpdateCheckRecord({ ...record, checkedAtMilliseconds: now, newestRelease });
  }
  if (newestRelease === null || compareVersions(newestRelease.version, currentVersion) <= 0) {
    return null;
  }
  const latestRecord = (await readUpdateCheckRecord()) ?? { checkedAtMilliseconds: now, newestRelease };
  const wasAnnouncedRecently =
    latestRecord.announcedVersion === newestRelease.version &&
    now - (latestRecord.announcedAtMilliseconds ?? 0) < REMINDER_INTERVAL_MILLISECONDS;
  if (wasAnnouncedRecently) {
    return null;
  }
  await writeUpdateCheckRecord({
    ...latestRecord,
    announcedVersion: newestRelease.version,
    announcedAtMilliseconds: now,
  });
  return newestRelease;
}

export function describeAvailableUpdate(release: Release, currentVersion: string = PRODUCT_VERSION): string {
  return `Godot Pilot ${release.version} is available (this is ${currentVersion}). Tell the person once and ask whether to install it; if they agree, call update_godot_pilot. What changed: ${release.pageUrl}`;
}

export interface UpdateOutcome {
  updated: boolean;
  message: string;
}

/** Downloads and installs the newest release over the running executable. */
export async function installNewestRelease(
  options: UpdateOptions & { executablePath?: string } = {},
): Promise<UpdateOutcome> {
  const currentVersion = options.currentVersion ?? PRODUCT_VERSION;
  const fetcher = options.fetcher ?? fetch;
  const release = await fetchNewestRelease(fetcher);
  if (release === null || compareVersions(release.version, currentVersion) <= 0) {
    return { updated: false, message: `Godot Pilot ${currentVersion} is the newest version.` };
  }
  const executablePath = options.executablePath ?? process.execPath;
  if (options.executablePath === undefined && !isRunningAsExecutable()) {
    return {
      updated: false,
      message: `Godot Pilot ${release.version} is available, but this copy runs from source code with Bun. Update it with "git pull" and "bun install" in its folder. Release: ${release.pageUrl}`,
    };
  }

  const assetName = getReleaseAssetName();
  const executableAsset = release.assets.find((asset) => asset.name === assetName);
  const checksumsAsset = release.assets.find((asset) => asset.name === CHECKSUMS_ASSET_NAME);
  if (!executableAsset || !checksumsAsset) {
    return {
      updated: false,
      message: `Release ${release.version} has no ${executableAsset ? CHECKSUMS_ASSET_NAME : assetName} file, so it cannot be installed automatically. Download it by hand: ${release.pageUrl}`,
    };
  }

  const expectedChecksum = parseChecksums(await downloadText(checksumsAsset.downloadUrl, fetcher)).get(
    assetName,
  );
  if (!expectedChecksum) {
    return {
      updated: false,
      message: `${CHECKSUMS_ASSET_NAME} of release ${release.version} has no line for ${assetName}.`,
    };
  }
  const newExecutable = await downloadBytes(executableAsset.downloadUrl, fetcher);
  const actualChecksum = createHash("sha256").update(newExecutable).digest("hex");
  if (actualChecksum !== expectedChecksum) {
    return {
      updated: false,
      message: `The downloaded file does not match its checksum, so it was not installed. Try again later or download it by hand: ${release.pageUrl}`,
    };
  }

  const downloadPath = `${executablePath}.download`;
  const previousPath = getPreviousExecutablePath(executablePath);
  await writeFile(downloadPath, newExecutable);
  if (process.platform !== "win32") {
    await chmod(downloadPath, 0o755);
  }
  await rm(previousPath, { force: true });
  await rename(executablePath, previousPath);
  try {
    await rename(downloadPath, executablePath);
  } catch (error) {
    await rename(previousPath, executablePath);
    throw error;
  }
  return {
    updated: true,
    message: [
      `Installed Godot Pilot ${release.version} (was ${currentVersion}).`,
      "It runs from the next start: the person should restart the AI app, or reconnect the godot-pilot MCP server.",
      "After that, launch_editor updates the addon in the project; restart the Godot editor if it is open.",
      `What changed: ${release.pageUrl}`,
    ].join(" "),
  };
}

/** Removes the executable left behind by the last update. Safe to call at every start. */
export async function removePreviousExecutable(executablePath: string = process.execPath): Promise<void> {
  if (isRunningAsExecutable()) {
    await rm(getPreviousExecutablePath(executablePath), { force: true }).catch(() => {});
  }
}

function getPreviousExecutablePath(executablePath: string): string {
  return join(dirname(executablePath), `${basename(executablePath)}.old`);
}

/** "<sha256>  <file name>" lines, as written by sha256sum. */
export function parseChecksums(text: string): Map<string, string> {
  const checksums = new Map<string, string>();
  for (const line of text.split(/\r?\n/)) {
    const match = /^([0-9a-f]{64})\s+\*?(.+)$/i.exec(line.trim());
    if (match?.[1] && match[2]) {
      checksums.set(match[2].trim(), match[1].toLowerCase());
    }
  }
  return checksums;
}

async function downloadText(url: string, fetcher: Fetcher): Promise<string> {
  return new TextDecoder().decode(await downloadBytes(url, fetcher));
}

async function downloadBytes(url: string, fetcher: Fetcher): Promise<Uint8Array> {
  const response = await fetcher(url, { headers: { "User-Agent": PRODUCT_NAME } });
  if (!response.ok) {
    throw new Error(`Download failed (${response.status}): ${url}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

function getUpdateCheckRecordPath(): string {
  return join(getProductHomeDirectory(), "update-check.json");
}

async function readUpdateCheckRecord(): Promise<UpdateCheckRecord | null> {
  try {
    return JSON.parse(await readFile(getUpdateCheckRecordPath(), "utf8")) as UpdateCheckRecord;
  } catch {
    return null;
  }
}

async function writeUpdateCheckRecord(record: UpdateCheckRecord): Promise<void> {
  try {
    await mkdir(getProductHomeDirectory(), { recursive: true });
    await writeFile(getUpdateCheckRecordPath(), JSON.stringify(record));
  } catch {
    // Not being able to remember the check only means checking again next time.
  }
}
