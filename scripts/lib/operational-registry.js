'use strict';

// Private routing data is never authority to execute an action. Public callers
// do not load this map; operational callers must opt in and bind its revision.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const childProcess = require('node:child_process');

const MAX_BYTES = 1024 * 1024;
const HOST = /^(?!-)[A-Za-z0-9][A-Za-z0-9._-]{0,252}$/;
const USER = /^[a-z_][a-z0-9_-]*$/;
const ID = /^[a-z][a-z0-9-]*$/;
const PRIVATE_COMPONENT_FIELDS = ['deploy_path', 'persistent_paths', 'systemd_runtime', 'external_environment_files', 'health_check'];
const PRIVATE_DEPLOY_FIELDS = ['release_root', 'deployed_marker', 'coupled_state'];

class OperationalError extends Error {
  constructor(code) { super('Operational registry: ' + code); this.code = code; }
}
function fail(code) { throw new OperationalError(code); }
function plain(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function exactKeys(value, allowed) {
  if (!plain(value) || Object.keys(value).some(k => !allowed.includes(k))) fail('MAP_FORMAT');
}
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function digest(raw) { return crypto.createHash('sha256').update(raw).digest('hex'); }
function assertPublicRegistry(registry) {
  if (!plain(registry) || registry.registry_profile !== 'public-v1' ||
      !Array.isArray(registry.nodes) || !Array.isArray(registry.components)) fail('REGISTRY_PROFILE');
  for (const n of registry.nodes) {
    if (!plain(n) || !ID.test(n.node_id || '') ||
        (n.hostname !== null && n.hostname !== n.node_id + '.invalid') || n.ssh_alias !== null ||
        Object.hasOwn(n, 'hardware') || Object.hasOwn(n, 'notes')) fail('PUBLIC_PRIVATE_DATA');
  }
  for (const c of registry.components) {
    if (!plain(c) || (c.host !== null && c.host !== c.target_node_id + '.invalid')) fail('PUBLIC_PRIVATE_DATA');
  }
  const raw = JSON.stringify(registry);
  if (/\/home\/(?!example(?:\/|"))|\/Users\/(?!example(?:\/|"))/.test(raw)) fail('PUBLIC_PRIVATE_DATA');
  function checkAliases(value) {
    if (typeof value === 'string' && !value.startsWith('/') && !value.startsWith('.local/') && /\.local\b|\.ts\.net\b/.test(value)) fail('PUBLIC_PRIVATE_DATA');
    if (value && typeof value === 'object') Object.values(value).forEach(checkAliases);
  }
  checkAliases(registry);
  for (const match of raw.matchAll(/\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b/g)) {
    const a = Number(match[1]), b = Number(match[2]);
    if (a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127)) fail('PUBLIC_PRIVATE_DATA');
  }
}
function parse(raw, code) {
  const text = String(raw);
  let parsed;
  try { parsed = JSON.parse(text); } catch (e) {
    if (e instanceof SyntaxError) fail(code);
    throw e;
  }
  // JSON.parse silently keeps the final duplicate key. Reject that ambiguity,
  // including equivalent escaped keys, before using any routing field. Syntax
  // has already been checked; this bounded walk only tracks object key identity.
  let i = 0;
  function whitespace() { while (/\s/.test(text[i] || '') && i < text.length) i++; }
  function string() {
    const start = i++;
    while (i < text.length) {
      if (text[i] === '\\') i += 2;
      else if (text[i++] === '"') return JSON.parse(text.slice(start, i));
    }
    fail(code);
  }
  function value(depth) {
    if (depth > 100) fail(code);
    whitespace();
    if (text[i] === '{') {
      i++; whitespace();
      const keys = new Set();
      while (text[i] !== '}') {
        const key = string();
        if (keys.has(key)) fail(code === 'MAP_FORMAT' ? 'AMBIGUOUS_ENTRY' : code);
        keys.add(key); whitespace(); i++;
        value(depth + 1); whitespace();
        if (text[i] !== ',') break;
        i++; whitespace();
      }
      i++;
    } else if (text[i] === '[') {
      i++; whitespace();
      while (text[i] !== ']') {
        value(depth + 1); whitespace();
        if (text[i] !== ',') break;
        i++; whitespace();
      }
      i++;
    } else if (text[i] === '"') string();
    else while (i < text.length && !/[\s,\]}]/.test(text[i])) i++;
  }
  value(0);
  return parsed;
}
function defaultOverlayPath() {
  return process.env.GRIMNIR_OPERATIONAL_MAP || path.join(os.homedir(), '.config', 'grimnir', 'operational-map.json');
}
function readMap(file) {
  let fd;
  try {
    fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
    const st = fs.fstatSync(fd);
    if (!st.isFile() || st.uid !== process.getuid() || (st.mode & 0o7777) !== 0o600 || st.nlink !== 1) fail('MAP_PERMISSIONS');
    if (st.size < 2 || st.size > MAX_BYTES) fail('MAP_SIZE');
    const bytes = Buffer.alloc(st.size + 1);
    const count = fs.readSync(fd, bytes, 0, bytes.length, 0);
    const after = fs.fstatSync(fd);
    if (count !== st.size || after.size !== st.size || after.mtimeMs !== st.mtimeMs || after.ctimeMs !== st.ctimeMs) fail('MAP_CHANGED');
    return parse(bytes.subarray(0, count).toString('utf8'), 'MAP_FORMAT');
  } catch (e) {
    if (e instanceof OperationalError) throw e;
    if (e.code === 'ENOENT') fail('MAP_MISSING');
    if (e.code === 'ELOOP') fail('MAP_PERMISSIONS');
    if (typeof e.code === 'string') fail('MAP_UNREADABLE');
    throw e;
  } finally { if (fd !== undefined) fs.closeSync(fd); }
}
function indexed(rows, key, known, allowed) {
  if (!Array.isArray(rows)) fail('MAP_FORMAT');
  const result = new Map();
  for (const row of rows) {
    exactKeys(row, allowed);
    if (typeof row[key] !== 'string' || !known.has(row[key])) fail('UNKNOWN_ENTRY');
    if (result.has(row[key])) fail('AMBIGUOUS_ENTRY');
    result.set(row[key], row);
  }
  return result;
}
function sshTarget(value) {
  if (typeof value !== 'string') fail('TARGET_MISSING');
  const parts = value.split('@');
  if (parts.length !== 2 || !USER.test(parts[0]) || !HOST.test(parts[1]) || parts[1].endsWith('.invalid')) fail('TARGET_INVALID');
  return { user: parts[0], host: parts[1] };
}
function sameShapeStrings(template, value) {
  if (typeof template === 'string') return typeof value === 'string';
  if (Array.isArray(template)) return Array.isArray(value) && value.length === template.length && template.every((v, i) => sameShapeStrings(v, value[i]));
  if (plain(template)) return plain(value) && Object.keys(template).length === Object.keys(value).length && Object.keys(template).every(k => Object.hasOwn(value, k) && sameShapeStrings(template[k], value[k]));
  return value === template;
}
function applyFields(rows, overrides, fields, kind) {
  for (const row of rows) {
    const override = overrides.get(row.name);
    if (!override) continue;
    for (const field of fields) {
      if (!Object.hasOwn(override, field)) continue;
      if (!Object.hasOwn(row, field)) fail('POLICY_OVERRIDE');
      if (field === 'health_check') {
        const original = row[field], replacement = override[field];
        if (!plain(original) || !plain(replacement) || !Object.hasOwn(original, 'host') ||
            Object.keys(original).length !== Object.keys(replacement).length ||
            Object.keys(original).some(k => k !== 'host' && JSON.stringify(original[k]) !== JSON.stringify(replacement[k])) ||
            typeof replacement.host !== 'string' || !HOST.test(replacement.host)) fail('POLICY_OVERRIDE');
      } else if (field === 'persistent_paths') {
        const before = row[field], after = override[field];
        if (!Array.isArray(before) || !Array.isArray(after) || before.length !== after.length ||
            before.some((item, i) => typeof after[i] !== 'string' ||
              (item.startsWith('/') ? !after[i].startsWith('/') : item !== after[i]))) fail('POLICY_OVERRIDE');
      } else if (field === 'coupled_state') {
        const before = row[field], after = override[field];
        if (!Array.isArray(before) || !Array.isArray(after) || before.length !== after.length ||
            before.some((item, i) => !plain(after[i]) || Object.keys(item).length !== Object.keys(after[i]).length ||
              Object.keys(item).some(k => k !== 'home_relative_path' && JSON.stringify(item[k]) !== JSON.stringify(after[i][k])) ||
              typeof after[i].home_relative_path !== 'string')) fail('POLICY_OVERRIDE');
      } else if (!sameShapeStrings(row[field], override[field])) fail('POLICY_OVERRIDE');
      row[field] = clone(override[field]);
    }
  }
}

function loadOperationalRegistry(registryPath, options = {}) {
  let raw;
  try { raw = fs.readFileSync(registryPath); } catch (e) { fail('REGISTRY_UNREADABLE'); }
  if (raw.length > MAX_BYTES) fail('REGISTRY_SIZE');
  const registry = parse(raw, 'REGISTRY_FORMAT');
  if (!plain(registry) || !Array.isArray(registry.nodes) || !Array.isArray(registry.components)) fail('REGISTRY_FORMAT');
  assertPublicRegistry(registry);
  const original = clone(registry);
  const map = readMap(options.overlayPath || defaultOverlayPath());
  exactKeys(map, ['version', 'public_registry_sha256', 'deploy_user', 'local_node_id', 'nodes', 'components', 'owning_repo_deployments']);
  if (map.version !== 1) fail('MAP_VERSION');
  if (map.public_registry_sha256 !== digest(raw)) fail('MAP_STALE');
  if (typeof map.deploy_user !== 'string' || !USER.test(map.deploy_user)) fail('MAP_FORMAT');
  const nodeIds = new Set(registry.nodes.map(n => n.node_id));
  if (nodeIds.size !== registry.nodes.length || registry.nodes.some(n => !ID.test(n.node_id))) fail('REGISTRY_FORMAT');
  if (!nodeIds.has(map.local_node_id)) fail('UNKNOWN_ENTRY');
  const nodes = indexed(map.nodes, 'node_id', nodeIds,
    ['node_id', 'hostname', 'ssh_alias', 'ssh_target', 'hardware', 'notes', 'hardware_evidence']);
  const components = indexed(map.components || [], 'name', new Set(registry.components.map(c => c.name)), ['name', ...PRIVATE_COMPONENT_FIELDS]);
  const deployments = indexed(map.owning_repo_deployments || [], 'name', new Set((registry.owning_repo_deployments || []).map(d => d.name)), ['name', ...PRIVATE_DEPLOY_FIELDS]);
  for (const row of registry.nodes) {
    const entry = nodes.get(row.node_id);
    if (!entry) continue;
    if (entry.ssh_target !== undefined) sshTarget(entry.ssh_target);
    for (const key of ['hostname', 'ssh_alias']) {
      if (entry[key] !== undefined) {
        if (entry[key] !== null && (typeof entry[key] !== 'string' || !HOST.test(entry[key]))) fail('TARGET_INVALID');
        row[key] = entry[key];
      }
    }
    for (const key of ['hardware', 'notes']) {
      if (entry[key] !== undefined) {
        if (typeof entry[key] !== 'string') fail('MAP_FORMAT');
        row[key] = entry[key];
      }
    }
  }
  for (const row of registry.components) {
    if (row.host !== null) {
      const node = registry.nodes.find(n => n.node_id === row.target_node_id);
      if (!node) fail('REGISTRY_FORMAT');
      row.host = node.hostname;
    }
  }
  applyFields(registry.components, components, PRIVATE_COMPONENT_FIELDS, 'component');
  applyFields(registry.owning_repo_deployments || [], deployments, PRIVATE_DEPLOY_FIELDS, 'deployment');
  if (options.requireRuntime) {
    for (const n of registry.nodes) {
      if (n.hostname !== null && (typeof n.hostname !== 'string' || n.hostname.endsWith('.invalid'))) fail('RUNTIME_MAPPING_MISSING');
    }
    for (const c of registry.components.filter(c => c.deploy)) {
      const binding = nodes.get(c.target_node_id);
      if (!binding || sshTarget(binding.ssh_target).user !== map.deploy_user) fail('TARGET_INVALID');
    }
    for (const [section, fields, entries] of [['components', PRIVATE_COMPONENT_FIELDS, components], ['owning_repo_deployments', PRIVATE_DEPLOY_FIELDS, deployments]]) {
      for (const row of original[section] || []) {
        for (const field of fields) {
          if (Object.hasOwn(row, field) && (field !== 'health_check' || row[field].host !== undefined) &&
              !Object.hasOwn(entries.get(row.name) || {}, field)) fail('RUNTIME_MAPPING_MISSING');
        }
      }
    }
    // Validate the complete private runtime projection with the existing contract.
    // The child receives no inherited application/provider environment.
    const checked = clone(registry);
    checked.registry_profile = 'operational-v1';
    const result = childProcess.spawnSync(process.execPath, [path.join(__dirname, 'validate-registry.js')], {
      input: JSON.stringify(checked), encoding: 'utf8', timeout: 10000, maxBuffer: MAX_BYTES,
      env: { REGISTRY_DATA_STDIN: '1', PATH: path.dirname(process.execPath) + ':/usr/bin:/bin' }
    });
    if (result.error || result.status !== 0) fail('RUNTIME_INVALID');
  }
  return { registry, deploy_user: map.deploy_user, local_node_id: map.local_node_id, nodes_by_id: nodes, public_registry: original };
}

function resolveNode(registryPath, nodeId, options = {}) {
  const loaded = loadOperationalRegistry(registryPath, options);
  const node = loaded.public_registry.nodes.find(n => n.node_id === nodeId);
  if (!node) fail('UNKNOWN_NODE');
  const entry = loaded.nodes_by_id.get(nodeId);
  if (!entry) fail('TARGET_MISSING');
  sshTarget(entry.ssh_target);
  const evidence = entry.hardware_evidence;
  if (!evidence) fail('EVIDENCE_MISSING');
  exactKeys(evidence, ['observed_at', 'source_ref', 'model', 'architecture', 'memory_mib']);
  if (typeof evidence.source_ref !== 'string' || !/^BROKKR-[1-9][0-9]*$/.test(evidence.source_ref) ||
      typeof evidence.model !== 'string' || !evidence.model.trim() || evidence.model.length > 200 ||
      !['aarch64', 'arm64', 'x86_64', 'armv7l', 'unknown'].includes(evidence.architecture) ||
      !Number.isSafeInteger(evidence.memory_mib) || evidence.memory_mib <= 0) fail('EVIDENCE_INVALID');
  const now = options.now === undefined ? Date.now() : options.now;
  const observed = Date.parse(evidence.observed_at);
  if (!Number.isFinite(now) || !Number.isFinite(observed) || typeof evidence.observed_at !== 'string' ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(evidence.observed_at)) fail('EVIDENCE_INVALID');
  if (observed > now + 300000) fail('EVIDENCE_FUTURE');
  if (now - observed > 86400000) fail('EVIDENCE_STALE');
  const result = { node_id: node.node_id, hostname: node.hostname, status: 'known',
    transport: { configured: true, scope: 'operator-ssh' },
    evidence: { source_ref: evidence.source_ref, observed_at: evidence.observed_at, freshness: 'fresh' } };
  if (options.privateOutput === true) {
    result.ssh_target = entry.ssh_target;
    result.hardware = clone(evidence);
  }
  return result;
}

module.exports = { OperationalError, loadOperationalRegistry, resolveNode, defaultOverlayPath, assertPublicRegistry };
