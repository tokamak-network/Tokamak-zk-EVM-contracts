import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

function runCapture(command, args, cwd = process.cwd()) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });

  if (result.status !== 0) {
    throw new Error(
      [
        `Command failed: ${command} ${args.join(" ")}`,
        result.stdout?.trim() ?? "",
        result.stderr?.trim() ?? ""
      ]
        .filter(Boolean)
        .join("\n")
    );
  }

  return result.stdout;
}

function readLatestPackageVersion() {
  const raw = runCapture("npm", ["view", "tokamak-l2js", "version", "--json"]);
  const version = JSON.parse(raw.trim());
  if (typeof version !== "string" || version.length === 0) {
    throw new Error("Failed to resolve the latest tokamak-l2js version.");
  }
  return version;
}

async function installAndReadMtDepth(version, installDir) {
  fs.mkdirSync(installDir, { recursive: true });
  fs.writeFileSync(
    path.join(installDir, "package.json"),
    JSON.stringify(
      {
        name: "bridge-mt-depth-resolver",
        private: true,
        type: "module"
      },
      null,
      2
    ) + "\n"
  );

  runCapture("npm", ["install", "--no-package-lock", "--ignore-scripts", `tokamak-l2js@${version}`], installDir);

  const packageRoot = path.join(installDir, "node_modules", "tokamak-l2js");
  const packageJson = JSON.parse(fs.readFileSync(path.join(packageRoot, "package.json"), "utf8"));
  const moduleUrl = pathToFileURL(path.join(packageRoot, "dist", "index.js")).href;
  const pkg = await import(moduleUrl);
  const mtDepth = pkg.MT_DEPTH;

  if (!Number.isInteger(mtDepth) || mtDepth <= 0) {
    throw new Error(`Invalid MT_DEPTH exported by tokamak-l2js@${packageJson.version}: ${String(mtDepth)}`);
  }

  return { version: packageJson.version, mtDepth };
}

async function main() {
  const latestVersion = readLatestPackageVersion();
  const installDir = fs.mkdtempSync(path.join(os.tmpdir(), "bridge-mt-depth-"));

  try {
    const { version, mtDepth } = await installAndReadMtDepth(latestVersion, installDir);
    process.stdout.write(
      JSON.stringify(
        {
          version,
          mtDepth
        },
        null,
        2
      ) + "\n"
    );
  } finally {
    fs.rmSync(installDir, { recursive: true, force: true });
  }
}

await main();
