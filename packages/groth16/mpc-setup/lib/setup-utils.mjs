import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import https from "node:https";
import path from "node:path";
import { URL, URLSearchParams } from "node:url";

export function createCommandRunner({ groth16Root, localSnarkJsBinary }) {
    const resolvedCommands = new Map();

    function resolveCommand(command) {
        if (resolvedCommands.has(command)) {
            return resolvedCommands.get(command);
        }

        const directCandidates = [];
        if (command === "node" && process.execPath) {
            directCandidates.push(process.execPath);
        }
        if (command === "snarkjs") {
            if (localSnarkJsBinary) {
                directCandidates.push(localSnarkJsBinary);
            }
            directCandidates.push(path.join(groth16Root, "node_modules", ".bin", "snarkjs"));
        }

        const pathEntries = (process.env.PATH ?? "").split(path.delimiter).filter(Boolean);
        const candidates = [
            ...directCandidates,
            ...pathEntries.map((entry) => path.join(entry, command))
        ];

        for (const candidate of candidates) {
            if (fs.existsSync(candidate)) {
                resolvedCommands.set(command, candidate);
                return candidate;
            }
        }

        resolvedCommands.set(command, command);
        return command;
    }

    function runCapture(command, args, options = {}) {
        if (command === "snarkjs") {
            return execFileSync(resolveCommand("node"), [resolveCommand("snarkjs"), ...args], {
                cwd: groth16Root,
                encoding: "utf8",
                stdio: ["ignore", "pipe", "pipe"],
                ...options
            });
        }

        return execFileSync(resolveCommand(command), args, {
            cwd: groth16Root,
            encoding: "utf8",
            stdio: ["ignore", "pipe", "pipe"],
            ...options
        });
    }

    function run(command, args, options = {}) {
        if (command === "snarkjs") {
            execFileSync(resolveCommand("node"), [resolveCommand("snarkjs"), ...args], {
                cwd: groth16Root,
                stdio: "inherit",
                ...options
            });
            return;
        }

        execFileSync(resolveCommand(command), args, {
            cwd: groth16Root,
            stdio: "inherit",
            ...options
        });
    }

    return {
        resolveCommand,
        run,
        runCapture
    };
}

export function ensureTools({ tools, resolveCommand, runCapture }) {
    for (const tool of tools) {
        const resolved = resolveCommand(tool.command);
        if (!fs.existsSync(resolved)) {
            throw new Error(`Missing required tool: ${tool.name}`);
        }

        try {
            runCapture(tool.command, tool.args);
        } catch (error) {
            if (tool.allowNonZeroExit) {
                continue;
            }
            throw new Error(`Missing required tool: ${tool.name}`);
        }
    }
}

export function hashFile(filePath, algorithm) {
    return new Promise((resolve, reject) => {
        const hasher = crypto.createHash(algorithm);
        const stream = fs.createReadStream(filePath);
        stream.on("data", (chunk) => hasher.update(chunk));
        stream.on("end", () => resolve(hasher.digest("hex")));
        stream.on("error", reject);
    });
}

export function fetchText(url) {
    return new Promise((resolve, reject) => {
        const request = https.get(url, { headers: { "user-agent": "Mozilla/5.0" } }, (response) => {
            if (
                response.statusCode &&
                response.statusCode >= 300 &&
                response.statusCode < 400 &&
                response.headers.location
            ) {
                response.resume();
                const redirectedUrl = new URL(response.headers.location, url).toString();
                fetchText(redirectedUrl).then(resolve, reject);
                return;
            }

            if (response.statusCode !== 200) {
                response.resume();
                reject(new Error(`Failed to download ${url}: HTTP ${response.statusCode ?? "unknown"}`));
                return;
            }

            const chunks = [];
            response.on("data", (chunk) => chunks.push(chunk));
            response.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
            response.on("error", reject);
        });

        request.on("error", reject);
    });
}

export function downloadFile(url, destinationPath) {
    const tmpDestinationPath = `${destinationPath}.download`;
    fs.rmSync(tmpDestinationPath, { force: true });
    return downloadFileInternal(url, destinationPath, tmpDestinationPath);
}

function downloadFileInternal(url, destinationPath, tmpDestinationPath) {
    return new Promise((resolve, reject) => {
        const request = https.get(url, { headers: { "user-agent": "Mozilla/5.0" } }, (response) => {
            if (
                response.statusCode &&
                response.statusCode >= 300 &&
                response.statusCode < 400 &&
                response.headers.location
            ) {
                response.resume();
                const redirectedUrl = new URL(response.headers.location, url).toString();
                downloadFileInternal(redirectedUrl, destinationPath, tmpDestinationPath).then(resolve, reject);
                return;
            }

            if (response.statusCode !== 200) {
                response.resume();
                reject(new Error(`Failed to download ${url}: HTTP ${response.statusCode ?? "unknown"}`));
                return;
            }

            const contentType = String(response.headers["content-type"] ?? "").toLowerCase();
            if (contentType.includes("text/html")) {
                const chunks = [];
                response.on("data", (chunk) => chunks.push(chunk));
                response.on("end", () => {
                    try {
                        const html = Buffer.concat(chunks).toString("utf8");
                        const confirmedUrl = extractGoogleDriveConfirmedDownloadUrl(url, html);
                        if (!confirmedUrl) {
                            reject(new Error(`Failed to resolve Google Drive confirmed download URL for ${url}`));
                            return;
                        }
                        downloadFileInternal(confirmedUrl, destinationPath, tmpDestinationPath).then(resolve, reject);
                    } catch (error) {
                        reject(error);
                    }
                });
                response.on("error", reject);
                return;
            }

            const file = fs.createWriteStream(tmpDestinationPath);
            file.on("error", (error) => {
                response.destroy(error);
            });
            response.on("error", (error) => {
                file.destroy(error);
            });
            file.on("finish", () => {
                file.close(() => {
                    fs.renameSync(tmpDestinationPath, destinationPath);
                    resolve();
                });
            });
            response.pipe(file);
        });

        request.on("error", (error) => {
            fs.rmSync(tmpDestinationPath, { force: true });
            reject(error);
        });
    });
}

function extractGoogleDriveConfirmedDownloadUrl(sourceUrl, html) {
    const formMatch = html.match(/<form[^>]*id="download-form"[^>]*action="([^"]+)"/i);
    if (!formMatch) {
        return null;
    }

    const actionUrl = new URL(formMatch[1], sourceUrl);
    const params = new URLSearchParams();
    const inputPattern = /<input[^>]*type="hidden"[^>]*name="([^"]+)"[^>]*value="([^"]*)"/gi;
    let match;
    while ((match = inputPattern.exec(html)) !== null) {
        params.set(match[1], match[2]);
    }
    actionUrl.search = params.toString();
    return actionUrl.toString();
}
