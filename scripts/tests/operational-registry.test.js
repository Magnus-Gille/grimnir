'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const cp = require('node:child_process');

const {
  loadOperationalRegistry,
  resolveNode,
} = require('../lib/operational-registry.js');

const NOW = Date.parse('2026-11-03T12:00:00.000Z');
const PRIVATE_TARGET = 'operator@node-test.internal';

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function hardwareEvidence(observedAt) {
  return {
    observed_at: new Date(observedAt).toISOString(),
    source_ref: 'BROKKR-136',
    model: 'synthetic model',
    architecture: 'aarch64',
    memory_mib: 8192,
  };
}

function publicRegistry() {
  return {
    registry_profile: 'public-v1',
    components: [
      {
        name: 'demo-service',
        workload_id: 'workload-demo-service',
        target_node_id: 'node-test',
        repo: 'demo-service',
        host: 'node-test.invalid',
        port: 4321,
        deploy: true,
        scan: false,
        deploy_path: '/srv/demo-service',
        needs_build: false,
        systemd_units: [],
      },
    ],
    owning_repo_deployments: [
      {
        name: 'demo-release',
        repo: 'demo-service',
        target_node_id: 'node-test',
        command: ['./scripts/deploy-demo.sh'],
        revision_argument: '--release',
        release_root: '/srv/demo-service/releases',
        deployed_marker: '/srv/demo-service/.deployed-commit',
        loopback_port: 9321,
        systemd_units: [],
        coupled_state: [],
      },
    ],
    nodes: [
      {
        name: 'laptop',
        node_id: 'node-laptop',
        hostname: 'node-laptop.invalid',
        ssh_alias: null,
        role: 'inference',
        status: 'active',
        llm_servers: [],
        monitor: false,
      },
      {
        name: 'test',
        node_id: 'node-test',
        hostname: 'node-test.invalid',
        ssh_alias: null,
        role: 'service-host',
        status: 'active',
        llm_servers: [],
        monitor: false,
      },
    ],
  };
}

function writeJson(filePath, value, mode) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + '\n', { mode });
  if (mode !== undefined) fs.chmodSync(filePath, mode);
}

function makeFixture({ map = {}, mapMode = 0o600, registry = publicRegistry() } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'grimnir-operational-registry-'));
  const registryPath = path.join(directory, 'services.json');
  const overlayPath = path.join(directory, 'operational-map.json');
  writeJson(registryPath, registry, 0o644);
  const registryRaw = fs.readFileSync(registryPath);
  writeJson(overlayPath, {
    version: 1,
    public_registry_sha256: sha256(registryRaw),
    deploy_user: 'operator',
    local_node_id: 'node-laptop',
    nodes: [
      {
        node_id: 'node-test',
        ssh_target: PRIVATE_TARGET,
        hardware_evidence: hardwareEvidence(NOW - 60 * 1000),
      },
    ],
    components: [],
    owning_repo_deployments: [],
    ...map,
  }, mapMode);
  return {
    directory,
    registryPath,
    overlayPath,
  };
}

function cleanup(fixture) {
  fs.rmSync(fixture.directory, { recursive: true, force: true });
}

function assertOperationalError(fn, { notContains = [] } = {}) {
  assert.throws(fn, (error) => {
    assert.equal(typeof error.code, 'string');
    assert.match(error.code, /^[A-Z][A-Z0-9_]{1,79}$/);
    assert.equal(typeof error.message, 'string');
    for (const value of notContains) assert.equal(error.message.includes(value), false);
    return true;
  });
}

function safeText(value) {
  return JSON.stringify(value);
}

function runtimeFixture() {
  const registry = JSON.parse(fs.readFileSync(path.join(__dirname, '../../services.json'), 'utf8'));
  function privateExample(value) {
    if (typeof value === 'string') return value.replace('/home/example', '/home/operator').replace('/srv/example', '/srv/operator').replace('/etc/example', '/etc/operator');
    if (Array.isArray(value)) return value.map(privateExample);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, privateExample(v)]));
    return value;
  }
  const components = registry.components.map(c => {
    const entry = { name: c.name };
    for (const key of ['deploy_path', 'persistent_paths', 'systemd_runtime', 'external_environment_files', 'health_check']) {
      if (Object.hasOwn(c, key)) entry[key] = privateExample(c[key]);
    }
    if (entry.systemd_runtime) entry.systemd_runtime.user = 'operator';
    if (entry.health_check && entry.health_check.host) entry.health_check.host = c.target_node_id + '.example.test';
    return entry;
  });
  const deployments = registry.owning_repo_deployments.map(d => {
    const entry = { name: d.name };
    for (const key of ['release_root', 'deployed_marker', 'coupled_state']) if (Object.hasOwn(d, key)) entry[key] = privateExample(d[key]);
    return entry;
  });
  return makeFixture({ registry, map: {
    nodes: registry.nodes.map(n => ({ node_id: n.node_id, hostname: n.node_id + '.example.test', ssh_alias: null,
      ssh_target: 'operator@' + n.node_id + '.example.test' })),
    components, owning_repo_deployments: deployments,
  } });
}

test('public queries ignore private mappings; operational consumers require and validate them', (t) => {
  const fixture = runtimeFixture(); t.after(() => cleanup(fixture));
  const cli = path.join(__dirname, '../lib/registry.js');
  function query(name, missing = false) {
    return cp.spawnSync(process.execPath, [cli], { encoding: 'utf8', env: {
      PATH: process.env.PATH, HOME: fixture.directory, REGISTRY_PATH: fixture.registryPath, QUERY: name,
      GRIMNIR_OPERATIONAL_MAP: missing ? path.join(fixture.directory, 'missing-private-map') : fixture.overlayPath,
    } });
  }
  for (const name of ['nodes', 'nodes-json', 'all', 'json:name=heimdall', 'scan', 'repository-authority']) {
    for (const missing of [false, true]) {
      const r = query(name, missing); assert.equal(r.status, 0, name);
      assert.ok(!/operator@|\.example\.test|\/home\/operator|missing-private-map/.test(r.stdout + r.stderr), name + ' is public');
    }
  }
  for (const name of ['deploy', 'validate', 'owning-deploys', 'runtime-json']) {
    const missing = query(name, true);
    assert.equal(missing.status, 1); assert.equal(missing.stdout, '');
    assert.match(missing.stderr, /MAP_MISSING/); assert.ok(!missing.stderr.includes(fixture.directory));
    const known = query(name); assert.equal(known.status, 0, name + ' accepts validated private bindings');
  }
  const runtime = JSON.parse(query('runtime-json').stdout);
  assert.ok(!Object.hasOwn(runtime, 'registry_profile'), 'direct-file export preserves the legacy shape');
  assert.equal(runtime.components.find(c => c.name === 'heimdall').systemd_runtime.user, 'operator');
  const deploy = query('deploy').stdout.trim().split('\n').map(JSON.parse);
  assert.equal(deploy.find(c => c.name === 'hugin').host, 'node-huginmunin.example.test');
  assert.equal(deploy.find(c => c.name === 'hugin').unit_scope, 'user');
});

test('operational materialization cannot omit private paths or silently substitute an SSH account', (t) => {
  for (const mutation of ['missing_path', 'account', 'relative_persistence', 'health_boundary']) {
    const fixture = runtimeFixture(); t.after(() => cleanup(fixture));
    const map = JSON.parse(fs.readFileSync(fixture.overlayPath, 'utf8'));
    if (mutation === 'missing_path') delete map.components.find(c => c.name === 'heimdall').deploy_path;
    if (mutation === 'account') map.nodes.find(n => n.node_id === 'node-huginmunin').ssh_target = 'other@node-huginmunin.example.test';
    if (mutation === 'relative_persistence') {
      const pub = JSON.parse(fs.readFileSync(fixture.registryPath, 'utf8'));
      const component = pub.components.find(c => c.name === 'hugin');
      component.persistent_paths.push('state'); component.rsync_excludes = [...(component.rsync_excludes || []), '/state/'];
      writeJson(fixture.registryPath, pub, 0o644);
      map.public_registry_sha256 = sha256(fs.readFileSync(fixture.registryPath));
      map.components.find(c => c.name === 'hugin').persistent_paths.push('different');
    }
    if (mutation === 'health_boundary') map.components.find(c => c.health_check).health_check.boundary = 'host';
    writeJson(fixture.overlayPath, map, 0o600);
    assertOperationalError(() => loadOperationalRegistry(fixture.registryPath, { overlayPath: fixture.overlayPath, requireRuntime: true }));
  }
});

test('loads the public registry and resolves a known node with redacted safe metadata', (t) => {
  const fixture = makeFixture();
  t.after(() => cleanup(fixture));

  const loaded = loadOperationalRegistry(fixture.registryPath, {
    overlayPath: fixture.overlayPath,
    now: NOW,
  });
  assert.equal(loaded.deploy_user, 'operator');
  assert.equal(loaded.local_node_id, 'node-laptop');
  assert.equal(loaded.registry.registry_profile, 'public-v1');

  const resolved = resolveNode(fixture.registryPath, 'node-test', {
    overlayPath: fixture.overlayPath,
    now: NOW,
  });
  const text = safeText(resolved);
  assert.equal(resolved.node_id, 'node-test');
  assert.equal(resolved.hostname, 'node-test.invalid');
  assert.equal(Object.hasOwn(resolved, 'ssh_target'), false);
  assert.equal(Object.hasOwn(resolved, 'ssh_alias'), false);
  assert.equal(text.includes(PRIVATE_TARGET), false);
  assert.equal(text.includes('synthetic model'), false);
  assert.equal(text.includes('/srv/demo-service'), false);
  assert.match(text, /BROKKR-136/);
  assert.match(text, /observed_at/);
  assert.match(text, /fresh/);
});

test('private output exposes only the explicitly configured ssh target', (t) => {
  const fixture = makeFixture();
  t.after(() => cleanup(fixture));

  const resolved = resolveNode(fixture.registryPath, 'node-test', {
    overlayPath: fixture.overlayPath,
    now: NOW,
    privateOutput: true,
  });
  assert.equal(resolved.ssh_target, PRIVATE_TARGET);
  assert.equal(resolved.hostname, 'node-test.invalid');
});

test('binds the overlay to the exact raw public-registry sha256', (t) => {
  const fixture = makeFixture({
    map: { public_registry_sha256: '0'.repeat(64) },
  });
  t.after(() => cleanup(fixture));

  assertOperationalError(() => loadOperationalRegistry(fixture.registryPath, {
    overlayPath: fixture.overlayPath,
    now: NOW,
  }), { notContains: [fixture.registryPath, fixture.overlayPath, '0'.repeat(64)] });
});

test('duplicate JSON keys cannot silently select a different transport', (t) => {
  const fixture = makeFixture();
  t.after(() => cleanup(fixture));
  const raw = fs.readFileSync(fixture.overlayPath, 'utf8');
  fs.writeFileSync(fixture.overlayPath, raw.replace('"ssh_target":', '"ssh_target":"operator@first.example.test", "ssh_target":'));
  assertOperationalError(() => resolveNode(fixture.registryPath, 'node-test', {
    overlayPath: fixture.overlayPath, now: NOW,
  }), { notContains: [PRIVATE_TARGET, fixture.overlayPath, 'first.example.test'] });
});

test('requires a present, regular, non-symlink map with mode 0600', (t) => {
  const missing = makeFixture();
  t.after(() => cleanup(missing));
  fs.unlinkSync(missing.overlayPath);
  assertOperationalError(() => loadOperationalRegistry(missing.registryPath, {
    overlayPath: missing.overlayPath,
    now: NOW,
  }), { notContains: [missing.registryPath, missing.overlayPath] });

  const tooOpen = makeFixture({ mapMode: 0o644 });
  t.after(() => cleanup(tooOpen));
  assertOperationalError(() => loadOperationalRegistry(tooOpen.registryPath, {
    overlayPath: tooOpen.overlayPath,
    now: NOW,
  }), { notContains: [tooOpen.registryPath, tooOpen.overlayPath] });

  const symlink = makeFixture();
  t.after(() => cleanup(symlink));
  const realMap = path.join(symlink.directory, 'real-map.json');
  fs.renameSync(symlink.overlayPath, realMap);
  fs.symlinkSync(realMap, symlink.overlayPath);
  assertOperationalError(() => loadOperationalRegistry(symlink.registryPath, {
    overlayPath: symlink.overlayPath,
    now: NOW,
  }), { notContains: [symlink.registryPath, symlink.overlayPath] });
});

test('rejects duplicate and unknown node or entry identifiers', (t) => {
  const cases = [
    {
      name: 'duplicate node',
      map: {
        nodes: [
          { node_id: 'node-test', ssh_target: PRIVATE_TARGET },
          { node_id: 'node-test', ssh_target: 'operator@other.invalid' },
        ],
      },
      forbidden: 'node-test',
    },
    {
      name: 'unknown node',
      map: { nodes: [{ node_id: 'node-unknown', ssh_target: 'operator@unknown.invalid' }] },
      forbidden: 'node-unknown',
    },
    {
      name: 'unknown component',
      map: { components: [{ name: 'unknown-service', deploy_path: '/srv/unknown' }] },
      forbidden: 'unknown-service',
    },
    {
      name: 'unknown owning-repository deployment',
      map: { owning_repo_deployments: [{ name: 'unknown-release', release_root: '/srv/unknown' }] },
      forbidden: 'unknown-release',
    },
  ];

  for (const entry of cases) {
    const fixture = makeFixture({ map: entry.map });
    t.after(() => cleanup(fixture));
    assertOperationalError(() => loadOperationalRegistry(fixture.registryPath, {
      overlayPath: fixture.overlayPath,
      now: NOW,
    }), { notContains: [entry.forbidden, fixture.registryPath, fixture.overlayPath] });
  }
});

test('reports missing, stale, and fresh hardware evidence without leaking private fields', (t) => {
  const missing = makeFixture({ map: { nodes: [{ node_id: 'node-test', ssh_target: PRIVATE_TARGET }] } });
  t.after(() => cleanup(missing));
  assert.throws(() => resolveNode(missing.registryPath, 'node-test', {
    overlayPath: missing.overlayPath,
    now: NOW,
  }), { code: 'EVIDENCE_MISSING' });

  const stale = makeFixture({
    map: {
      nodes: [{
        node_id: 'node-test',
        ssh_target: PRIVATE_TARGET,
        hardware_evidence: hardwareEvidence(NOW - (86400 * 1000 + 1)),
      }],
    },
  });
  t.after(() => cleanup(stale));
  assert.throws(() => resolveNode(stale.registryPath, 'node-test', {
    overlayPath: stale.overlayPath,
    now: NOW,
  }), { code: 'EVIDENCE_STALE' });

  const fresh = makeFixture();
  t.after(() => cleanup(fresh));
  const freshResolved = resolveNode(fresh.registryPath, 'node-test', {
    overlayPath: fresh.overlayPath,
    now: NOW,
  });
  assert.match(safeText(freshResolved), /fresh/);
});

test('rejects hardware evidence more than five minutes in the future', (t) => {
  const fixture = makeFixture({
    map: {
      nodes: [{
        node_id: 'node-test',
        ssh_target: PRIVATE_TARGET,
        hardware_evidence: hardwareEvidence(NOW + 5 * 60 * 1000 + 1),
      }],
    },
  });
  t.after(() => cleanup(fixture));

  assertOperationalError(() => resolveNode(fixture.registryPath, 'node-test', {
    overlayPath: fixture.overlayPath,
    now: NOW,
  }), { notContains: [fixture.registryPath, fixture.overlayPath, 'node-test'] });
});

test('rejects overlays that change non-private component or placement fields', (t) => {
  const forbidden = [
    ['port', 9999],
    ['systemd_units', [{ name: 'demo.service', type: 'service' }]],
    ['repo', 'other-repo'],
    ['deploy', false],
    ['target_node_id', 'node-laptop'],
  ];

  for (const [field, value] of forbidden) {
    const fixture = makeFixture({ map: { components: [{ name: 'demo-service', [field]: value }] } });
    t.after(() => cleanup(fixture));
    assertOperationalError(() => loadOperationalRegistry(fixture.registryPath, {
      overlayPath: fixture.overlayPath,
      now: NOW,
    }), { notContains: [fixture.registryPath, fixture.overlayPath, String(value)] });
  }
});


test('an unknown explicit registry profile cannot downgrade into legacy operational output', (t) => {
  const fixture = runtimeFixture(); t.after(() => cleanup(fixture));
  const registry = JSON.parse(fs.readFileSync(fixture.registryPath, 'utf8'));
  registry.registry_profile = 'public-v2'; writeJson(fixture.registryPath, registry, 0o644);
  for (const name of ['deploy', 'runtime-json', 'profile']) {
    const result = cp.spawnSync(process.execPath, [path.join(__dirname, '../lib/registry.js')], {
      encoding: 'utf8', env: { PATH: process.env.PATH, HOME: fixture.directory,
        REGISTRY_PATH: fixture.registryPath, QUERY: name, GRIMNIR_OPERATIONAL_MAP: fixture.overlayPath }
    });
    assert.equal(result.status, 1); assert.equal(result.stdout, '');
    assert.match(result.stderr, /REGISTRY_PROFILE/);
  }
});
