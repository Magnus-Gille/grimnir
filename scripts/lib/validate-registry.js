// validate-registry.js — schema/consistency smoke check for services.json
//
// Usage:
//   REGISTRY_PATH=/path/to/services.json node --input-type=commonjs scripts/lib/validate-registry.js
//   REGISTRY_PATH defaults to services.json at the repo root.
//
// Exits 0 and prints a summary when the registry is well-formed and
// internally consistent. Exits 1 and prints every violation found when not.
// Read-only, no network access — safe to run in CI on every PR.

var fs = require('fs');
var path = require('path');

var registryPath = process.env.REGISTRY_PATH ||
  path.join(__dirname, '..', '..', 'services.json');

var errors = [];

function fail(msg) {
  errors.push(msg);
}

function isPlainObject(x) {
  return x !== null && typeof x === 'object' && !Array.isArray(x);
}

var raw;
try {
  raw = fs.readFileSync(registryPath, 'utf8');
} catch (err) {
  console.error('ERROR: Failed to read ' + registryPath + ': ' + err.message);
  process.exit(1);
}

var data;
try {
  data = JSON.parse(raw);
} catch (err) {
  console.error('ERROR: ' + registryPath + ' is not valid JSON: ' + err.message);
  process.exit(1);
}

if (!isPlainObject(data)) {
  fail('top-level document must be a JSON object');
  printAndExit();
}

if (!Array.isArray(data.components)) {
  fail('top-level "components" must be an array');
  printAndExit();
}

var VALID_UNIT_TYPES = ['service', 'timer'];
var VALID_UNIT_SCOPES = ['system', 'user'];

var seenNames = {};
var seenPorts = {};

data.components.forEach(function (c, i) {
  var label = '(index ' + i + ')';
  if (!isPlainObject(c)) {
    fail(label + ': component must be an object');
    return;
  }
  if (typeof c.name === 'string' && c.name) {
    label = c.name;
  } else {
    fail(label + ': missing/invalid required field "name" (non-empty string)');
  }

  ['repo'].forEach(function (field) {
    if (typeof c[field] !== 'string' || !c[field]) {
      fail(label + ': missing/invalid required field "' + field + '" (non-empty string)');
    }
  });

  ['deploy', 'scan', 'needs_build'].forEach(function (field) {
    if (typeof c[field] !== 'boolean') {
      fail(label + ': field "' + field + '" must be a boolean');
    }
  });

  if (c.host !== null && typeof c.host !== 'string') {
    fail(label + ': field "host" must be a string or null');
  }
  if (c.port !== undefined && c.port !== null && typeof c.port !== 'number') {
    fail(label + ': field "port" must be a number or null');
  }

  if (c.name && seenNames[c.name]) {
    fail('duplicate component name: "' + c.name + '"');
  } else if (c.name) {
    seenNames[c.name] = true;
  }

  if (typeof c.port === 'number') {
    if (seenPorts[c.port] !== undefined) {
      fail('duplicate port ' + c.port + ' used by "' + seenPorts[c.port] + '" and "' + label + '"');
    } else {
      seenPorts[c.port] = label;
    }
  }

  if (c.deploy === true) {
    if (typeof c.deploy_path !== 'string' || !c.deploy_path) {
      fail(label + ': deploy=true requires a non-empty "deploy_path"');
    }
    if (typeof c.host !== 'string' || !c.host) {
      fail(label + ': deploy=true requires a non-empty "host"');
    }
  }

  if (!Array.isArray(c.systemd_units)) {
    fail(label + ': "systemd_units" must be an array');
  } else {
    c.systemd_units.forEach(function (u, ui) {
      var uLabel = label + '.systemd_units[' + ui + ']';
      if (!isPlainObject(u)) {
        fail(uLabel + ': unit must be an object');
        return;
      }
      if (typeof u.name !== 'string' || !u.name) {
        fail(uLabel + ': missing/invalid "name"');
      }
      if (VALID_UNIT_TYPES.indexOf(u.type) === -1) {
        fail(uLabel + ': "type" must be one of ' + VALID_UNIT_TYPES.join('/') + ', got "' + u.type + '"');
      }
      if (u.scope !== undefined && VALID_UNIT_SCOPES.indexOf(u.scope) === -1) {
        fail(uLabel + ': "scope" must be one of ' + VALID_UNIT_SCOPES.join('/') + ', got "' + u.scope + '"');
      }
    });
  }
});

if (data.nodes !== undefined) {
  if (!Array.isArray(data.nodes)) {
    fail('top-level "nodes" must be an array when present');
  } else {
    var seenNodeNames = {};
    data.nodes.forEach(function (n, i) {
      var label = '(nodes index ' + i + ')';
      if (!isPlainObject(n)) {
        fail(label + ': node must be an object');
        return;
      }
      label = (typeof n.name === 'string' && n.name) ? n.name : label;
      if (typeof n.name !== 'string' || !n.name) {
        fail(label + ': missing/invalid required field "name" (non-empty string)');
      }
      if (typeof n.hostname !== 'string' && n.hostname !== null) {
        fail(label + ': field "hostname" must be a string or null');
      }
      if (n.name && seenNodeNames[n.name]) {
        fail('duplicate node name: "' + n.name + '"');
      } else if (n.name) {
        seenNodeNames[n.name] = true;
      }
    });
  }
}

printAndExit();

function printAndExit() {
  if (errors.length > 0) {
    console.error('services.json validation FAILED (' + errors.length + ' issue(s)):');
    errors.forEach(function (e) { console.error('  - ' + e); });
    process.exit(1);
  }
  console.log('services.json OK: ' + data.components.length + ' component(s)' +
    (Array.isArray(data.nodes) ? ', ' + data.nodes.length + ' node(s)' : '') + ' — no consistency issues found');
  process.exit(0);
}
