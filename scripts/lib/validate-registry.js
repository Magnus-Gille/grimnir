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
var VALID_TIMER_SEMANTICS = ['recurring', 'one-shot'];
var VALID_UNIT_NAME = /^[A-Za-z0-9_.@-]+$/;
var VALID_COMPONENT_ID = /^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$/;
var VALID_HOST = /^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/;
var VALID_ABSOLUTE_PATH = /^\/[A-Za-z0-9._@%+,=:\/-]+$/;
var INVALID_RSYNC_EXCLUDE_CHARS = /[\x00-\x1f*?[\]{}\\]/;
var VALID_HEALTH_BOUNDARIES = ['host', 'network'];
var VALID_HEALTH_PATH = /^\/[A-Za-z0-9._~%+\/-]*$/;

function isWithinPath(candidate, parent) {
  if (parent === '/') return path.posix.isAbsolute(candidate);
  return candidate === parent || candidate.indexOf(parent + '/') === 0;
}

function normalizedRootExclude(value) {
  return path.posix.normalize(value).replace(/^\/+/, '').replace(/\/+$/, '');
}

function isCanonicalAbsolutePath(value) {
  return typeof value === 'string' && VALID_ABSOLUTE_PATH.test(value) && value !== '/' &&
    value.charAt(value.length - 1) !== '/' && path.posix.normalize(value) === value;
}

var seenNames = {};
var seenPorts = {};

data.components.forEach(function (c, i) {
  var label = '(index ' + i + ')';
  if (!isPlainObject(c)) {
    fail(label + ': component must be an object');
    return;
  }
  if (typeof c.name === 'string' && VALID_COMPONENT_ID.test(c.name)) {
    label = c.name;
  } else {
    fail(label + ': missing/invalid required field "name" (safe identifier)');
  }

  ['repo'].forEach(function (field) {
    if (typeof c[field] !== 'string' || !VALID_COMPONENT_ID.test(c[field])) {
      fail(label + ': missing/invalid required field "' + field + '" (safe identifier)');
    }
  });

  ['deploy', 'scan', 'needs_build'].forEach(function (field) {
    if (typeof c[field] !== 'boolean') {
      fail(label + ': field "' + field + '" must be a boolean');
    }
  });

  if (c.deploy_mode !== undefined && c.deploy_mode !== 'rsync' && c.deploy_mode !== 'git-pull') {
    fail(label + ': "deploy_mode" must be "rsync" or "git-pull" when present, got "' + c.deploy_mode + '"');
  }

  if (c.host !== null && (typeof c.host !== 'string' || !VALID_HOST.test(c.host))) {
    fail(label + ': field "host" must be a safe hostname/address or null');
  }
  if (c.port !== undefined && c.port !== null &&
      (!Number.isInteger(c.port) || c.port < 1 || c.port > 65535)) {
    fail(label + ': field "port" must be an integer from 1 through 65535 or null');
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

  if (c.deploy_path !== undefined && !isCanonicalAbsolutePath(c.deploy_path)) {
    fail(label + ': deploy_path must be a canonical absolute path below / with no trailing slash');
  }

  if (c.deploy === true) {
    if (typeof c.deploy_path !== 'string' || !c.deploy_path) {
      fail(label + ': deploy=true requires a non-empty "deploy_path"');
    }
    if (typeof c.host !== 'string' || !VALID_HOST.test(c.host)) {
      fail(label + ': deploy=true requires a non-empty "host"');
    }
  }

  var deployMode = c.deploy_mode || 'rsync';
  var persistentPathsValid = true;
  var rsyncExcludesValid = true;

  if (c.persistent_paths !== undefined && !Array.isArray(c.persistent_paths)) {
    fail(label + ': "persistent_paths" must be an array when present');
    persistentPathsValid = false;
  }
  if (c.rsync_excludes !== undefined && !Array.isArray(c.rsync_excludes)) {
    fail(label + ': "rsync_excludes" must be an array when present');
    rsyncExcludesValid = false;
  }
  if (c.deploy === true && deployMode === 'rsync' && !Array.isArray(c.persistent_paths)) {
    fail(label + ': rsync deploy requires an explicit "persistent_paths" array (use [] only after auditing runtime writes)');
    persistentPathsValid = false;
  }

  var persistentPaths = persistentPathsValid && Array.isArray(c.persistent_paths) ? c.persistent_paths : [];
  persistentPaths.forEach(function (persistentPath, pi) {
    if (!isCanonicalAbsolutePath(persistentPath)) {
      fail(label + '.persistent_paths[' + pi + ']: must be a canonical absolute path below / with no trailing slash');
      persistentPathsValid = false;
    }
  });

  var rsyncExcludes = rsyncExcludesValid && Array.isArray(c.rsync_excludes) ? c.rsync_excludes : [];
  rsyncExcludes.forEach(function (exclude, ei) {
    if (typeof exclude !== 'string' || exclude.length < 2 || exclude.charAt(0) !== '/' ||
        exclude === '/' || INVALID_RSYNC_EXCLUDE_CHARS.test(exclude) || exclude.indexOf('//') !== -1 ||
        exclude.split('/').indexOf('..') !== -1 || exclude.split('/').indexOf('.') !== -1) {
      fail(label + '.rsync_excludes[' + ei + ']: must be a literal, root-anchored rsync path such as "/data/"');
      rsyncExcludesValid = false;
    }
  });

  if (c.deploy === true && deployMode === 'rsync' && typeof c.deploy_path === 'string' &&
      c.deploy_path && persistentPathsValid && rsyncExcludesValid) {
    var normalizedDeployPath = path.posix.normalize(c.deploy_path);
    var normalizedExcludes = rsyncExcludes.map(normalizedRootExclude);
    persistentPaths.forEach(function (persistentPath) {
      if (!isWithinPath(persistentPath, normalizedDeployPath)) return;
      if (persistentPath === normalizedDeployPath) {
        fail(label + ': persistent path equals rsync deploy_path and cannot be protected by a child exclusion: ' + persistentPath);
        return;
      }
      var relativePath = path.posix.relative(normalizedDeployPath, persistentPath);
      var protectedByExclude = normalizedExcludes.some(function (exclude) {
        return relativePath === exclude || relativePath.indexOf(exclude + '/') === 0;
      });
      if (!protectedByExclude) {
        fail(label + ': persistent path inside rsync deploy_path must be covered by rsync_excludes: ' +
          persistentPath + ' (expected a root-anchored exclusion for /' + relativePath + ')');
      }
    });
  }

  if (c.systemd_runtime !== undefined) {
    var runtime = c.systemd_runtime;
    if (!isPlainObject(runtime)) {
      fail(label + ': "systemd_runtime" must be an object when present');
    } else {
      if (c.deploy !== true || deployMode !== 'rsync') {
        fail(label + ': "systemd_runtime" is only supported for deploy=true rsync components');
      }
      if (typeof runtime.user !== 'string' || !/^[a-z_][a-z0-9_-]*$/.test(runtime.user)) {
        fail(label + '.systemd_runtime.user: must be a safe POSIX account name');
      }
      ['home', 'deploy_target'].forEach(function (field) {
        if (!isCanonicalAbsolutePath(runtime[field])) {
          fail(label + '.systemd_runtime.' + field + ': must be a canonical absolute path below /');
        }
      });
      if (typeof runtime.deploy_target === 'string' && runtime.deploy_target !== c.deploy_path) {
        fail(label + '.systemd_runtime.deploy_target: must exactly match deploy_path');
      }
      if (isCanonicalAbsolutePath(runtime.home) && isCanonicalAbsolutePath(runtime.deploy_target) &&
          !isWithinPath(runtime.deploy_target, runtime.home)) {
        fail(label + '.systemd_runtime.deploy_target: must be within the registered runtime home');
      }

      ['environment_files', 'sandbox_paths'].forEach(function (field) {
        if (!Array.isArray(runtime[field])) {
          fail(label + '.systemd_runtime.' + field + ': must be an explicit array');
          return;
        }
        runtime[field].forEach(function (runtimePath, ri) {
          if (!isCanonicalAbsolutePath(runtimePath)) {
            fail(label + '.systemd_runtime.' + field + '[' + ri + ']: must be a canonical absolute path below /');
          }
        });
      });

      if (Array.isArray(runtime.environment_files) && isCanonicalAbsolutePath(runtime.deploy_target)) {
        runtime.environment_files.forEach(function (environmentFile) {
          if (isCanonicalAbsolutePath(environmentFile) &&
              !isWithinPath(environmentFile, runtime.deploy_target)) {
            fail(label + '.systemd_runtime.environment_files: private environment files must live within deploy_target');
          }
        });
      }
      if (Array.isArray(runtime.sandbox_paths) && isCanonicalAbsolutePath(runtime.deploy_target)) {
        runtime.sandbox_paths.forEach(function (sandboxPath) {
          if (!isCanonicalAbsolutePath(sandboxPath)) return;
          var registered = isWithinPath(sandboxPath, runtime.deploy_target) ||
            persistentPaths.some(function (persistentPath) {
              return isCanonicalAbsolutePath(persistentPath) && isWithinPath(sandboxPath, persistentPath);
            });
          if (!registered) {
            fail(label + '.systemd_runtime.sandbox_paths: path must be within deploy_target or persistent_paths: ' +
              sandboxPath);
          }
        });
      }
      if (!isPlainObject(c.health_check)) {
        fail(label + ': systemd_runtime requires an explicit "health_check" object');
      }
    }
  }

  if (c.health_check !== undefined) {
    if (!isPlainObject(c.health_check)) {
      fail(label + ': "health_check" must be an object when present');
    } else {
      if (VALID_HEALTH_BOUNDARIES.indexOf(c.health_check.boundary) === -1) {
        fail(label + '.health_check.boundary: must be one of ' + VALID_HEALTH_BOUNDARIES.join('/'));
      }
      if (!Array.isArray(c.health_check.paths) || c.health_check.paths.length === 0) {
        fail(label + '.health_check.paths: must be a non-empty array');
      } else {
        c.health_check.paths.forEach(function (healthPath, hi) {
          if (typeof healthPath !== 'string' || !VALID_HEALTH_PATH.test(healthPath) ||
              healthPath.indexOf('//') !== -1) {
            fail(label + '.health_check.paths[' + hi + ']: must be a safe absolute HTTP path');
          }
        });
      }
      if (!Number.isInteger(c.port) || c.port < 1 || c.port > 65535) {
        fail(label + ': health_check requires a registered port');
      }
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
      } else if (!VALID_UNIT_NAME.test(u.name)) {
        fail(uLabel + ': "name" must be a valid systemd unit base name, got "' + u.name + '"');
      }
      if (VALID_UNIT_TYPES.indexOf(u.type) === -1) {
        fail(uLabel + ': "type" must be one of ' + VALID_UNIT_TYPES.join('/') + ', got "' + u.type + '"');
      }
      if (u.scope !== undefined && VALID_UNIT_SCOPES.indexOf(u.scope) === -1) {
        fail(uLabel + ': "scope" must be one of ' + VALID_UNIT_SCOPES.join('/') + ', got "' + u.scope + '"');
      }
      if (u.timer_semantics !== undefined) {
        if (u.type !== 'timer') {
          fail(uLabel + ': "timer_semantics" is only valid for timer units');
        } else if (VALID_TIMER_SEMANTICS.indexOf(u.timer_semantics) === -1) {
          fail(uLabel + ': "timer_semantics" must be one of ' + VALID_TIMER_SEMANTICS.join('/') +
            ', got "' + u.timer_semantics + '"');
        }
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
