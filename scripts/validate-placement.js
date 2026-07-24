#!/usr/bin/env node
// validate-placement.js — deterministic desired-vs-observed placement view.
//
// This is deliberately a read-only consumer. services.json supplies desired
// placement only; the caller must supply a captured Brokkr observation. It
// never opens a network connection or derives liveness from desired config.

var fs = require('fs');
var path = require('path');
var canonicalEvidence = require('./lib/canonical-evidence.js');
var schemaSubset = require('./lib/json-schema-subset.js');

var args = process.argv.slice(2);
function option(name) {
  var index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
}
function usage() {
  console.error('Usage: node scripts/validate-placement.js --registry services.json --observation brokkr-observation.json --now YYYY-MM-DDTHH:MM:SSZ');
  process.exit(2);
}
var registryPath = option('--registry');
var observationPath = option('--observation');
var nowText = option('--now');
if (!registryPath || !observationPath || !nowText || args.length !== 6) usage();

function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (error) { throw new Error('cannot read valid JSON from ' + file + ': ' + error.message); }
}
function plain(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function own(object, key) { return Object.prototype.hasOwnProperty.call(object, key); }
function exact(object, fields, label, errors) {
  if (!plain(object)) { errors.push(label + ' must be an object'); return false; }
  fields.forEach(function (field) { if (!own(object, field)) errors.push(label + '.' + field + ' is required'); });
  Object.keys(object).forEach(function (field) { if (fields.indexOf(field) === -1) errors.push(label + '.' + field + ' is not a v1 field'); });
  return true;
}
var ID = /^[a-z][a-z0-9-]{2,62}$/;
var DIGEST = /^sha256:[a-f0-9]{64}$/;
var SAFE_HOST = /^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/;
var UTC = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
function instant(value) {
  if (typeof value !== 'string') return NaN;
  var match = UTC.exec(value);
  if (!match) return NaN;
  var parsed = Date.parse(value);
  if (Number.isNaN(parsed)) return NaN;
  var date = new Date(parsed);
  return date.getUTCFullYear() === Number(match[1]) && date.getUTCMonth() + 1 === Number(match[2]) &&
    date.getUTCDate() === Number(match[3]) && date.getUTCHours() === Number(match[4]) &&
    date.getUTCMinutes() === Number(match[5]) && date.getUTCSeconds() === Number(match[6]) ? parsed : NaN;
}
function naturalCompare(left, right) {
  var a = String(left).match(/\d+|\D+/g) || [];
  var b = String(right).match(/\d+|\D+/g) || [];
  for (var index = 0; index < Math.min(a.length, b.length); index += 1) {
    if (a[index] === b[index]) continue;
    var aNumber = /^\d+$/.test(a[index]);
    var bNumber = /^\d+$/.test(b[index]);
    if (aNumber && bNumber) {
      var aSignificant = a[index].replace(/^0+/, '') || '0';
      var bSignificant = b[index].replace(/^0+/, '') || '0';
      if (aSignificant.length !== bSignificant.length) return aSignificant.length - bSignificant.length;
      if (aSignificant !== bSignificant) return aSignificant < bSignificant ? -1 : 1;
      if (a[index].length !== b[index].length) return a[index].length - b[index].length;
    }
    return a[index] < b[index] ? -1 : 1;
  }
  return a.length - b.length;
}
function fail(errors) {
  if (!errors.length) return;
  console.error('placement validation FAILED (' + errors.length + ' issue(s)):');
  errors.forEach(function (error) { console.error('  - ' + error); });
  process.exit(1);
}
function validateEvidence(evidence, observedAt, label, errors) {
  if (!exact(evidence, ['evidence_id', 'producer', 'observed_at', 'digest'], label, errors)) return;
  if (!ID.test(evidence.evidence_id || '')) errors.push(label + '.evidence_id must be a stable public-safe id');
  if (evidence.producer !== 'brokkr') errors.push(label + '.producer must be brokkr');
  if (evidence.observed_at !== observedAt || Number.isNaN(instant(evidence.observed_at))) errors.push(label + '.observed_at must exactly match its observation timestamp');
  if (!DIGEST.test(evidence.digest || '')) errors.push(label + '.digest must be a sha256 digest');
}
function validateEvidenceDigest(record, label, errors) {
  if (!plain(record) || !plain(record.evidence) || !DIGEST.test(record.evidence.digest || '')) return;
  var expected = canonicalEvidence.evidenceDigest(record);
  if (record.evidence.digest !== expected) {
    errors.push(label + '.evidence.digest mismatch: expected ' + expected);
  }
}
function validateNode(record, now, errors) {
  var fields = ['kind', 'schema_version', 'node_id', 'observed_at', 'valid_until', 'evidence', 'capability_status', 'architecture', 'resources', 'uptime_class', 'network_capabilities', 'logical_storage', 'service_manager', 'deployment_mechanisms', 'health_reporting', 'extensions'];
  if (!exact(record, fields, 'node-capability', errors)) return;
  if (record.kind !== 'node-capability' || record.schema_version !== 'v1') errors.push('node-capability must use the exact node/substrate v1 kind and version');
  if (!ID.test(record.node_id || '')) errors.push('node-capability.node_id must be a stable public-safe id');
  var observedAt = instant(record.observed_at); var validUntil = instant(record.valid_until);
  if (Number.isNaN(observedAt) || Number.isNaN(validUntil) || validUntil <= observedAt) errors.push('node-capability timestamps must be valid and increasing');
  if (!Number.isNaN(observedAt) && observedAt > now) errors.push('node-capability.observed_at must not be later than --now: ' + record.node_id);
  validateEvidence(record.evidence, record.observed_at, 'node-capability.evidence', errors);
  validateEvidenceDigest(record, 'node-capability', errors);
  if (['known', 'unknown', 'not_applicable'].indexOf(record.capability_status) === -1) errors.push('node-capability capability_status is invalid: ' + record.node_id);
  if (['arm64', 'x86_64', 'unknown', 'not_applicable'].indexOf(record.architecture) === -1) errors.push('node-capability architecture is invalid: ' + record.node_id);
  if (!exact(record.resources, ['cpu_cores', 'memory_mib'], 'node-capability.resources', errors) || !Number.isInteger(record.resources.cpu_cores) || record.resources.cpu_cores < 1 || !Number.isInteger(record.resources.memory_mib) || record.resources.memory_mib < 1) errors.push('node-capability.resources must contain positive numeric observed resources');
  if (['always_on', 'best_effort', 'unknown', 'not_applicable'].indexOf(record.uptime_class) === -1 || ['systemd', 'launchd', 'unknown', 'not_applicable'].indexOf(record.service_manager) === -1 || ['supported', 'unsupported', 'unknown', 'not_applicable'].indexOf(record.health_reporting) === -1) errors.push('node-capability contains an unsupported v1 capability enum');
  var networkValues = ['wired', 'wifi', 'tailnet', 'unknown', 'not_applicable'];
  if (!Array.isArray(record.network_capabilities) || !record.network_capabilities.length || new Set(record.network_capabilities).size !== record.network_capabilities.length || !record.network_capabilities.every(function (value) { return networkValues.indexOf(value) !== -1; })) errors.push('node-capability.network_capabilities must be a non-empty unique v1 array');
  if (!Array.isArray(record.logical_storage) || !record.logical_storage.length) errors.push('node-capability.logical_storage must be a non-empty v1 array');
  else record.logical_storage.forEach(function (storage) {
    if (!exact(storage, ['class', 'available_mib', 'status'], 'node-capability.logical_storage entry', errors) || ['local_ssd', 'external_ssd', 'network_share', 'unknown', 'not_applicable'].indexOf(storage.class) === -1 || !Number.isInteger(storage.available_mib) || storage.available_mib < 0 || ['known', 'unknown', 'not_applicable'].indexOf(storage.status) === -1) errors.push('node-capability.logical_storage entry must use exact v1 fields');
  });
  var mechanismValues = ['guarded_deploy', 'systemd', 'manual_operator', 'unknown', 'not_applicable'];
  if (!Array.isArray(record.deployment_mechanisms) || !record.deployment_mechanisms.length || new Set(record.deployment_mechanisms).size !== record.deployment_mechanisms.length || !record.deployment_mechanisms.every(function (value) { return mechanismValues.indexOf(value) !== -1; })) errors.push('node-capability.deployment_mechanisms must be a non-empty unique v1 array');
  var extensionIds = {};
  if (!Array.isArray(record.extensions) || !record.extensions.every(function (entry) { var valid = plain(entry) && Object.keys(entry).length === 3 && ID.test(entry.id || '') && /^v[1-9][0-9]*$/.test(entry.version || '') && entry.decision_effect === 'informational' && !extensionIds[entry.id]; extensionIds[entry.id] = true; return valid; })) errors.push('node-capability extensions must be unique and informational only');
}

function validateDesiredRegistry(registry, errors) {
  if (!plain(registry) || !Array.isArray(registry.components) || !Array.isArray(registry.nodes)) {
    errors.push('registry must provide components and nodes arrays');
    return;
  }
  var desiredNodes = {};
  registry.nodes.forEach(function (node, index) {
    var label = 'registry.nodes[' + index + ']';
    if (!plain(node)) { errors.push(label + ' must be an object'); return; }
    if (!ID.test(node.node_id || '')) errors.push(label + '.node_id must be a stable public-safe id');
    else if (desiredNodes[node.node_id]) errors.push('duplicate desired node_id: ' + node.node_id);
    else desiredNodes[node.node_id] = node;
    if (!(node.hostname === null || (typeof node.hostname === 'string' && node.hostname.length <= 253 &&
        SAFE_HOST.test(node.hostname)))) {
      errors.push(label + '.hostname must be null or a safe hostname/address');
    }
  });
  var componentNames = {};
  var workloadIds = {};
  var desiredPorts = {};
  registry.components.forEach(function (component, index) {
    var label = 'registry.components[' + index + ']';
    if (!plain(component)) { errors.push(label + ' must be an object'); return; }
    if (!ID.test(component.name || '')) errors.push(label + '.name must be a stable public-safe id');
    else if (componentNames[component.name]) errors.push('duplicate desired component name: ' + component.name);
    else componentNames[component.name] = true;
    if (!ID.test(component.repo || '')) errors.push(label + '.repo must be a stable public-safe id');
    if (!ID.test(component.workload_id || '')) errors.push(label + '.workload_id must be a stable public-safe id');
    else if (workloadIds[component.workload_id]) errors.push('duplicate desired workload_id: ' + component.workload_id);
    else workloadIds[component.workload_id] = true;
    if (typeof component.deploy !== 'boolean') errors.push(label + '.deploy must be boolean');
    if (own(component, 'desired_runtime_state') &&
        ['active', 'stopped', 'not-applicable'].indexOf(component.desired_runtime_state) === -1) {
      errors.push(label + '.desired_runtime_state is invalid');
    }
    if (!(component.port === null || component.port === undefined ||
        (Number.isInteger(component.port) && component.port >= 1 && component.port <= 65535))) {
      errors.push(label + '.port must be null or an integer from 1 through 65535');
    }
    if (typeof component.port === 'number') {
      var portOwner = desiredPorts[component.port];
      var portLabel = label + ' (' + (component.name || 'unnamed') + ')';
      if (portOwner !== undefined) {
        errors.push('duplicate desired port ' + component.port + ' used by ' + portOwner + ' and ' + portLabel);
      } else {
        desiredPorts[component.port] = portLabel;
      }
    }
    if (!(component.host === null || (typeof component.host === 'string' && component.host.length <= 253 &&
        SAFE_HOST.test(component.host)))) {
      errors.push(label + '.host must be null or a safe hostname/address');
    }
    if (component.host === null) {
      if (own(component, 'target_node_id') && component.target_node_id !== null) {
        errors.push(label + '.target_node_id is forbidden for a hostless workload');
      }
    } else if (!ID.test(component.target_node_id || '') || !desiredNodes[component.target_node_id]) {
      errors.push(label + '.target_node_id must reference a registered node');
    } else if (desiredNodes[component.target_node_id].hostname !== component.host) {
      errors.push(label + '.host and target node hostname disagree');
    }
    if (!Array.isArray(component.systemd_units)) {
      errors.push(label + '.systemd_units must be an array');
    } else {
      if (component.desired_runtime_state === 'not-applicable' &&
          (component.systemd_units.length || (component.port !== null && component.port !== undefined))) {
        errors.push(label + '.desired_runtime_state not-applicable cannot declare units or a port');
      }
      if (component.host === null &&
          (component.deploy !== false || component.desired_runtime_state !== 'not-applicable' ||
           component.systemd_units.length || (component.port !== null && component.port !== undefined))) {
        errors.push(label + ' hostless workload must be undeployed, not-applicable, and have no units or port');
      }
      var unitNames = {};
      component.systemd_units.forEach(function (unit, unitIndex) {
        var unitLabel = label + '.systemd_units[' + unitIndex + ']';
        if (!plain(unit)) { errors.push(unitLabel + ' must be an object'); return; }
        Object.keys(unit).forEach(function (field) {
          if (['name', 'type', 'scope', 'timer_semantics'].indexOf(field) === -1) {
            errors.push(unitLabel + '.' + field + ' is not a placement field');
          }
        });
        if (typeof unit.name !== 'string' || !/^[a-z0-9@._-]+$/.test(unit.name)) {
          errors.push(unitLabel + '.name must be a safe unit id');
        } else if (unitNames[unit.name]) {
          errors.push('duplicate desired unit for ' + component.workload_id + ': ' + unit.name);
        } else unitNames[unit.name] = true;
        if (['service', 'timer'].indexOf(unit.type) === -1) errors.push(unitLabel + '.type is invalid');
        if (own(unit, 'scope') && ['system', 'user'].indexOf(unit.scope) === -1) errors.push(unitLabel + '.scope is invalid');
        if (own(unit, 'timer_semantics') &&
            (unit.type !== 'timer' || ['recurring', 'one-shot'].indexOf(unit.timer_semantics) === -1)) {
          errors.push(unitLabel + '.timer_semantics is invalid');
        }
      });
    }
    var contract = component.workload_contract;
    if (!plain(contract) || Object.keys(contract).sort().join(',') !== 'digest,kind,producer,schema_version') {
      errors.push(label + '.workload_contract must contain the exact v1 provenance fields');
    } else {
      if (contract.kind !== 'workload-requirement' || contract.schema_version !== 'v1') {
        errors.push(label + '.workload_contract must use workload-requirement v1');
      }
      if (contract.producer !== component.repo) errors.push(label + '.workload_contract.producer must equal repo');
      if (!DIGEST.test(contract.digest || '')) errors.push(label + '.workload_contract.digest must be a sha256 digest');
    }
  });
}

var errors = [];
var now = instant(nowText);
if (Number.isNaN(now)) errors.push('--now must be a real UTC timestamp');
var registry; var observation;
try { registry = readJson(registryPath); } catch (error) { errors.push(error.message); }
try { observation = readJson(observationPath); } catch (error) { errors.push(error.message); }
var placementSchema; var nodeSchema; var runtimeSchema;
try {
  placementSchema = readJson(path.join(__dirname, '..', 'docs', 'placement-validation-v1.schema.json'));
  nodeSchema = readJson(path.join(__dirname, '..', 'docs', 'node-substrate-contract-v1.schema.json'));
  if (placementSchema.$id !== 'https://grimnir.gille.ai/contracts/placement-validation/v1/schema.json') {
    throw new Error('unexpected pinned placement schema identity');
  }
  if (nodeSchema.$id !== 'https://grimnir.gille.ai/contracts/node-substrate/v1/schema.json') {
    throw new Error('unexpected pinned node/substrate schema identity');
  }
  runtimeSchema = schemaSubset.createValidator({
    rootName: 'placement-validation-v1.schema.json',
    schemas: [
      { name: 'placement-validation-v1.schema.json', schema: placementSchema },
      { name: 'node-substrate-contract-v1.schema.json', schema: nodeSchema }
    ]
  });
} catch (error) {
  errors.push('tracked schema validation unavailable: ' + error.message);
}
validateDesiredRegistry(registry, errors);
if (!plain(observation)) errors.push('observation must be a JSON object');
if (!errors.length) {
  runtimeSchema.validate(observation).forEach(function (error) {
    errors.push('placement-validation-v1 schema: ' + error);
  });
}
if (!errors.length) {
  exact(observation, ['kind', 'schema_version', 'observation_id', 'observed_at', 'valid_until', 'evidence', 'node_capabilities', 'workloads', 'capability_assessments'], 'observation', errors);
  if (observation.kind !== 'brokkr-placement-observation' || observation.schema_version !== 'v1') errors.push('observation must use kind brokkr-placement-observation and schema_version v1');
  if (!ID.test(observation.observation_id || '')) errors.push('observation.observation_id must be a stable public-safe id');
  var topObservedAt = instant(observation.observed_at); var topValidUntil = instant(observation.valid_until);
  if (Number.isNaN(topObservedAt) || Number.isNaN(topValidUntil) || topValidUntil <= topObservedAt) errors.push('observation timestamps must be valid and increasing');
  if (!Number.isNaN(topObservedAt) && topObservedAt > now) errors.push('observation.observed_at must not be later than --now');
  validateEvidence(observation.evidence, observation.observed_at, 'observation.evidence', errors);
  validateEvidenceDigest(observation, 'observation', errors);
  ['node_capabilities', 'workloads', 'capability_assessments'].forEach(function (field) { if (!Array.isArray(observation[field])) errors.push('observation.' + field + ' must be an array'); });
}
if (!errors.length) {
  observation.node_capabilities.forEach(function (node) { validateNode(node, now, errors); });
  var seenEvidenceIds = {};
  seenEvidenceIds[observation.evidence.evidence_id] = true;
  var seenNodes = {};
  observation.node_capabilities.forEach(function (node) {
    if (node && seenNodes[node.node_id]) errors.push('duplicate observed node_id: ' + node.node_id);
    else if (node) seenNodes[node.node_id] = node;
    if (node && node.evidence) {
      if (seenEvidenceIds[node.evidence.evidence_id]) {
        errors.push('duplicate Brokkr evidence_id: ' + node.evidence.evidence_id);
      }
      seenEvidenceIds[node.evidence.evidence_id] = true;
    }
    if (node && (instant(node.observed_at) < topObservedAt ||
        instant(node.valid_until) > topValidUntil)) {
      errors.push('node-capability interval falls outside top-level observation: ' + node.node_id);
    }
  });
  var seenWorkloads = {};
  observation.workloads.forEach(function (workload, index) {
    var label = 'observation.workloads[' + index + ']';
    if (!exact(workload, ['workload_id', 'node_id', 'deployed', 'running', 'healthy', 'units'], label, errors)) return;
    if (!ID.test(workload.workload_id || '') || !ID.test(workload.node_id || '')) errors.push(label + ' IDs must be stable public-safe ids');
    if (['deployed', 'missing', 'unknown', 'not_applicable'].indexOf(workload.deployed) === -1) errors.push(label + '.deployed is invalid');
    if (['running', 'stopped', 'unknown', 'not_applicable'].indexOf(workload.running) === -1) errors.push(label + '.running is invalid');
    if (['healthy', 'unhealthy', 'unknown', 'not_applicable'].indexOf(workload.healthy) === -1) errors.push(label + '.healthy is invalid');
    if (!Array.isArray(workload.units) || !workload.units.every(function (unit) { return typeof unit === 'string' && /^[a-z0-9@._-]+$/.test(unit); }) || new Set(workload.units).size !== workload.units.length) errors.push(label + '.units must be unique safe unit ids');
    if (!seenNodes[workload.node_id]) errors.push(label + ' references unknown observed node: ' + workload.node_id);
    if (seenWorkloads[workload.workload_id]) errors.push('duplicate observed workload_id: ' + workload.workload_id); else seenWorkloads[workload.workload_id] = workload;
  });
  var assessments = {};
  observation.capability_assessments.forEach(function (assessment, index) {
    var label = 'observation.capability_assessments[' + index + ']';
    if (!exact(assessment, ['workload_id', 'node_id', 'requirement_kind', 'requirement_schema_version', 'requirement_producer', 'requirement_digest', 'compatibility'], label, errors)) return;
    if (!ID.test(assessment.workload_id || '') || !ID.test(assessment.node_id || '')) errors.push(label + ' IDs must be stable public-safe ids');
    if (assessment.requirement_kind !== 'workload-requirement' || assessment.requirement_schema_version !== 'v1' ||
        typeof assessment.requirement_producer !== 'string' || !ID.test(assessment.requirement_producer) ||
        !DIGEST.test(assessment.requirement_digest || '')) errors.push(label + ' must bind the exact workload-requirement v1 producer and digest');
    if (['compatible', 'incompatible', 'unknown'].indexOf(assessment.compatibility) === -1) errors.push(label + '.compatibility is invalid');
    if (!seenNodes[assessment.node_id]) errors.push(label + ' references unknown observed node: ' + assessment.node_id);
    var key = assessment.workload_id + '|' + assessment.node_id;
    if (assessments[key]) errors.push('duplicate capability assessment: ' + key); else assessments[key] = assessment;
  });
  registry.components.forEach(function (component) {
    if (!plain(component) || !component.target_node_id) return;
    var assessment = assessments[component.workload_id + '|' + component.target_node_id];
    if (!assessment) return;
    var contract = component.workload_contract;
    if (!plain(contract) || Object.keys(contract).length !== 4 ||
        contract.kind !== assessment.requirement_kind ||
        contract.schema_version !== assessment.requirement_schema_version ||
        contract.producer !== assessment.requirement_producer ||
        contract.digest !== assessment.requirement_digest) {
      errors.push('workload requirement provenance/digest mismatch: ' + component.workload_id);
    }
  });
}
fail(errors);

var desiredNodes = {};
registry.nodes.forEach(function (node) { if (plain(node) && ID.test(node.node_id || '')) desiredNodes[node.node_id] = node; });
var drift = []; var states = [];
function add(category, data) { drift.push(Object.assign({ category: category }, data)); }
observation.node_capabilities.forEach(function (node) {
  if (!desiredNodes[node.node_id]) {
    add('extra-node', { node_id: node.node_id, evidence_id: node.evidence.evidence_id });
  }
  if (instant(node.valid_until) <= now) {
    add('stale-evidence', { node_id: node.node_id, evidence_id: node.evidence.evidence_id });
  }
});
var desiredWorkloads = {};
registry.components.forEach(function (component, index) {
  if (!plain(component)) { add('missing-evidence', { detail: 'invalid desired component at index ' + index }); return; }
  var workloadId = component.workload_id;
  var targetNodeId = component.target_node_id;
  if (!ID.test(workloadId || '')) { add('missing-evidence', { detail: 'missing desired workload_id for ' + (component.name || index) }); return; }
  if (desiredWorkloads[workloadId]) { add('missing-evidence', { workload_id: workloadId, detail: 'duplicate desired workload id' }); return; }
  desiredWorkloads[workloadId] = component;
  if (component.host === null || component.host === undefined) {
    if (targetNodeId !== undefined && targetNodeId !== null) add('missing-evidence', { workload_id: workloadId, detail: 'hostless workload cannot declare target_node_id' });
    return;
  }
  if (!ID.test(targetNodeId || '') || !desiredNodes[targetNodeId]) { add('missing-evidence', { workload_id: workloadId, detail: 'desired target_node_id does not reference a registered node' }); return; }
  var target = desiredNodes[targetNodeId];
  if (target.hostname !== component.host) add('missing-evidence', { workload_id: workloadId, node_id: targetNodeId, detail: 'desired host and target node disagree' });
  if (!plain(component.workload_contract) || component.workload_contract.kind !== 'workload-requirement' ||
      component.workload_contract.schema_version !== 'v1' ||
      component.workload_contract.producer !== component.repo ||
      !DIGEST.test(component.workload_contract.digest || '') ||
      Object.keys(component.workload_contract).length !== 4) {
    add('missing-evidence', { workload_id: workloadId, detail: 'desired workload must exactly pin owner-published workload-requirement v1 provenance and digest' });
  }
  var node = observation.node_capabilities.filter(function (candidate) { return candidate.node_id === targetNodeId; })[0];
  if (!node) { add('missing-evidence', { workload_id: workloadId, node_id: targetNodeId, detail: 'no Brokkr node capability evidence' }); return; }
  if (node.capability_status !== 'known' || ['arm64', 'x86_64'].indexOf(node.architecture) === -1) add('incompatible-capability', { workload_id: workloadId, node_id: targetNodeId, compatibility: 'unknown', detail: 'node capability cannot drive placement' });
  var assessment = assessments[workloadId + '|' + targetNodeId];
  if (!assessment) add('missing-evidence', { workload_id: workloadId, node_id: targetNodeId, detail: 'no Brokkr capability assessment bound to the workload contract' });
  else if (assessment.compatibility !== 'compatible') add('incompatible-capability', { workload_id: workloadId, node_id: targetNodeId, compatibility: assessment.compatibility });
  var observed = seenWorkloads[workloadId];
  if (!observed) { add('missing-evidence', { workload_id: workloadId, node_id: targetNodeId, detail: 'no Brokkr workload observation' }); return; }
  if (observed.node_id !== targetNodeId) add('missing-workload', { workload_id: workloadId, node_id: targetNodeId, observed_node_id: observed.node_id, detail: 'workload observed away from desired target' });
  if (observed.deployed === 'missing') add('missing-workload', { workload_id: workloadId, node_id: targetNodeId, detail: 'Brokkr observed workload missing' });
  var desiredState = component.desired_runtime_state || 'active';
  var units = Array.isArray(component.systemd_units) ? component.systemd_units.map(function (unit) { return unit.name; }) : [];
  var deployedExpected = component.deploy === false ? 'not_applicable' : 'deployed';
  states.push({ workload_id: workloadId, node_id: targetNodeId, declared: { desired_runtime_state: desiredState, deployment: deployedExpected, units: units.sort(naturalCompare) }, deployed: observed.deployed, running: observed.running, healthy: observed.healthy });
  if (observed.deployed !== deployedExpected && !(component.deploy === false && observed.deployed === 'not_applicable')) add('deployment-state', { workload_id: workloadId, node_id: targetNodeId, expected: deployedExpected, observed: observed.deployed });
  var runningExpected = desiredState === 'active' ? 'running' : desiredState === 'stopped' ? 'stopped' : 'not_applicable';
  if (observed.running !== runningExpected) add('running-state', { workload_id: workloadId, node_id: targetNodeId, expected: runningExpected, observed: observed.running });
  var healthyExpected = desiredState === 'active' && component.port !== null && component.port !== undefined ? 'healthy' : 'not_applicable';
  if (observed.healthy !== healthyExpected) add('health-state', { workload_id: workloadId, node_id: targetNodeId, expected: healthyExpected, observed: observed.healthy });
  observed.units.forEach(function (unit) { if (units.indexOf(unit) === -1) add('extra-live-unit', { workload_id: workloadId, node_id: observed.node_id, unit_id: unit }); });
  units.forEach(function (unit) { if (observed.units.indexOf(unit) === -1) add('missing-live-unit', { workload_id: workloadId, node_id: observed.node_id, unit_id: unit }); });
});
observation.workloads.forEach(function (workload) {
  var desired = desiredWorkloads[workload.workload_id];
  if (desired && desired.target_node_id) return;
  add('extra-workload', { workload_id: workload.workload_id, node_id: workload.node_id });
  workload.units.forEach(function (unit) {
    add('extra-live-unit', { workload_id: workload.workload_id, node_id: workload.node_id, unit_id: unit });
  });
});
observation.capability_assessments.forEach(function (assessment) {
  var desired = desiredWorkloads[assessment.workload_id];
  if (!desired || desired.target_node_id !== assessment.node_id) {
    add('extra-assessment', { workload_id: assessment.workload_id, node_id: assessment.node_id });
  }
});
if (instant(observation.valid_until) <= now) add('stale-evidence', { evidence_id: observation.evidence.evidence_id, detail: 'placement observation expired' });

var categoryOrder = ['incompatible-capability', 'extra-node', 'extra-workload', 'extra-assessment', 'extra-live-unit', 'missing-live-unit', 'missing-workload', 'stale-evidence', 'missing-evidence', 'deployment-state', 'running-state', 'health-state'];
drift.sort(function (left, right) {
  var category = categoryOrder.indexOf(left.category) - categoryOrder.indexOf(right.category);
  if (category) return category;
  return naturalCompare(left.workload_id || left.node_id || left.evidence_id || '', right.workload_id || right.node_id || right.evidence_id || '') || naturalCompare(left.unit_id || '', right.unit_id || '');
});
states.sort(function (left, right) { return naturalCompare(left.workload_id, right.workload_id); });
process.stdout.write(JSON.stringify({ schema_version: 'v1', evaluated_at: nowText, compliant: drift.length === 0, states: states, drift: drift }) + '\n');
