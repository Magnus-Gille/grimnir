'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('checked-in registry exposes stable identities and reserved operational examples only', () => {
  const data = JSON.parse(fs.readFileSync(path.join(__dirname, '../../services.json'), 'utf8'));
  assert.ok(data.registry_profile === 'public-v1', 'public profile must be explicit');
  for (const node of data.nodes) {
    assert.ok(node.hostname === null || node.hostname === node.node_id + '.invalid', 'hostname must be reserved by stable identity');
    assert.ok(node.ssh_alias === null, 'SSH aliases belong to the private map');
    assert.ok(!Object.hasOwn(node, 'hardware') && !Object.hasOwn(node, 'notes'), 'observed hardware and operator notes are private evidence');
  }
  const raw = JSON.stringify(data);
  assert.ok(!/\/home\/(?!example(?:\/|"))|\/Users\/(?!example(?:\/|"))/.test(raw), 'no personal home paths');
  const checkAliases = value => {
    if (typeof value === 'string' && !value.startsWith('/') && !value.startsWith('.local/')) {
      assert.ok(!/\.local\b|\.ts\.net\b/.test(value), 'no operational host aliases');
    }
    if (value && typeof value === 'object') Object.values(value).forEach(checkAliases);
  };
  checkAliases(data);
  for (const match of raw.matchAll(/\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b/g)) {
    const [a, b] = match.slice(1).map(Number);
    assert.ok(!(a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 100 && b >= 64 && b <= 127)), 'private IPv4 locators cannot be public data');
  }
});
