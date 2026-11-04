#!/usr/bin/env node
/**
 * Today's auto-apply status at a glance: daily counters, CSV rows, recent log lines.
 * Usage: node .qoder/skills/naukri-auto-apply/scripts/status.cjs [logLines]
 */
const fs = require('fs');
const path = require('path');

const repo = path.resolve(__dirname, '..', '..', '..', '..');
const SITES = ['naukri', 'wellfound'];

// Read the caps from the runner so this report can't drift from what actually runs.
const runnerSrc = (() => {
  try {
    return fs.readFileSync(path.join(repo, 'auto-apply-runner.js'), 'utf8');
  } catch (e) {
    return '';
  }
})();
const CAPS = Object.fromEntries(
  SITES.map((site) => {
    const m = runnerSrc.match(new RegExp(`${site}: \\{[\\s\\S]*?dailyCap: (\\d+)`));
    return [site, m ? Number(m[1]) : 50];
  }),
);
const tailLines = Math.max(1, parseInt(process.argv[2], 10) || 6);
const today = new Date().toDateString();
const todayPrefix = new Date().toLocaleDateString();

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  } catch (e) {
    return null;
  }
}

function csvCount(site) {
  const file = path.join(repo, 'applications.csv');
  if (!fs.existsSync(file)) return 0;
  return fs
    .readFileSync(file, 'utf8')
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .slice(1)
    .filter((line) => line.includes(`"${site}"`) && line.startsWith(`"${todayPrefix}`))
    .length;
}

function lastLines(file, n) {
  if (!fs.existsSync(file)) return [`(no ${path.basename(file)})`];
  const lines = fs.readFileSync(file, 'utf8').trimEnd().split(/\r?\n/);
  return lines.slice(-n);
}

console.log(`Date: ${today}`);
for (const site of SITES) {
  const state = readJson(path.join(repo, `apply-state-${site}.json`));
  const used = state && state.date === today ? state.count : 0;
  const rows = csvCount(site);
  console.log(`\n${site}: ${used}/${CAPS[site]} today` + (rows !== used ? `  (CSV rows today: ${rows} — mismatch means a lost write)` : ''));
  for (const line of lastLines(path.join(repo, `auto-apply-${site}.log`), tailLines)) {
    console.log(`  ${line}`);
  }
}
