#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

function fail(message) {
  console.error(`[release-check] ${message}`);
  process.exit(1);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function readUtf8(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function parseChangelogEntries(markdown) {
  const lines = markdown.split(/\r?\n/u);
  const entries = [];
  let current = null;

  for (const line of lines) {
    const match = /^##\s+(\S+)\s+-\s+(\d{4}-\d{2}-\d{2})\s*$/u.exec(line);
    if (match) {
      if (current !== null) {
        current.body = current.body.join('\n').trim();
        entries.push(current);
      }
      current = {
        version: match[1],
        date: match[2],
        body: [],
      };
      continue;
    }

    if (current !== null) {
      current.body.push(line);
    }
  }

  if (current !== null) {
    current.body = current.body.join('\n').trim();
    entries.push(current);
  }

  return entries;
}

function validateReleaseReadiness(packageRoot) {
  const manifestPath = path.join(packageRoot, 'package.json');
  const changelogPath = path.join(packageRoot, 'CHANGELOG.md');

  if (!fs.existsSync(manifestPath)) {
    fail(`Missing package manifest: ${manifestPath}`);
  }
  if (!fs.existsSync(changelogPath)) {
    fail(`Missing changelog: ${changelogPath}`);
  }

  const manifest = readJson(manifestPath);
  const version = manifest.version;
  if (typeof version !== 'string' || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/u.test(version)) {
    fail(`package.json version is missing or invalid: ${String(version)}`);
  }
  if (manifest.private === true) {
    fail(`${manifest.name ?? packageRoot} is marked private and cannot be published.`);
  }

  const entries = parseChangelogEntries(readUtf8(changelogPath));
  if (entries.length === 0) {
    fail('CHANGELOG.md does not contain any release entries.');
  }

  const latest = entries[0];
  if (latest.version !== version) {
    fail(`Top changelog entry is ${latest.version}, but package.json version is ${version}.`);
  }

  const bulletLines = latest.body
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .filter((line) => line.startsWith('- '));
  if (bulletLines.length === 0) {
    fail(`Top changelog entry for ${version} must contain at least one bullet.`);
  }

  return {
    name: manifest.name,
    version,
    date: latest.date,
    notes: latest.body.trim(),
  };
}

const packageRoot = path.resolve(process.cwd());
const release = validateReleaseReadiness(packageRoot);

if (process.argv.includes('--print-current-notes')) {
  process.stdout.write(`${release.notes}\n`);
  process.exit(0);
}

console.log(`[release-check] OK for ${release.name} ${release.version} (${release.date})`);
