/**
 * Tests of the update check and installer (server/src/updates/updates.ts), with a fake
 * GitHub so nothing goes over the internet.
 */
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { HOME_OVERRIDE_ENVIRONMENT_VARIABLE } from "../../server/src/product.ts";
import {
  compareVersions,
  type Fetcher,
  fetchNewestRelease,
  findUpdateToAnnounce,
  getReleaseAssetName,
  installNewestRelease,
  NO_UPDATE_CHECK_ENVIRONMENT_VARIABLE,
  parseChecksums,
} from "../../server/src/updates/updates.ts";

const NEW_EXECUTABLE = new TextEncoder().encode("the new version");
const ASSET_NAME = getReleaseAssetName();

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/** A fake GitHub with releases 0.1.0 and 0.3.0 (newest), plus a draft 9.0.0. */
function fakeGitHub(options: { checksum?: string } = {}) {
  const requestedUrls: string[] = [];
  const fetcher: Fetcher = async (url) => {
    requestedUrls.push(url);
    if (url.includes("api.github.com")) {
      return Response.json([
        { tag_name: "v9.0.0", html_url: "https://example.test/draft", draft: true, assets: [] },
        {
          tag_name: "v0.3.0",
          html_url: "https://example.test/v0.3.0",
          draft: false,
          assets: [
            { name: ASSET_NAME, browser_download_url: "https://example.test/download/executable" },
            { name: "SHA256SUMS", browser_download_url: "https://example.test/download/sums" },
          ],
        },
        { tag_name: "v0.1.0", html_url: "https://example.test/v0.1.0", draft: false, assets: [] },
      ]);
    }
    if (url.endsWith("/sums")) {
      return new Response(`${options.checksum ?? sha256(NEW_EXECUTABLE)}  ${ASSET_NAME}\n`);
    }
    if (url.endsWith("/executable")) {
      return new Response(NEW_EXECUTABLE);
    }
    return new Response("not found", { status: 404 });
  };
  return { fetcher, requestedUrls };
}

let temporaryDirectory = "";

beforeEach(async () => {
  temporaryDirectory = await mkdtemp(join(tmpdir(), "godot-pilot-updates-"));
  process.env[HOME_OVERRIDE_ENVIRONMENT_VARIABLE] = temporaryDirectory;
  delete process.env[NO_UPDATE_CHECK_ENVIRONMENT_VARIABLE];
});

afterEach(async () => {
  await rm(temporaryDirectory, { recursive: true, force: true });
});

describe("compareVersions", () => {
  test("orders versions by their numbers, not as text", () => {
    expect(compareVersions("0.10.0", "0.9.0")).toBeGreaterThan(0);
    expect(compareVersions("v0.2.0", "0.2.0")).toBe(0);
    expect(compareVersions("0.2.0", "0.2.1")).toBeLessThan(0);
  });

  test("a version with a suffix comes before the plain version", () => {
    expect(compareVersions("1.0.0-beta.2", "1.0.0")).toBeLessThan(0);
    expect(compareVersions("1.0.0-beta.10", "1.0.0-beta.2")).toBeGreaterThan(0);
  });
});

test("parseChecksums reads sha256sum output", () => {
  const checksum = "a".repeat(64);
  const checksums = parseChecksums(`${checksum}  godot-pilot-linux-x64\n${checksum} *other.zip\n`);
  expect(checksums.get("godot-pilot-linux-x64")).toBe(checksum);
  expect(checksums.get("other.zip")).toBe(checksum);
});

test("the newest release leaves drafts out", async () => {
  const release = await fetchNewestRelease(fakeGitHub().fetcher);
  expect(release?.version).toBe("0.3.0");
});

describe("telling the AI about a new version", () => {
  test("a newer release is announced once, then not again for a week", async () => {
    const github = fakeGitHub();
    const now = Date.now();
    const first = await findUpdateToAnnounce({
      fetcher: github.fetcher,
      currentVersion: "0.1.0",
      nowMilliseconds: now,
    });
    expect(first?.version).toBe("0.3.0");

    const nextDay = now + 25 * 60 * 60 * 1000;
    const second = await findUpdateToAnnounce({
      fetcher: github.fetcher,
      currentVersion: "0.1.0",
      nowMilliseconds: nextDay,
    });
    expect(second).toBeNull();

    const nextWeek = now + 8 * 24 * 60 * 60 * 1000;
    const third = await findUpdateToAnnounce({
      fetcher: github.fetcher,
      currentVersion: "0.1.0",
      nowMilliseconds: nextWeek,
    });
    expect(third?.version).toBe("0.3.0");
  });

  test("GitHub is asked at most once a day", async () => {
    const github = fakeGitHub();
    const now = Date.now();
    await findUpdateToAnnounce({ fetcher: github.fetcher, currentVersion: "0.3.0", nowMilliseconds: now });
    await findUpdateToAnnounce({
      fetcher: github.fetcher,
      currentVersion: "0.3.0",
      nowMilliseconds: now + 60_000,
    });
    expect(github.requestedUrls.length).toBe(1);
  });

  test("nothing is announced when this is the newest version", async () => {
    const release = await findUpdateToAnnounce({ fetcher: fakeGitHub().fetcher, currentVersion: "0.3.0" });
    expect(release).toBeNull();
  });

  test("the check can be turned off", async () => {
    process.env[NO_UPDATE_CHECK_ENVIRONMENT_VARIABLE] = "1";
    const github = fakeGitHub();
    const release = await findUpdateToAnnounce({ fetcher: github.fetcher, currentVersion: "0.1.0" });
    expect(release).toBeNull();
    expect(github.requestedUrls.length).toBe(0);
  });

  test("being offline is not an error", async () => {
    const offline: Fetcher = async () => {
      throw new Error("network is down");
    };
    expect(await findUpdateToAnnounce({ fetcher: offline, currentVersion: "0.1.0" })).toBeNull();
  });
});

describe("installing the newest release", () => {
  test("downloads, checks the checksum and swaps the executable", async () => {
    const executablePath = join(temporaryDirectory, ASSET_NAME);
    await writeFile(executablePath, "the old version");
    const outcome = await installNewestRelease({
      fetcher: fakeGitHub().fetcher,
      currentVersion: "0.1.0",
      executablePath,
    });
    expect(outcome.updated).toBe(true);
    expect(outcome.message).toContain("Installed Godot Pilot 0.3.0");
    expect(await readFile(executablePath, "utf8")).toBe("the new version");
    // The old file is kept next to it until the next start.
    expect(await readFile(`${executablePath}.old`, "utf8")).toBe("the old version");
  });

  test("a download that does not match its checksum is not installed", async () => {
    const executablePath = join(temporaryDirectory, ASSET_NAME);
    await writeFile(executablePath, "the old version");
    const outcome = await installNewestRelease({
      fetcher: fakeGitHub({ checksum: "0".repeat(64) }).fetcher,
      currentVersion: "0.1.0",
      executablePath,
    });
    expect(outcome.updated).toBe(false);
    expect(outcome.message).toContain("does not match its checksum");
    expect(await readFile(executablePath, "utf8")).toBe("the old version");
  });

  test("nothing happens when this is already the newest version", async () => {
    const outcome = await installNewestRelease({ fetcher: fakeGitHub().fetcher, currentVersion: "0.3.0" });
    expect(outcome.updated).toBe(false);
    expect(outcome.message).toContain("is the newest version");
  });
});
