import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

export const PRIVATE_STATE_TERMS_VERSION = "2026-06-10";
export const PRIVATE_STATE_TERMS_HASH_ALGORITHM = "sha256";
export const PRIVATE_STATE_TERMS_PACKAGE_PATH = "assets/service-terms.md";
export const PRIVATE_STATE_TERMS_PUBLIC_PATH = "docs/dapps/private-state/terms.md";

const privateStateCliPackageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const privateStateTermsAssetPath = path.join(privateStateCliPackageRoot, PRIVATE_STATE_TERMS_PACKAGE_PATH);

export function readPrivateStateTermsText() {
  return fs.readFileSync(privateStateTermsAssetPath, "utf8");
}

export function computePrivateStateTermsHash(termsText = readPrivateStateTermsText()) {
  return `${PRIVATE_STATE_TERMS_HASH_ALGORITHM}:${createHash(PRIVATE_STATE_TERMS_HASH_ALGORITHM)
    .update(termsText, "utf8")
    .digest("hex")}`;
}

export function readPrivateStateTermsMetadata() {
  const termsText = readPrivateStateTermsText();
  return {
    termsVersion: PRIVATE_STATE_TERMS_VERSION,
    termsHash: computePrivateStateTermsHash(termsText),
    termsHashAlgorithm: PRIVATE_STATE_TERMS_HASH_ALGORITHM,
    termsPackagePath: PRIVATE_STATE_TERMS_PACKAGE_PATH,
    termsPublicPath: PRIVATE_STATE_TERMS_PUBLIC_PATH,
    termsHashInput: "exact UTF-8 bytes of the packaged Service Terms Markdown",
    termsContentBytes: Buffer.byteLength(termsText, "utf8"),
  };
}
