#!/usr/bin/env node
/**
 * Run Naukri and Wellfound auto-apply side by side in one terminal.
 *
 *   node run-both.js --live      # apply for real on both sites
 *   node run-both.js             # dry run on both (nothing is sent)
 *
 * Each site keeps its own Chrome profile, daily counter and log file, so the two
 * runs don't interfere. Flags are passed through to both runners.
 */
const { spawn } = require('child_process');
const path = require('path');
const readline = require('readline');

const passthrough = process.argv.slice(2);
const children = [];

for (const site of ['wellfound', 'naukri']) {
  const tag = `[${site}] `;
  const child = spawn(
    process.execPath,
    [path.join(__dirname, 'auto-apply-runner.js'), site, ...passthrough],
    { cwd: __dirname, env: process.env, stdio: ['ignore', 'pipe', 'pipe'] },
  );
  children.push(child);
  for (const stream of [child.stdout, child.stderr]) {
    readline.createInterface({ input: stream }).on('line', (line) => {
      process.stdout.write(tag + line + '\n');
    });
  }
  child.on('exit', (code, signal) => {
    console.log(`${tag}finished (${signal || `exit ${code}`})`);
  });
}

const stopAll = () => {
  for (const child of children) if (!child.killed) child.kill();
};
process.on('SIGINT', () => {
  stopAll();
  setTimeout(() => process.exit(130), 1500);
});
process.on('SIGTERM', stopAll);
