const textDecoder = new TextDecoder();
const textEncoder = new TextEncoder();

const state = {
  files: new Map(),
  manifest: null,
  notes: [],
  filteredNotes: [],
  selectedNotePaths: new Set(),
  graph: { nodes: [], edges: [] },
  activeTab: "graph",
};

const els = {
  bundleFile: document.getElementById("bundleFile"),
  summaryCards: document.getElementById("summaryCards"),
  filters: document.getElementById("filters"),
  packageForm: document.getElementById("packageForm"),
  applyFilters: document.getElementById("applyFilters"),
  buildPackage: document.getElementById("buildPackage"),
  exportAscii: document.getElementById("exportAscii"),
  selectAll: document.getElementById("selectAll"),
  selectNone: document.getElementById("selectNone"),
  status: document.getElementById("status"),
  noteRows: document.getElementById("noteRows"),
  graphSvg: document.getElementById("graphSvg"),
  graphViewport: document.getElementById("graphViewport"),
  nodeDetail: document.getElementById("nodeDetail"),
  graphPanel: document.getElementById("graphPanel"),
  notesPanel: document.getElementById("notesPanel"),
  graphTab: document.getElementById("graphTab"),
  notesTab: document.getElementById("notesTab"),
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
els.filters.addEventListener("change", (event) => {
  if (event.target?.name === "purpose") {
    updatePurposeFields();
    applyFilters();
  }
});
els.selectAll.addEventListener("click", () => {
  state.selectedNotePaths = new Set(state.filteredNotes.map((entry) => entry.path));
  renderResults();
});
els.selectNone.addEventListener("click", () => {
  state.selectedNotePaths.clear();
  renderResults();
});
els.buildPackage.addEventListener("click", async () => {
  try {
    await buildDisclosurePackage();
  } catch (error) {
    setStatus(`Failed to build disclosure package: ${error.message}`);
  }
});
els.exportAscii.addEventListener("click", () => {
  try {
    exportAsciiReport();
  } catch (error) {
    setStatus(`Failed to export ASCII report: ${error.message}`);
  }
});
els.graphTab.addEventListener("click", () => setResultTab("graph"));
els.notesTab.addEventListener("click", () => setResultTab("notes"));

updatePurposeFields();

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
    .map(([path, content], index) => {
      const record = JSON.parse(content);
      return {
        path,
        record,
        note: normalizeNoteEntry(path, record, index),
      };
    })
    .sort((left, right) =>
      String(left.record?.derived?.commitment ?? "").localeCompare(String(right.record?.derived?.commitment ?? "")));
  notes.forEach((entry, index) => {
    entry.note.label = `N${String(index + 1).padStart(2, "0")}`;
  });
  if (notes.length === 0) {
    throw new Error("The evidence bundle does not contain current epoch-aware note records.");
  }
  state.files = files;
  state.manifest = manifest;
  state.notes = notes;
  state.filteredNotes = notes;
  state.selectedNotePaths = new Set(notes.map((entry) => entry.path));
  els.buildPackage.disabled = false;
  els.exportAscii.disabled = false;
  els.selectAll.disabled = false;
  els.selectNone.disabled = false;
  renderSummary();
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
  state.graph = { nodes: [], edges: [] };
  state.selectedNotePaths.clear();
  els.buildPackage.disabled = true;
  els.exportAscii.disabled = true;
  els.selectAll.disabled = true;
  els.selectNone.disabled = true;
  els.noteRows.textContent = "";
  els.graphSvg.textContent = "";
  els.summaryCards.textContent = "";
  hideNodeDetail();
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
  renderResults();
  setStatus(`${state.filteredNotes.length} of ${state.notes.length} notes match the current filter.`);
}

function getFilterCriteria(form) {
  const purpose = String(form.get("purpose") ?? "overview");
  const criteria = {
    purpose,
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
  if (!["receipt", "spend"].includes(purpose)) criteria.commitment = "";
  if (purpose !== "spend") criteria.nullifier = "";
  if (!["receipt", "transaction"].includes(purpose)) criteria.creationTx = "";
  if (!["spend", "transaction"].includes(purpose)) criteria.spendTx = "";
  if (purpose !== "range") {
    criteria.createdFrom = null;
    criteria.createdTo = null;
  }
  if (!["range", "spend"].includes(purpose)) {
    criteria.spentFrom = null;
    criteria.spentTo = null;
  }
  if (purpose !== "counterparty") criteria.counterparty = "";
  return criteria;
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

function normalizeNoteEntry(path, record, index) {
  return {
    path,
    label: `N${String(index + 1).padStart(2, "0")}`,
    commitment: record.derived?.commitment ?? null,
    nullifier: record.derived?.nullifier ?? null,
    value: record.plaintext?.value ?? null,
    owner: record.plaintext?.owner ?? null,
    salt: record.plaintext?.salt ?? null,
    status: record.spend?.status ?? "unknown",
    direction: record.relationshipHints?.direction ?? "unknown",
    counterparty: record.relationshipHints?.counterpartyL2Address ?? null,
    creation: normalizeEventRef(record.creation),
    spend: normalizeEventRef(record.spend),
    walletPath: path.split("/notes/")[0] ?? "",
  };
}

function normalizeEventRef(value) {
  if (!value) {
    return null;
  }
  return {
    txHash: value.txHash ?? null,
    blockNumber: value.blockNumber ?? null,
    logIndex: value.logIndex ?? null,
    functionName: value.functionName ?? value.function ?? null,
    acceptedTransition: value.acceptedTransition ?? null,
  };
}

function renderResults() {
  renderNotes();
  buildGraph();
  renderGraph();
  renderSummary();
  hideNodeDetail();
}

function renderSummary() {
  els.summaryCards.textContent = "";
  if (!state.manifest) {
    return;
  }
  const total = state.notes.length;
  const spent = state.notes.filter(({ note }) => note.status === "spent").length;
  const unused = state.notes.filter(({ note }) => note.status === "unused").length;
  const visible = state.filteredNotes.length;
  const externalOnly = countExternalOnlyNotes(state.notes);
  const selected = state.selectedNotePaths.size;
  const summaryItems = [
    ["Wallet", evidenceWalletLabel(state.manifest)],
    ["Visible notes", `${visible} / ${total}`],
    ["Spent / unused", `${spent} / ${unused}`],
    ["Selected for ZIP", String(selected)],
    ["External-only notes", String(externalOnly)],
  ];
  for (const [label, value] of summaryItems) {
    const item = document.createElement("div");
    item.className = "summary-card";
    const title = document.createElement("span");
    title.textContent = label;
    const body = document.createElement("strong");
    body.textContent = value;
    item.append(title, body);
    els.summaryCards.append(item);
  }
}

function countExternalOnlyNotes(notes) {
  const creationTxs = new Set(notes.map(({ note }) => note.creation?.txHash).filter(Boolean));
  const spendTxs = new Set(notes.map(({ note }) => note.spend?.txHash).filter(Boolean));
  let count = 0;
  for (const { note } of notes) {
    const hasLocalPredecessor = note.creation?.txHash && spendTxs.has(note.creation.txHash);
    const hasLocalSuccessor = note.spend?.txHash && creationTxs.has(note.spend.txHash);
    if (!hasLocalPredecessor && !hasLocalSuccessor) {
      count += 1;
    }
  }
  return count;
}

function renderNotes() {
  els.noteRows.textContent = "";
  const fragment = document.createDocumentFragment();
  for (const { path, record, note } of state.filteredNotes) {
    const row = document.createElement("tr");
    row.append(
      cellWithCheckbox(path),
      monoCell(`${note.label} ${shortHex(record.derived?.commitment)}`),
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
    renderSummary();
  });
  cell.append(checkbox);
  return cell;
}

function buildGraph() {
  const entries = state.filteredNotes;
  const noteByPath = new Map(entries.map((entry) => [entry.path, entry.note]));
  const notesByCreationTx = groupNotesByTx(entries, "creation");
  const edges = [];
  const incoming = new Map(entries.map(({ path }) => [path, []]));
  const outgoing = new Map(entries.map(({ path }) => [path, []]));

  for (const { path, note } of entries) {
    const localSuccessors = note.spend?.txHash ? notesByCreationTx.get(note.spend.txHash) ?? [] : [];
    for (const successor of localSuccessors) {
      if (successor.path === path) {
        continue;
      }
      const edge = {
        id: `${path}->${successor.path}`,
        type: "local",
        sourcePath: path,
        targetPath: successor.path,
        txHash: note.spend.txHash,
      };
      edges.push(edge);
      outgoing.get(path).push(edge);
      incoming.get(successor.path).push(edge);
    }
  }

  for (const { path, note } of entries) {
    const hasLocalPredecessor = incoming.get(path).length > 0;
    const hasLocalSuccessor = outgoing.get(path).length > 0;
    if (!hasLocalPredecessor) {
      edges.push({
        id: `external-in->${path}`,
        type: "external-in",
        targetPath: path,
        txHash: note.creation?.txHash ?? null,
      });
    }
    if (note.status === "spent" && !hasLocalSuccessor) {
      edges.push({
        id: `${path}->external-out`,
        type: "external-out",
        sourcePath: path,
        txHash: note.spend?.txHash ?? null,
      });
    }
  }

  const depthByPath = computeGraphDepth(entries, incoming, noteByPath);
  const rowByPath = assignGraphRows(entries, incoming, outgoing);

  const nodes = entries.map(({ path, note }) => ({
    path,
    note,
    depth: depthByPath.get(path) ?? 0,
    row: rowByPath.get(path) ?? 0,
    x: 120 + (depthByPath.get(path) ?? 0) * 240,
    y: 80 + (rowByPath.get(path) ?? 0) * 88,
  }));
  state.graph = { nodes, edges };
}

function assignGraphRows(entries, incoming, outgoing) {
  const entryByPath = new Map(entries.map((entry) => [entry.path, entry]));
  const rowByPath = new Map();
  let row = 0;
  const ordered = [...entries].sort(compareNoteEntriesForGraph);
  const roots = ordered.filter((entry) => (incoming.get(entry.path) ?? []).length === 0);
  const assignChain = (entry) => {
    let current = entry;
    let safety = entries.length + 1;
    while (current && !rowByPath.has(current.path) && safety > 0) {
      rowByPath.set(current.path, row);
      const nextEdge = (outgoing.get(current.path) ?? [])[0];
      current = nextEdge?.targetPath ? entryByPath.get(nextEdge.targetPath) : null;
      safety -= 1;
    }
    row += 1;
  };
  for (const root of roots) {
    assignChain(root);
  }
  for (const entry of ordered) {
    if (!rowByPath.has(entry.path)) {
      assignChain(entry);
    }
  }
  return rowByPath;
}

function compareNoteEntriesForGraph(left, right) {
  return compareNullableNumber(left.note.creation?.blockNumber, right.note.creation?.blockNumber)
    || compareNullableNumber(left.note.creation?.logIndex, right.note.creation?.logIndex)
    || left.note.label.localeCompare(right.note.label);
}

function groupNotesByTx(entries, section) {
  const result = new Map();
  for (const entry of entries) {
    const txHash = entry.note[section]?.txHash;
    if (!txHash) {
      continue;
    }
    if (!result.has(txHash)) {
      result.set(txHash, []);
    }
    result.get(txHash).push(entry);
  }
  return result;
}

function computeGraphDepth(entries, incoming, noteByPath) {
  const depthByPath = new Map();
  const visiting = new Set();
  const visit = (path) => {
    if (depthByPath.has(path)) {
      return depthByPath.get(path);
    }
    if (visiting.has(path)) {
      return 0;
    }
    visiting.add(path);
    const predecessors = incoming.get(path) ?? [];
    let depth = 0;
    for (const edge of predecessors) {
      if (!edge.sourcePath || !noteByPath.has(edge.sourcePath)) {
        continue;
      }
      depth = Math.max(depth, visit(edge.sourcePath) + 1);
    }
    visiting.delete(path);
    depthByPath.set(path, depth);
    return depth;
  };
  for (const { path } of entries) {
    visit(path);
  }
  return depthByPath;
}

function renderGraph() {
  const svg = els.graphSvg;
  svg.textContent = "";
  const nodes = state.graph.nodes;
  if (!nodes.length) {
    svg.setAttribute("width", "720");
    svg.setAttribute("height", "220");
    const empty = svgElement("text", { x: 28, y: 48, class: "graph-empty" });
    empty.textContent = "No notes match the current request.";
    svg.append(empty);
    return;
  }

  const nodeByPath = new Map(nodes.map((node) => [node.path, node]));
  const width = Math.max(900, Math.max(...nodes.map((node) => node.x)) + 260);
  const height = Math.max(360, Math.max(...nodes.map((node) => node.y)) + 130);
  svg.setAttribute("width", String(width));
  svg.setAttribute("height", String(height));
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.append(buildGraphDefs());

  for (const edge of state.graph.edges) {
    renderGraphEdge(svg, edge, nodeByPath, width);
  }
  for (const node of nodes) {
    renderGraphNode(svg, node);
  }
}

function buildGraphDefs() {
  const defs = svgElement("defs");
  const marker = svgElement("marker", {
    id: "arrow",
    markerWidth: "10",
    markerHeight: "10",
    refX: "9",
    refY: "3",
    orient: "auto",
    markerUnits: "strokeWidth",
  });
  const path = svgElement("path", { d: "M0,0 L0,6 L9,3 z", class: "edge-arrow" });
  marker.append(path);
  defs.append(marker);
  return defs;
}

function renderGraphEdge(svg, edge, nodeByPath, width) {
  const source = edge.sourcePath ? nodeByPath.get(edge.sourcePath) : null;
  const target = edge.targetPath ? nodeByPath.get(edge.targetPath) : null;
  const sourcePoint = source
    ? { x: source.x + 150, y: source.y + 28 }
    : { x: 34, y: target.y + 28 };
  const targetPoint = target
    ? { x: target.x, y: target.y + 28 }
    : { x: Math.min(width - 34, source.x + 230), y: source.y + 28 };
  const path = svgElement("path", {
    d: curvedPath(sourcePoint, targetPoint),
    class: `graph-edge ${edge.type}`,
    "marker-end": "url(#arrow)",
  });
  svg.append(path);

  const label = svgElement("text", {
    x: String((sourcePoint.x + targetPoint.x) / 2),
    y: String((sourcePoint.y + targetPoint.y) / 2 - 8),
    class: "edge-label",
  });
  label.textContent = edge.type === "local" ? shortHex(edge.txHash) : edge.type === "external-in" ? "created" : "spent";
  svg.append(label);
}

function curvedPath(source, target) {
  const distance = Math.max(60, Math.abs(target.x - source.x));
  const control = Math.min(120, distance / 2);
  return `M ${source.x} ${source.y} C ${source.x + control} ${source.y}, ${target.x - control} ${target.y}, ${target.x} ${target.y}`;
}

function renderGraphNode(svg, node) {
  const group = svgElement("g", {
    class: `graph-node ${state.selectedNotePaths.has(node.path) ? "is-selected" : ""}`,
    tabindex: "0",
    role: "button",
    "aria-label": `${node.note.label} note details`,
  });
  group.addEventListener("click", () => showNodeDetail(node));
  group.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      showNodeDetail(node);
    }
  });
  const rect = svgElement("rect", {
    x: String(node.x),
    y: String(node.y),
    width: "150",
    height: "58",
    rx: "8",
  });
  const label = svgElement("text", { x: String(node.x + 14), y: String(node.y + 22), class: "node-label" });
  label.textContent = node.note.label;
  const value = svgElement("text", { x: String(node.x + 14), y: String(node.y + 42), class: "node-value" });
  value.textContent = `${shortText(node.note.value ?? "-", 15)} ${node.note.status}`;
  const commitment = svgElement("title");
  commitment.textContent = node.note.commitment ?? "";
  group.append(rect, label, value, commitment);
  svg.append(group);
}

function showNodeDetail(node) {
  const detail = els.nodeDetail;
  const selected = state.selectedNotePaths.has(node.path);
  detail.classList.remove("is-hidden");
  detail.style.left = `${node.x + 166}px`;
  detail.style.top = `${Math.max(12, node.y - 8)}px`;
  detail.textContent = "";
  const title = document.createElement("div");
  title.className = "detail-title";
  title.textContent = `${node.note.label} note`;
  const selectButton = document.createElement("button");
  selectButton.type = "button";
  selectButton.className = "secondary";
  selectButton.textContent = selected ? "Remove from ZIP" : "Add to ZIP";
  selectButton.addEventListener("click", () => {
    if (state.selectedNotePaths.has(node.path)) {
      state.selectedNotePaths.delete(node.path);
    } else {
      state.selectedNotePaths.add(node.path);
    }
    renderResults();
    showNodeDetail(node);
  });
  detail.append(title, detailRows(node.note), selectButton);
}

function detailRows(note) {
  const container = document.createElement("dl");
  container.className = "detail-rows";
  for (const [label, value] of [
    ["Commitment", note.commitment],
    ["Nullifier", note.nullifier],
    ["Value", note.value],
    ["Status", note.status],
    ["Created", formatEventRef(note.creation)],
    ["Spent", formatEventRef(note.spend)],
    ["Direction", note.direction],
    ["Counterparty", note.counterparty],
  ]) {
    const term = document.createElement("dt");
    term.textContent = label;
    const description = document.createElement("dd");
    description.className = "mono";
    description.textContent = value || "-";
    container.append(term, description);
  }
  return container;
}

function hideNodeDetail() {
  els.nodeDetail.classList.add("is-hidden");
  els.nodeDetail.textContent = "";
}

function setResultTab(tab) {
  state.activeTab = tab;
  els.graphTab.classList.toggle("is-active", tab === "graph");
  els.notesTab.classList.toggle("is-active", tab === "notes");
  els.graphPanel.classList.toggle("is-active", tab === "graph");
  els.notesPanel.classList.toggle("is-active", tab === "notes");
}

function updatePurposeFields() {
  const purpose = String(new FormData(els.filters).get("purpose") ?? "overview");
  const fields = [...els.filters.querySelectorAll("[data-purpose-field]")];
  for (const element of fields) {
    const values = element.dataset.purposeField.split(/\s+/u);
    element.hidden = purpose === "overview" ? true : !values.includes(purpose);
  }
  const section = els.filters.querySelector(".form-section");
  if (section) {
    section.hidden = fields.every((element) => element.hidden);
  }
}

function exportAsciiReport() {
  if (!state.manifest) {
    throw new Error("Load an evidence bundle first.");
  }
  if (state.filteredNotes.length === 0) {
    throw new Error("No notes match the current request.");
  }
  const metadata = readPackageMetadata();
  const report = buildAsciiReport(metadata);
  const name = asciiReportFileName(metadata, state.manifest);
  downloadBlob(new Blob([report], { type: "text/markdown" }), name);
  setStatus(`Exported ${name} with ${state.filteredNotes.length} visible notes.`);
}

function buildAsciiReport(metadata) {
  const selected = new Set(state.selectedNotePaths);
  const lines = [
    "# Private-State Note Linkage Report",
    "",
    `Generated at: ${new Date().toISOString()}`,
    `Network: ${state.manifest.network ?? "-"}`,
    `Channel: ${state.manifest.channelName ?? state.manifest.channelId ?? "-"}`,
    `Wallet: ${evidenceWalletLabel(state.manifest)}`,
    `Case ID: ${metadata.caseId || "-"}`,
    `Requesting party: ${metadata.requestingParty || "-"}`,
    "",
    "## ASCII Linkage Graph",
    "",
    "```text",
    ...asciiGraphLines(),
    "```",
    "",
    "## Note Details",
    "",
  ];
  for (const { note } of state.filteredNotes) {
    lines.push(
      `### ${note.label}${selected.has(note.path) ? " (selected)" : ""}`,
      "",
      `- Commitment: ${note.commitment ?? "-"}`,
      `- Nullifier: ${note.nullifier ?? "-"}`,
      `- Value: ${note.value ?? "-"}`,
      `- Status: ${note.status}`,
      `- Created: ${formatEventRef(note.creation)}`,
      `- Spent: ${formatEventRef(note.spend)}`,
      `- Direction: ${note.direction}`,
      `- Counterparty: ${note.counterparty ?? "-"}`,
      "",
    );
  }
  return `${lines.join("\n")}\n`;
}

function asciiGraphLines() {
  const nodeByPath = new Map(state.graph.nodes.map((node) => [node.path, node]));
  const localEdges = state.graph.edges.filter((edge) => edge.type === "local");
  const outgoing = new Map();
  const incoming = new Map();
  for (const edge of localEdges) {
    if (!outgoing.has(edge.sourcePath)) outgoing.set(edge.sourcePath, []);
    if (!incoming.has(edge.targetPath)) incoming.set(edge.targetPath, []);
    outgoing.get(edge.sourcePath).push(edge);
    incoming.get(edge.targetPath).push(edge);
  }
  const lines = [];
  const nodes = [...state.graph.nodes].sort((left, right) =>
    compareNullableNumber(left.note.creation?.blockNumber, right.note.creation?.blockNumber)
    || left.note.label.localeCompare(right.note.label));
  for (const node of nodes) {
    if (!incoming.has(node.path)) {
      lines.push(`external -> ${asciiNodeLabel(node.note)}`);
    }
    for (const edge of outgoing.get(node.path) ?? []) {
      const target = nodeByPath.get(edge.targetPath);
      if (target) {
        lines.push(`${asciiNodeLabel(node.note)} -- ${shortHex(edge.txHash)} --> ${asciiNodeLabel(target.note)}`);
      }
    }
    if (node.note.status === "spent" && !outgoing.has(node.path)) {
      lines.push(`${asciiNodeLabel(node.note)} -> external`);
    }
    if (node.note.status !== "spent" && !outgoing.has(node.path)) {
      lines.push(`${asciiNodeLabel(node.note)} remains unused`);
    }
  }
  return lines.length ? lines : ["No linkage graph is available for the current filter."];
}

function asciiNodeLabel(note) {
  return `${note.label}[${note.value ?? "-"}, ${note.status}, ${shortHex(note.commitment)}]`;
}

function asciiReportFileName(metadata, manifest) {
  const rawName = [
    metadata.caseId || "note-linkage-report",
    manifest.network,
    manifest.channelName,
    new Date().toISOString().replace(/[:.]/g, "-"),
  ].filter(Boolean).join("-");
  return `${rawName.replace(/[^A-Za-z0-9_.-]+/g, "-")}.md`;
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

function compareNullableNumber(left, right) {
  const leftNumber = Number.isFinite(Number(left)) ? Number(left) : Number.MAX_SAFE_INTEGER;
  const rightNumber = Number.isFinite(Number(right)) ? Number(right) : Number.MAX_SAFE_INTEGER;
  return leftNumber - rightNumber;
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

function shortText(value, maxLength) {
  const text = String(value ?? "");
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, Math.max(1, maxLength - 3))}...`;
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

function svgElement(tagName, attributes = {}) {
  const element = document.createElementNS("http://www.w3.org/2000/svg", tagName);
  for (const [key, value] of Object.entries(attributes)) {
    element.setAttribute(key, value);
  }
  return element;
}
