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

var VALID_REPOSITORY_PART = /^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$/;

if (data.repository_authority !== undefined && !isPlainObject(data.repository_authority)) {
  fail('top-level "repository_authority" must be an object when present');
} else if (isPlainObject(data.repository_authority)) {
  var authority = data.repository_authority;
  if (typeof authority.default_owner !== 'string' ||
      !VALID_REPOSITORY_PART.test(authority.default_owner)) {
    fail('repository_authority.default_owner must be a safe GitHub owner');
  }
  if (!isPlainObject(authority.owner_overrides)) {
    fail('repository_authority.owner_overrides must be an object');
  } else {
    Object.keys(authority.owner_overrides).forEach(function (repo) {
      if (!VALID_REPOSITORY_PART.test(repo) ||
          typeof authority.owner_overrides[repo] !== 'string' ||
          !VALID_REPOSITORY_PART.test(authority.owner_overrides[repo])) {
        fail('repository_authority.owner_overrides must map safe repo names to safe GitHub owners');
      }
    });
  }
  if (authority.checkout_overrides !== undefined) {
    fail('repository_authority.checkout_overrides is not supported; canonical checkout names equal repository names');
  }
  if (!Array.isArray(authority.additional_repositories)) {
    fail('repository_authority.additional_repositories must be an array');
  } else {
    var seenAuthorityCheckouts = new Set();
    data.components.forEach(function (component) {
      if (isPlainObject(component) && typeof component.repo === 'string') {
        if (seenAuthorityCheckouts.has(component.repo)) {
          fail('duplicate repository-authority checkout: "' + component.repo + '"');
        }
        seenAuthorityCheckouts.add(component.repo);
      }
    });
    authority.additional_repositories.forEach(function (entry, i) {
      var label = 'repository_authority.additional_repositories[' + i + ']';
      if (!isPlainObject(entry)) {
        fail(label + ' must be an object');
        return;
      }
      ['repo', 'checkout'].forEach(function (field) {
        if (typeof entry[field] !== 'string' || !VALID_REPOSITORY_PART.test(entry[field])) {
          fail(label + '.' + field + ' must be a safe repository/directory name');
        }
      });
      if (typeof entry.checkout === 'string') {
        if (seenAuthorityCheckouts.has(entry.checkout)) {
          fail('duplicate repository-authority checkout: "' + entry.checkout + '"');
        }
        seenAuthorityCheckouts.add(entry.checkout);
      }
    });
  }
}

var VALID_UNIT_TYPES = ['service', 'timer'];
var VALID_UNIT_SCOPES = ['system', 'user'];
var VALID_TIMER_SEMANTICS = ['recurring', 'one-shot'];
var VALID_UNIT_FIELDS = ['name', 'type', 'scope', 'timer_semantics', 'service_name', 'boot_enable'];
var VALID_RUNTIME_STATES = ['active', 'stopped', 'not-applicable'];
var VALID_UNIT_NAME = /^[A-Za-z0-9_.@-]+$/;
var VALID_COMPONENT_ID = /^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$/;
var VALID_PLACEMENT_ID = /^[a-z][a-z0-9-]{2,62}$/;
var VALID_HOST = /^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/;
var VALID_ABSOLUTE_PATH = /^\/[A-Za-z0-9._@%+,=:\/-]+$/;
var INVALID_RSYNC_EXCLUDE_CHARS = /[\x00-\x1f*?[\]{}\\]/;
var VALID_HEALTH_BOUNDARIES = ['host', 'network'];
var VALID_HEALTH_PATH = /^\/[A-Za-z0-9._~%+\/-]*$/;
// Placement is an additive registry extension. Legacy registry consumers may
// still validate inventories that predate node/workload IDs; once any node ID
// is declared, the complete desired-placement graph is required.
var placementEnabled = Array.isArray(data.nodes) && data.nodes.some(function (node) {
  return isPlainObject(node) && node.node_id !== undefined;
});

function isSafeHealthHostname(value) {
  return typeof value === 'string' && VALID_HOST.test(value) && /[A-Za-z]/.test(value);
}

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

function validateUnits(units, label) {
  units.forEach(function (u, ui) {
    var uLabel = label + '.systemd_units[' + ui + ']';
    if (!isPlainObject(u)) {
      fail(uLabel + ': unit must be an object');
      return;
    }
    Object.keys(u).forEach(function (field) {
      if (VALID_UNIT_FIELDS.indexOf(field) === -1) {
        fail(uLabel + ': unknown field "' + field + '" (fail-closed: only ' +
          VALID_UNIT_FIELDS.join('/') + ' are allowed)');
      }
    });
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
    if (u.service_name !== undefined) {
      if (u.type !== 'timer') {
        fail(uLabel + ': "service_name" is only valid for timer units');
      } else if (typeof u.service_name !== 'string' || !VALID_UNIT_NAME.test(u.service_name)) {
        fail(uLabel + ': "service_name" must be a valid systemd service base name');
      }
    }
    if (u.boot_enable !== undefined) {
      if (u.type !== 'service') {
        fail(uLabel + ': "boot_enable" is only valid for service units (timers are enabled via their own timer path)');
      } else if (typeof u.boot_enable !== 'boolean') {
        fail(uLabel + ': "boot_enable" must be a boolean when present, got "' + u.boot_enable + '"');
      }
    }
  });
}

var seenNames = new Set();
var seenPorts = new Map();
var seenWorkloadIds = new Set();

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

  if (placementEnabled) {
    if (typeof c.workload_id !== 'string' || !VALID_PLACEMENT_ID.test(c.workload_id)) {
      fail(label + ': missing/invalid required field "workload_id" (stable public-safe id)');
    } else if (seenWorkloadIds.has(c.workload_id)) {
      fail('duplicate workload_id: "' + c.workload_id + '"');
    } else {
      seenWorkloadIds.add(c.workload_id);
    }
    if (!isPlainObject(c.workload_contract) ||
        Object.keys(c.workload_contract).length !== 4 ||
        c.workload_contract.kind !== 'workload-requirement' ||
        ['v1', 'v2'].indexOf(c.workload_contract.schema_version) === -1 ||
        c.workload_contract.producer !== c.repo ||
        typeof c.workload_contract.digest !== 'string' ||
        !/^sha256:[a-f0-9]{64}$/.test(c.workload_contract.digest)) {
      fail(label + ': workload_contract must exactly pin workload-requirement v1 or v2, its owning repo producer, and SHA-256 digest');
    }
  }

  ['deploy', 'scan', 'needs_build'].forEach(function (field) {
    if (typeof c[field] !== 'boolean') {
      fail(label + ': field "' + field + '" must be a boolean');
    }
  });

  if (c.desired_runtime_state !== undefined &&
      VALID_RUNTIME_STATES.indexOf(c.desired_runtime_state) === -1) {
    fail(label + ': "desired_runtime_state" must be one of ' +
      VALID_RUNTIME_STATES.join('/') + ', got "' + c.desired_runtime_state + '"');
  }

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

  if (c.name && seenNames.has(c.name)) {
    fail('duplicate component name: "' + c.name + '"');
  } else if (c.name) {
    seenNames.add(c.name);
  }

  if (typeof c.port === 'number') {
    if (seenPorts.has(c.port)) {
      fail('duplicate port ' + c.port + ' used by "' + seenPorts.get(c.port) + '" and "' + label + '"');
    } else {
      seenPorts.set(c.port, label);
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

  // Explicit allowlist for byte-for-byte units whose EnvironmentFile must
  // live outside the registry deploy_path (e.g. an owner-managed credential
  // file that deliberately never enters the repository). Undeclared external
  // files still fail the deploy containment guard (issue #200); declaration
  // is exact-path, never a prefix or glob.
  if (c.external_environment_files !== undefined) {
    if (!Array.isArray(c.external_environment_files)) {
      fail(label + ': "external_environment_files" must be an array when present');
    } else {
      c.external_environment_files.forEach(function (allowedPath, ai) {
        if (!isCanonicalAbsolutePath(allowedPath)) {
          fail(label + '.external_environment_files[' + ai + ']: must be a canonical absolute path below / with no trailing slash');
        }
      });
      if (c.systemd_runtime !== undefined) {
        fail(label + ': "external_environment_files" is only valid without "systemd_runtime" (rendered units declare environment files via systemd_runtime.environment_files)');
      }
    }
  }

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
          if (!isCanonicalAbsolutePath(environmentFile)) return;
          var registered = isWithinPath(environmentFile, runtime.deploy_target) ||
            persistentPaths.some(function (persistentPath) {
              return isCanonicalAbsolutePath(persistentPath) &&
                isWithinPath(environmentFile, persistentPath);
            });
          if (!registered) {
            fail(label + '.systemd_runtime.environment_files: private environment files must live within ' +
              'deploy_target or persistent_paths');
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
      if (c.health_check.boundary === 'network') {
        if (!isSafeHealthHostname(c.health_check.host)) {
          fail(label + '.health_check.host: network boundary requires an explicit safe hostname, not an IP locator');
        }
      } else if (c.health_check.host !== undefined) {
        fail(label + '.health_check.host: is only valid for the network boundary');
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
    if (c.desired_runtime_state === 'not-applicable' &&
        (c.systemd_units.length > 0 || (c.port !== undefined && c.port !== null))) {
      fail(label + ': desired_runtime_state "not-applicable" cannot declare systemd units or a health port');
    }
    validateUnits(c.systemd_units, label);
  }
});

if (data.nodes !== undefined) {
  if (!Array.isArray(data.nodes)) {
    fail('top-level "nodes" must be an array when present');
  } else {
    var seenNodeNames = new Set();
    var seenNodeIds = new Set();
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
      if (placementEnabled && (typeof n.node_id !== 'string' || !VALID_PLACEMENT_ID.test(n.node_id))) {
        fail(label + ': missing/invalid required field "node_id" (stable public-safe id)');
      } else if (placementEnabled && seenNodeIds.has(n.node_id)) {
        fail('duplicate node_id: "' + n.node_id + '"');
      } else if (placementEnabled) {
        seenNodeIds.add(n.node_id);
      }
      if (typeof n.hostname !== 'string' && n.hostname !== null) {
        fail(label + ': field "hostname" must be a string or null');
      }
      if (n.name && seenNodeNames.has(n.name)) {
        fail('duplicate node name: "' + n.name + '"');
      } else if (n.name) {
        seenNodeNames.add(n.name);
      }
    });
    if (placementEnabled) data.components.forEach(function (component) {
      if (!isPlainObject(component)) return;
      var target = component.target_node_id;
      if (component.host === null) {
        if (target !== undefined && target !== null) {
          fail(component.name + ': hostless component cannot declare target_node_id');
        }
        return;
      }
      if (typeof target !== 'string' || !VALID_PLACEMENT_ID.test(target)) {
        fail(component.name + ': host requires a stable target_node_id');
        return;
      }
      var node = data.nodes.filter(function (candidate) { return isPlainObject(candidate) && candidate.node_id === target; })[0];
      if (!node) {
        fail(component.name + ': target_node_id does not reference a registered node: ' + target);
      } else if (node.hostname !== component.host) {
        fail(component.name + ': target_node_id hostname must exactly match component host');
      }
    });
  }
}

// Owning-repository deployments are an additive registry extension for
// runtimes whose deploy entry point lives in the owning repository and is
// intentionally outside the centrally deployable component set. They are not
// components: they carry no workload_contract, placement evidence, rsync
// target or deploy=true flag, so scripts/deploy.sh never selects them. They
// exist so /deploy can find the owning repository's command and run it only
// through scripts/guarded-deploy.sh. See docs/deployment-source-binding.md.
var OWNING_DEPLOYMENT_FIELDS = ['name', 'repo', 'target_node_id', 'command', 'revision_argument',
  'release_root', 'deployed_marker', 'loopback_port', 'systemd_units', 'coupled_state'];
var COUPLED_STATE_FIELDS = ['node_id', 'home_relative_path', 'fields'];
var VALID_REPO_COMMAND = /^\.\/(?:[A-Za-z0-9._-]+\/)*[A-Za-z0-9._-]+$/;
var VALID_COMMAND_ARG = /^[A-Za-z0-9._@%+,=:\/-]+$/;
var VALID_REVISION_ARGUMENT = /^--[a-z][a-z0-9-]*$/;
var VALID_RELATIVE_PATH = /^[A-Za-z0-9._@%+,=-]+(?:\/[A-Za-z0-9._@%+,=-]+)*$/;
var VALID_STATE_FIELD = /^[a-z][a-z0-9_]*$/;

if (data.owning_repo_deployments !== undefined) {
  validateOwningRepoDeployments(data.owning_repo_deployments);
}

function validateOwningRepoDeployments(entries) {
  if (!Array.isArray(entries)) {
    fail('top-level "owning_repo_deployments" must be an array when present');
    return;
  }
  var knownRepos = new Set();
  var componentNames = new Set();
  // port -> component name (components own a port globally, as in the
  // component duplicate-port check above)
  var componentPorts = new Map();
  // "<target_node_id>:<port>" -> owning deployment name
  var owningPorts = new Map();
  data.components.forEach(function (component) {
    if (!isPlainObject(component)) return;
    if (typeof component.repo === 'string') knownRepos.add(component.repo);
    if (typeof component.name === 'string') componentNames.add(component.name);
    if (typeof component.port === 'number') componentPorts.set(component.port, component.name);
  });
  if (isPlainObject(data.repository_authority) &&
      Array.isArray(data.repository_authority.additional_repositories)) {
    data.repository_authority.additional_repositories.forEach(function (entry) {
      if (isPlainObject(entry) && typeof entry.repo === 'string') knownRepos.add(entry.repo);
    });
  }
  var nodeIds = new Set();
  if (Array.isArray(data.nodes)) {
    data.nodes.forEach(function (node) {
      if (isPlainObject(node) && typeof node.node_id === 'string') nodeIds.add(node.node_id);
    });
  }

  var seen = new Set();
  entries.forEach(function (entry, i) {
    var label = 'owning_repo_deployments[' + i + ']';
    if (!isPlainObject(entry)) {
      fail(label + ': entry must be an object');
      return;
    }
    if (typeof entry.name === 'string' && VALID_COMPONENT_ID.test(entry.name)) {
      label = 'owning_repo_deployments.' + entry.name;
      if (seen.has(entry.name)) fail('duplicate owning_repo_deployments name: "' + entry.name + '"');
      seen.add(entry.name);
      if (componentNames.has(entry.name)) {
        fail(label + ': name collides with a component name');
      }
    } else {
      fail(label + ': missing/invalid required field "name" (safe identifier)');
    }
    Object.keys(entry).forEach(function (field) {
      if (OWNING_DEPLOYMENT_FIELDS.indexOf(field) === -1) {
        fail(label + ': unknown field "' + field + '" (fail-closed: only ' +
          OWNING_DEPLOYMENT_FIELDS.join('/') + ' are allowed)');
      }
    });

    if (typeof entry.repo !== 'string' || !VALID_COMPONENT_ID.test(entry.repo)) {
      fail(label + ': missing/invalid required field "repo" (safe identifier)');
    } else if (!knownRepos.has(entry.repo)) {
      fail(label + ': repo "' + entry.repo + '" is not a registered component or repository_authority repository');
    }

    if (typeof entry.target_node_id !== 'string' || !VALID_PLACEMENT_ID.test(entry.target_node_id)) {
      fail(label + ': missing/invalid required field "target_node_id" (stable public-safe id)');
    } else if (!nodeIds.has(entry.target_node_id)) {
      fail(label + ': target_node_id does not reference a registered node: ' + entry.target_node_id);
    }

    var revisionArgumentValid = typeof entry.revision_argument === 'string' &&
      VALID_REVISION_ARGUMENT.test(entry.revision_argument);
    if (!revisionArgumentValid) {
      fail(label + ': revision_argument must be a long option such as "--release"; the executor appends it and the full commit SHA to the command');
    }

    if (!Array.isArray(entry.command) || entry.command.length === 0) {
      fail(label + ': command must be a non-empty argv array whose first element is a repo-relative executable');
    } else {
      entry.command.forEach(function (arg, ci) {
        if (ci === 0) {
          if (typeof arg !== 'string' || !VALID_REPO_COMMAND.test(arg) ||
              arg.split('/').slice(1).some(function (part) { return part === '.' || part === '..'; })) {
            fail(label + '.command[0]: must be a "./"-prefixed repo-relative path with no "." or ".." segment');
          }
        } else if (typeof arg !== 'string' || !VALID_COMMAND_ARG.test(arg)) {
          fail(label + '.command[' + ci + ']: must be a literal argument without whitespace or shell metacharacters');
        } else if (revisionArgumentValid && arg === entry.revision_argument) {
          fail(label + '.command[' + ci + ']: must not repeat revision_argument; the executor supplies the revision');
        }
      });
    }

    ['release_root', 'deployed_marker'].forEach(function (field) {
      if (!isCanonicalAbsolutePath(entry[field])) {
        fail(label + '.' + field + ': must be a canonical absolute path below / with no trailing slash');
      }
    });
    if (isCanonicalAbsolutePath(entry.release_root) && isCanonicalAbsolutePath(entry.deployed_marker) &&
        isWithinPath(entry.deployed_marker, entry.release_root)) {
      fail(label + '.deployed_marker: must live outside release_root so a release directory cannot overwrite its own acceptance marker');
    }

    if (!Number.isInteger(entry.loopback_port) || entry.loopback_port < 1 || entry.loopback_port > 65535) {
      fail(label + ': loopback_port must be an integer from 1 through 65535');
    } else {
      if (componentPorts.has(entry.loopback_port)) {
        fail(label + ': loopback_port ' + entry.loopback_port + ' is already registered to component "' +
          componentPorts.get(entry.loopback_port) + '"');
      }
      if (typeof entry.target_node_id === 'string') {
        var portKey = entry.target_node_id + ':' + entry.loopback_port;
        if (owningPorts.has(portKey)) {
          fail(label + ': loopback_port ' + entry.loopback_port + ' on ' + entry.target_node_id +
            ' is already registered to owning deployment "' + owningPorts.get(portKey) + '"');
        } else {
          owningPorts.set(portKey, typeof entry.name === 'string' ? entry.name : label);
        }
      }
    }

    if (!Array.isArray(entry.systemd_units) || entry.systemd_units.length === 0) {
      fail(label + ': systemd_units must be a non-empty array');
    } else {
      validateUnits(entry.systemd_units, label);
    }

    if (entry.coupled_state !== undefined) {
      if (!Array.isArray(entry.coupled_state)) {
        fail(label + ': coupled_state must be an array when present');
      } else {
        entry.coupled_state.forEach(function (state, si) {
          var sLabel = label + '.coupled_state[' + si + ']';
          if (!isPlainObject(state)) {
            fail(sLabel + ': must be an object');
            return;
          }
          Object.keys(state).forEach(function (field) {
            if (COUPLED_STATE_FIELDS.indexOf(field) === -1) {
              fail(sLabel + ': unknown field "' + field + '" (fail-closed: only ' +
                COUPLED_STATE_FIELDS.join('/') + ' are allowed)');
            }
          });
          if (typeof state.node_id !== 'string' || !nodeIds.has(state.node_id)) {
            fail(sLabel + '.node_id: must reference a registered node');
          }
          if (typeof state.home_relative_path !== 'string' ||
              !VALID_RELATIVE_PATH.test(state.home_relative_path) ||
              state.home_relative_path.split('/').some(function (part) { return part === '.' || part === '..'; })) {
            fail(sLabel + '.home_relative_path: must be a relative path below the node user home with no "." or ".." segment');
          }
          if (!Array.isArray(state.fields) || state.fields.length === 0 ||
              !state.fields.every(function (field) { return typeof field === 'string' && VALID_STATE_FIELD.test(field); })) {
            fail(sLabel + '.fields: must be a non-empty array of field names the rollout updates');
          }
        });
      }
    }
  });
}

printAndExit();

function printAndExit() {
  if (errors.length > 0) {
    console.error('services.json validation FAILED (' + errors.length + ' issue(s)):');
    errors.forEach(function (e) { console.error('  - ' + e); });
    process.exit(1);
  }
  console.log('services.json OK: ' + data.components.length + ' component(s)' +
    (Array.isArray(data.nodes) ? ', ' + data.nodes.length + ' node(s)' : '') +
    (Array.isArray(data.owning_repo_deployments) ? ', ' + data.owning_repo_deployments.length + ' owning-repo deployment(s)' : '') +
    ' — no consistency issues found');
  process.exit(0);
}
