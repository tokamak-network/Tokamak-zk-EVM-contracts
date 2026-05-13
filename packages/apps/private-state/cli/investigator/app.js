const textDecoder = new TextDecoder();
const textEncoder = new TextEncoder();

const state = {
  files: new Map(),
  manifest: null,
  notes: [],
  filteredNotes: [],
  selectedNotePaths: new Set(),
};

const els = {
  bundleFile: document.getElementById("bundleFile"),
  filters: document.getElementById("filters"),
  packageForm: document.getElementById("packageForm"),
  applyFilters: document.getElementById("applyFilters"),
  buildPackage: document.getElementById("buildPackage"),
  selectAll: document.getElementById("selectAll"),
  selectNone: document.getElementById("selectNone"),
  status: document.getElementById("status"),
  noteRows: document.getElementById("noteRows"),
};

els.bundleFile.addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (!file) {
    return;
  }
  try {
    setStatus(`Loading ${file.name}...`);
    const bytes = new Uint8Array(await file.arrayBuffer());
    await loadEvidenceBundle(bytes);
    applyFilters();
  } catch (error) {
    resetBundle();
    setStatus(`Failed to load bundle: ${error.message}`);
  }
});

els.applyFilters.addEventListener("click", applyFilters);
els.selectAll.addEventListener("click", () => {
  state.selectedNotePaths = new Set(state.filteredNotes.map((entry) => entry.path));
  renderNotes();
});
els.selectNone.addEventListener("click", () => {
  state.selectedNotePaths.clear();
  renderNotes();
});
els.buildPackage.addEventListener("click", async () => {
  try {
    await buildDisclosurePackage();
  } catch (error) {
    setStatus(`Failed to build disclosure package: ${error.message}`);
  }
});

async function loadEvidenceBundle(bytes) {
  const files = await readZip(bytes);
  const manifest = readJsonFile(files, "manifest.json");
  if (manifest.format !== "tokamak-private-state-raw-evidence-bundle") {
    throw new Error(`Unsupported evidence format: ${manifest.format ?? "missing"}.`);
  }
  if (Number(manifest.formatVersion) !== 2) {
    throw new Error("Current evidence bundle formatVersion 2 is required. Run wallet recover-workspace, then run wallet get-notes --export-evidence again.");
  }
  const notes = [...files.entries()]
    .filter(([path]) => isEvidenceNotePath(path))
    .map(([path, content]) => ({
      path,
      record: JSON.parse(content),
    }))
    .sort((left, right) =>
      String(left.record?.derived?.commitment ?? "").localeCompare(String(right.record?.derived?.commitment ?? "")));
  if (notes.length === 0) {
    throw new Error("The evidence bundle does not contain current epoch-aware note records.");
  }
  state.files = files;
  state.manifest = manifest;
  state.notes = notes;
  state.filteredNotes = notes;
  state.selectedNotePaths = new Set(notes.map((entry) => entry.path));
  els.buildPackage.disabled = false;
  els.selectAll.disabled = false;
  els.selectNone.disabled = false;
  setStatus(
    `Loaded ${notes.length} note records from ${evidenceWalletLabel(manifest)} on ${manifest.network ?? "network"}.`,
  );
}

function isEvidenceNotePath(entryPath) {
  return /^wallets\/[^/]+\/epochs\/[^/]+\/notes\/[^/]+\.json$/u.test(entryPath);
}

function evidenceWalletLabel(manifest) {
  if (manifest.wallets?.length) {
    return `${manifest.wallets[0].wallet ?? manifest.wallet ?? "wallet"} (${manifest.wallets.length} epochs)`;
  }
  return manifest.wallet ?? "wallet";
}

function resetBundle() {
  state.files = new Map();
  state.manifest = null;
  state.notes = [];
  state.filteredNotes = [];
  state.selectedNotePaths.clear();
  els.buildPackage.disabled = true;
  els.selectAll.disabled = true;
  els.selectNone.disabled = true;
  els.noteRows.textContent = "";
}

function applyFilters() {
  if (!state.manifest) {
    setStatus("Load a raw evidence ZIP to begin.");
    return;
  }
  const form = new FormData(els.filters);
  const criteria = getFilterCriteria(form);
  state.filteredNotes = state.notes.filter(({ record }) => matchesCriteria(record, criteria));
  state.selectedNotePaths = new Set(state.filteredNotes.map((entry) => entry.path));
  renderNotes();
  setStatus(`${state.filteredNotes.length} of ${state.notes.length} notes match the current filter.`);
}

function getFilterCriteria(form) {
  return {
    commitment: normalizeSearch(form.get("commitment")),
    nullifier: normalizeSearch(form.get("nullifier")),
    creationTx: normalizeSearch(form.get("creationTx")),
    spendTx: normalizeSearch(form.get("spendTx")),
    createdFrom: parseOptionalNumber(form.get("createdFrom")),
    createdTo: parseOptionalNumber(form.get("createdTo")),
    spentFrom: parseOptionalNumber(form.get("spentFrom")),
    spentTo: parseOptionalNumber(form.get("spentTo")),
    status: String(form.get("status") ?? ""),
    direction: String(form.get("direction") ?? ""),
    counterparty: normalizeSearch(form.get("counterparty")),
  };
}

function matchesCriteria(record, criteria) {
  if (criteria.commitment && !contains(record.derived?.commitment, criteria.commitment)) return false;
  if (criteria.nullifier && !contains(record.derived?.nullifier, criteria.nullifier)) return false;
  if (criteria.creationTx && !contains(record.creation?.txHash, criteria.creationTx)) return false;
  if (criteria.spendTx && !contains(record.spend?.txHash, criteria.spendTx)) return false;
  if (criteria.status && record.spend?.status !== criteria.status) return false;
  if (criteria.direction && record.relationshipHints?.direction !== criteria.direction) return false;
  if (criteria.counterparty && !contains(record.relationshipHints?.counterpartyL2Address, criteria.counterparty)) return false;
  if (!inRange(record.creation?.blockNumber, criteria.createdFrom, criteria.createdTo)) return false;
  if (!inRange(record.spend?.blockNumber, criteria.spentFrom, criteria.spentTo)) return false;
  return true;
}

function renderNotes() {
  els.noteRows.textContent = "";
  const fragment = document.createDocumentFragment();
  for (const { path, record } of state.filteredNotes) {
    const row = document.createElement("tr");
    row.append(
      cellWithCheckbox(path),
      monoCell(shortHex(record.derived?.commitment)),
      textCell(record.plaintext?.value ?? ""),
      textCell(record.spend?.status ?? ""),
      monoCell(formatEventRef(record.creation)),
      monoCell(formatEventRef(record.spend)),
      textCell(record.relationshipHints?.direction ?? "unknown"),
      monoCell(shortHex(record.relationshipHints?.counterpartyL2Address)),
    );
    fragment.append(row);
  }
  els.noteRows.append(fragment);
}

function cellWithCheckbox(path) {
  const cell = document.createElement("td");
  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  checkbox.checked = state.selectedNotePaths.has(path);
  checkbox.addEventListener("change", () => {
    if (checkbox.checked) {
      state.selectedNotePaths.add(path);
    } else {
      state.selectedNotePaths.delete(path);
    }
  });
  cell.append(checkbox);
  return cell;
}

function textCell(value) {
  const cell = document.createElement("td");
  cell.textContent = value === null || value === undefined || value === "" ? "-" : String(value);
  return cell;
}

function monoCell(value) {
  const cell = textCell(value);
  cell.className = "mono";
  return cell;
}

async function buildDisclosurePackage() {
  if (!state.manifest) {
    throw new Error("Load an evidence bundle first.");
  }
  const selectedNotes = state.notes.filter((entry) => state.selectedNotePaths.has(entry.path));
  if (selectedNotes.length === 0) {
    throw new Error("Select at least one note.");
  }
  const packageMetadata = readPackageMetadata();
  const criteria = getFilterCriteria(new FormData(els.filters));
  const selectedPaths = collectSelectedPaths(selectedNotes);
  const files = new Map();
  const manifest = buildDisclosureManifest({
    selectedNotes,
    selectedPaths,
    packageMetadata,
    criteria,
  });

  files.set("manifest.json", jsonString(manifest));
  files.set("indexes/by-commitment.json", jsonString(buildDisclosureIndex(selectedNotes, "commitment")));
  files.set("indexes/by-nullifier.json", jsonString(buildDisclosureIndex(selectedNotes, "nullifier")));
  files.set("indexes/by-creation-tx.json", jsonString(buildDisclosureTxIndex(selectedNotes, "creation")));
  files.set("indexes/by-spend-tx.json", jsonString(buildDisclosureTxIndex(selectedNotes, "spend")));
  files.set("indexes/by-block-range.json", jsonString(buildDisclosureBlockIndex(selectedNotes)));
  files.set("indexes/by-counterparty.json", jsonString(buildDisclosureCounterpartyIndex(selectedNotes)));
  files.set("verification-guide.md", buildVerificationGuide());
  if (packageMetadata.statement) {
    files.set("user-statement.txt", `${packageMetadata.statement}\n`);
  }
  for (const path of selectedPaths) {
    const content = state.files.get(path);
    if (content !== undefined) {
      files.set(path, content.endsWith("\n") ? content : `${content}\n`);
    }
  }

  const zipBytes = createZip(files);
  const blob = new Blob([zipBytes], { type: "application/zip" });
  const fileName = disclosureFileName(packageMetadata, state.manifest);
  downloadBlob(blob, fileName);
  setStatus(`Built ${fileName} with ${selectedNotes.length} selected notes and ${files.size} files.`);
}

function readPackageMetadata() {
  const form = new FormData(els.packageForm);
  return {
    caseId: String(form.get("caseId") ?? "").trim(),
    requestingParty: String(form.get("requestingParty") ?? "").trim(),
    bridgeDepositTx: normalizeSearch(form.get("bridgeDepositTx")),
    withdrawTx: normalizeSearch(form.get("withdrawTx")),
    statement: String(form.get("statement") ?? "").trim(),
    intents: form.getAll("intent").map((value) => String(value)),
  };
}

function collectSelectedPaths(selectedNotes) {
  const paths = new Set();
  for (const { path, record } of selectedNotes) {
    paths.add(path);
    addTransitionPaths(paths, record.creation?.acceptedTransition);
    addTransitionPaths(paths, record.spend?.acceptedTransition);
  }
  return [...paths].sort();
}

function buildDisclosureIndex(selectedNotes, key) {
  const result = {};
  for (const { path, record } of selectedNotes) {
    const value = key === "commitment" ? record.derived?.commitment : record.derived?.nullifier;
    if (value) {
      result[value] = path;
    }
  }
  return result;
}

function buildDisclosureTxIndex(selectedNotes, section) {
  const result = {};
  for (const { path, record } of selectedNotes) {
    const txHash = record[section]?.txHash;
    if (!txHash) {
      continue;
    }
    if (!result[txHash]) {
      result[txHash] = [];
    }
    result[txHash].push(path);
  }
  return result;
}

function buildDisclosureBlockIndex(selectedNotes) {
  return selectedNotes.map(({ path, record }) => ({
    commitment: record.derived?.commitment ?? null,
    createdAtBlockNumber: record.creation?.blockNumber ?? null,
    spentAtBlockNumber: record.spend?.blockNumber ?? null,
    path,
  }));
}

function buildDisclosureCounterpartyIndex(selectedNotes) {
  const result = { unavailable: [] };
  for (const { path, record } of selectedNotes) {
    const counterparty = record.relationshipHints?.counterpartyL2Address;
    if (!counterparty) {
      result.unavailable.push(path);
      continue;
    }
    if (!result[counterparty]) {
      result[counterparty] = { sent: [], received: [], both: [] };
    }
    const direction = record.relationshipHints?.direction === "received" ? "received" : "sent";
    result[counterparty][direction].push(path);
    result[counterparty].both.push(path);
  }
  return result;
}

function addTransitionPaths(paths, transition) {
  for (const key of ["transactionPath", "receiptPath", "eventsPath"]) {
    if (transition?.[key]) {
      paths.add(transition[key]);
    }
  }
}

function buildDisclosureManifest({ selectedNotes, selectedPaths, packageMetadata, criteria }) {
  return {
    format: "tokamak-private-state-consent-disclosure-package",
    formatVersion: 1,
    generatedAt: new Date().toISOString(),
    sourceBundle: {
      format: state.manifest.format,
      formatVersion: state.manifest.formatVersion,
      network: state.manifest.network,
      chainId: state.manifest.chainId,
      channelName: state.manifest.channelName,
      channelId: state.manifest.channelId,
      wallet: state.manifest.wallet,
      wallets: state.manifest.wallets ?? null,
      walletL1Address: state.manifest.walletL1Address,
      walletL2Address: state.manifest.walletL2Address,
    },
    case: {
      caseId: packageMetadata.caseId || null,
      requestingParty: packageMetadata.requestingParty || null,
      bridgeDepositTx: packageMetadata.bridgeDepositTx || null,
      withdrawTx: packageMetadata.withdrawTx || null,
      disclosureIntents: packageMetadata.intents,
    },
    filterCriteria: criteria,
    disclosureScope: {
      selectedNoteCount: selectedNotes.length,
      selectedCommitments: selectedNotes.map(({ record }) => record.derived?.commitment).filter(Boolean),
      selectedNullifiers: selectedNotes.map(({ record }) => record.derived?.nullifier).filter(Boolean),
      includedPaths: selectedPaths,
      includesFullRawBundle: false,
      includesOnlySelectedNotes: true,
    },
    includedSecrets: {
      spendingKey: false,
      viewingKey: false,
      walletSecret: false,
      accountPrivateKey: false,
      keyFiles: false,
    },
    warnings: [
      "Selected note plaintext is included for the disclosed notes.",
      "This package is not a keyless cryptographic decryption proof.",
      "Counterparty filtering is only as complete as the relationship hints present in the raw evidence bundle.",
    ],
  };
}

function buildVerificationGuide() {
  return [
    "# Verification Guide",
    "",
    "This ZIP is a user-consent disclosure package derived from a local raw evidence bundle.",
    "",
    "A reviewer can:",
    "",
    "1. Recompute each note commitment from `plaintext.owner`, `plaintext.value`, and `plaintext.salt`.",
    "2. Recompute each note nullifier from the same plaintext fields.",
    "3. Compare creation and spend transaction references against included transaction, receipt, and event files.",
    "4. Confirm that the package manifest excludes viewing keys, spending keys, wallet secrets, account private keys, and `.key` files.",
    "5. Treat bridge deposit, withdraw, and counterparty fields as user-scoped disclosure context, not as an operator-reconstructed private note graph.",
    "",
  ].join("\n");
}

async function readZip(bytes) {
  const entries = parseZipEntries(bytes);
  const files = new Map();
  for (const entry of entries) {
    if (entry.isDirectory) {
      continue;
    }
    const data = await inflateZipEntry(bytes, entry);
    files.set(entry.name, textDecoder.decode(data));
  }
  return files;
}

function parseZipEntries(bytes) {
  const eocdOffset = findEndOfCentralDirectory(bytes);
  const entryCount = readUint16(bytes, eocdOffset + 10);
  const centralDirectoryOffset = readUint32(bytes, eocdOffset + 16);
  const entries = [];
  let offset = centralDirectoryOffset;
  for (let index = 0; index < entryCount; index += 1) {
    if (readUint32(bytes, offset) !== 0x02014b50) {
      throw new Error("Invalid ZIP central directory.");
    }
    const method = readUint16(bytes, offset + 10);
    const compressedSize = readUint32(bytes, offset + 20);
    const uncompressedSize = readUint32(bytes, offset + 24);
    const nameLength = readUint16(bytes, offset + 28);
    const extraLength = readUint16(bytes, offset + 30);
    const commentLength = readUint16(bytes, offset + 32);
    const localHeaderOffset = readUint32(bytes, offset + 42);
    const name = textDecoder.decode(bytes.slice(offset + 46, offset + 46 + nameLength));
    entries.push({
      name,
      method,
      compressedSize,
      uncompressedSize,
      localHeaderOffset,
      isDirectory: name.endsWith("/"),
    });
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

function findEndOfCentralDirectory(bytes) {
  const minimum = Math.max(0, bytes.length - 65557);
  for (let offset = bytes.length - 22; offset >= minimum; offset -= 1) {
    if (readUint32(bytes, offset) === 0x06054b50) {
      return offset;
    }
  }
  throw new Error("ZIP end-of-central-directory record not found.");
}

async function inflateZipEntry(bytes, entry) {
  const offset = entry.localHeaderOffset;
  if (readUint32(bytes, offset) !== 0x04034b50) {
    throw new Error(`Invalid local ZIP header for ${entry.name}.`);
  }
  const nameLength = readUint16(bytes, offset + 26);
  const extraLength = readUint16(bytes, offset + 28);
  const dataStart = offset + 30 + nameLength + extraLength;
  const compressed = bytes.slice(dataStart, dataStart + entry.compressedSize);
  if (entry.method === 0) {
    return compressed;
  }
  if (entry.method !== 8) {
    throw new Error(`Unsupported ZIP compression method ${entry.method} for ${entry.name}.`);
  }
  if (!("DecompressionStream" in window)) {
    throw new Error("This browser cannot decompress ZIP deflate entries.");
  }
  const stream = new Blob([compressed]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function createZip(files) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;
  for (const [name, content] of files.entries()) {
    const nameBytes = textEncoder.encode(name);
    const data = typeof content === "string" ? textEncoder.encode(content) : content;
    const crc = crc32(data);
    const { time, date } = dosTimeDate(new Date());
    const localHeader = new Uint8Array(30 + nameBytes.length);
    writeUint32(localHeader, 0, 0x04034b50);
    writeUint16(localHeader, 4, 20);
    writeUint16(localHeader, 8, 0);
    writeUint16(localHeader, 10, time);
    writeUint16(localHeader, 12, date);
    writeUint32(localHeader, 14, crc);
    writeUint32(localHeader, 18, data.length);
    writeUint32(localHeader, 22, data.length);
    writeUint16(localHeader, 26, nameBytes.length);
    localHeader.set(nameBytes, 30);
    localParts.push(localHeader, data);

    const centralHeader = new Uint8Array(46 + nameBytes.length);
    writeUint32(centralHeader, 0, 0x02014b50);
    writeUint16(centralHeader, 4, 20);
    writeUint16(centralHeader, 6, 20);
    writeUint16(centralHeader, 10, 0);
    writeUint16(centralHeader, 12, time);
    writeUint16(centralHeader, 14, date);
    writeUint32(centralHeader, 16, crc);
    writeUint32(centralHeader, 20, data.length);
    writeUint32(centralHeader, 24, data.length);
    writeUint16(centralHeader, 28, nameBytes.length);
    writeUint32(centralHeader, 42, offset);
    centralHeader.set(nameBytes, 46);
    centralParts.push(centralHeader);
    offset += localHeader.length + data.length;
  }

  const centralOffset = offset;
  const centralSize = centralParts.reduce((sum, part) => sum + part.length, 0);
  const end = new Uint8Array(22);
  writeUint32(end, 0, 0x06054b50);
  writeUint16(end, 8, files.size);
  writeUint16(end, 10, files.size);
  writeUint32(end, 12, centralSize);
  writeUint32(end, 16, centralOffset);
  return concatBytes([...localParts, ...centralParts, end]);
}

function readJsonFile(files, path) {
  const content = files.get(path);
  if (!content) {
    throw new Error(`Missing ${path}.`);
  }
  return JSON.parse(content);
}

function readUint16(bytes, offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function readUint32(bytes, offset) {
  return (
    bytes[offset]
    | (bytes[offset + 1] << 8)
    | (bytes[offset + 2] << 16)
    | (bytes[offset + 3] << 24)
  ) >>> 0;
}

function writeUint16(bytes, offset, value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >>> 8) & 0xff;
}

function writeUint32(bytes, offset, value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >>> 8) & 0xff;
  bytes[offset + 2] = (value >>> 16) & 0xff;
  bytes[offset + 3] = (value >>> 24) & 0xff;
}

function concatBytes(parts) {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value = crcTable[(value ^ byte) & 0xff] ^ (value >>> 8);
  }
  return (value ^ 0xffffffff) >>> 0;
}

const crcTable = (() => {
  const table = [];
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value & 1) ? (0xedb88320 ^ (value >>> 1)) : (value >>> 1);
    }
    table[index] = value >>> 0;
  }
  return table;
})();

function dosTimeDate(date) {
  const time =
    (date.getHours() << 11)
    | (date.getMinutes() << 5)
    | Math.floor(date.getSeconds() / 2);
  const year = Math.max(1980, date.getFullYear());
  const dosDate =
    ((year - 1980) << 9)
    | ((date.getMonth() + 1) << 5)
    | date.getDate();
  return { time, date: dosDate };
}

function parseOptionalNumber(value) {
  const text = String(value ?? "").trim();
  if (!text) {
    return null;
  }
  const number = Number(text);
  if (!Number.isSafeInteger(number) || number < 0) {
    return null;
  }
  return number;
}

function inRange(value, from, to) {
  if (from === null && to === null) {
    return true;
  }
  if (value === null || value === undefined) {
    return false;
  }
  const number = Number(value);
  if (from !== null && number < from) return false;
  if (to !== null && number > to) return false;
  return true;
}

function normalizeSearch(value) {
  return String(value ?? "").trim().toLowerCase();
}

function contains(value, needle) {
  return String(value ?? "").toLowerCase().includes(needle);
}

function shortHex(value) {
  const text = String(value ?? "");
  if (!text) {
    return "-";
  }
  return text.length > 18 ? `${text.slice(0, 10)}...${text.slice(-8)}` : text;
}

function formatEventRef(value) {
  if (!value?.txHash) {
    return "-";
  }
  const block = value.blockNumber === null || value.blockNumber === undefined ? "?" : value.blockNumber;
  return `${shortHex(value.txHash)} @ ${block}`;
}

function jsonString(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function disclosureFileName(metadata, manifest) {
  const rawName = [
    metadata.caseId || "consent-disclosure",
    manifest.network,
    manifest.channelName,
    new Date().toISOString().replace(/[:.]/g, "-"),
  ].filter(Boolean).join("-");
  return `${rawName.replace(/[^A-Za-z0-9_.-]+/g, "-")}.zip`;
}

function downloadBlob(blob, fileName) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  document.body.append(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function setStatus(message) {
  els.status.textContent = message;
}
