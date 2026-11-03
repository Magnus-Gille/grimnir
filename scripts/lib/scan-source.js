#!/usr/bin/env node
'use strict';

// Fetch one advertised upstream HEAD into a disposable object repository.
// Never check out source, invoke repository hooks, or use a stale fallback.
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

class SourceError extends Error {}

function captureSource(authority, destination) {
  if (!/^[A-Za-z0-9][A-Za-z0-9-]*\/[A-Za-z0-9][A-Za-z0-9._-]*$/.test(authority || '')) {
    throw new SourceError('invalid repository authority');
  }
  if (!destination || !path.isAbsolute(destination) || path.resolve(destination) !== destination) {
    throw new SourceError('invalid source destination');
  }
  if (fs.existsSync(destination)) throw new SourceError('source destination already exists');

  // Existing GitHub authentication may use HOME/config or the owner's SSH
  // agent. The scanner's Munin credential and unrelated provider tokens must
  // not enter Git, its transport or credential-helper processes.
  const env = { GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'Never' };
  for (const key of ['PATH', 'HOME', 'XDG_CONFIG_HOME', 'TMPDIR', 'LANG', 'LC_ALL', 'SSH_AUTH_SOCK']) {
    if (process.env[key] !== undefined) env[key] = process.env[key];
  }
  const safeguards = [
    '-c', 'core.hooksPath=/dev/null',
    '-c', 'maintenance.auto=false',
    '-c', 'gc.auto=0',
    '-c', 'protocol.ext.allow=never',
    '-c', 'protocol.file.allow=never',
    '-c', 'fetch.fsckObjects=true',
    '-c', 'transfer.fsckObjects=true',
  ];
  function git(stage, args, cwd = path.dirname(destination)) {
    const result = spawnSync('git', [...safeguards, ...args], {
      cwd, env, encoding: 'utf8', timeout: 45000, maxBuffer: 4 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (result.error || result.status !== 0) throw new SourceError(stage + ' failed');
    return result.stdout.trim();
  }

  fs.mkdirSync(destination, { mode: 0o700 });
  git('initialization', ['init', '--quiet', '--template=', '--initial-branch=scan', destination]);
  git('origin setup', ['config', '--local', 'remote.origin.url', `https://github.com/${authority}.git`], destination);
  const advertised = git('upstream lookup', ['ls-remote', '--exit-code', 'origin', 'HEAD'], destination);
  const match = /^([0-9a-f]{40})\tHEAD$/.exec(advertised);
  if (!match) throw new SourceError('invalid upstream HEAD');
  const commit = match[1];
  const capturedAt = new Date().toISOString();
  git('upstream fetch', ['fetch', '--quiet', '--depth=1', '--no-tags', '--no-recurse-submodules', 'origin', commit], destination);
  const fetched = git('fetched revision check', ['rev-parse', '--verify', 'FETCH_HEAD^{commit}'], destination);
  if (fetched !== commit) throw new SourceError('upstream revision mismatch');
  // Bind HEAD without checkout, filters, smudge or materializing untrusted files.
  git('revision binding', ['update-ref', 'HEAD', commit], destination);
  if (git('bound revision check', ['rev-parse', '--verify', 'HEAD^{commit}'], destination) !== commit) {
    throw new SourceError('bound revision mismatch');
  }
  return { commit, captured_at: capturedAt };
}

if (require.main === module) {
  try {
    if (process.argv.length !== 4) throw new SourceError('expected authority and destination');
    process.stdout.write(JSON.stringify(captureSource(process.argv[2], process.argv[3])) + '\n');
  } catch (error) {
    // Transport stderr/configuration can contain private URLs or credentials.
    // Emit only our fixed stage diagnostics, never raw subprocess/parser errors.
    process.stderr.write('ERROR: upstream source: ' + (error instanceof SourceError ? error.message : 'local source preparation failed') + '\n');
    process.exitCode = 1;
  }
}

module.exports = { captureSource };
