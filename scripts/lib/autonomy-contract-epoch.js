'use strict';

var fs = require('fs');
var path = require('path');
var schemaSubset = require('./json-schema-subset.js');

var ROOT = path.resolve(__dirname, '../..');
var MAX_BYTES = 1000000;
var MAX_NODES = 10000;
var MAX_DEPTH = 64;
var EPOCHS = Object.freeze({
  v1: Object.freeze({
    constitutionSchema: 'docs/autonomy-constitution-v1.schema.json',
    coverageSchema: 'docs/autonomy-coverage-registry-v1.schema.json'
  }),
  v2: Object.freeze({
    constitutionSchema: 'docs/autonomy-constitution-v2.schema.json',
    coverageSchema: 'docs/autonomy-coverage-registry-v2.schema.json'
  })
});
var validators = {};

function plain(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function structuralLimit(value, label) {
  var pending = [{ value: value, depth: 0 }];
  var nodes = 0;
  while (pending.length) {
    var current = pending.pop();
    nodes += 1;
    if (nodes > MAX_NODES) throw new Error(label + ' exceeds ' + MAX_NODES + ' JSON nodes');
    if (current.depth > MAX_DEPTH) throw new Error(label + ' exceeds JSON depth ' + MAX_DEPTH);
    if (current.value !== null && typeof current.value === 'object') {
      Object.values(current.value).forEach(function (child) {
        pending.push({ value: child, depth: current.depth + 1 });
      });
    }
  }
}

function readBoundedJson(file, label) {
  var raw = fs.readFileSync(file, 'utf8');
  if (Buffer.byteLength(raw) > MAX_BYTES) throw new Error(label + ' exceeds 1 MiB');
  var value;
  try {
    value = JSON.parse(raw);
  } catch (error) {
    throw new Error(label + ' is not valid JSON: ' + error.message);
  }
  structuralLimit(value, label);
  return value;
}

function validatorFor(version, kind) {
  var epoch = EPOCHS[version];
  if (!epoch) throw new Error('unsupported autonomy contract epoch: ' + version);
  var key = version + ':' + kind;
  if (!validators[key]) {
    var relative = kind === 'constitution' ? epoch.constitutionSchema : epoch.coverageSchema;
    var schemaPath = path.join(ROOT, relative);
    var schema = readBoundedJson(schemaPath, relative);
    validators[key] = schemaSubset.createValidator({
      schemas: [{ name: schemaPath, schema: schema }],
      rootName: schemaPath
    });
  }
  return validators[key];
}

function validateRecord(record, version, kind) {
  var errors = validatorFor(version, kind).validate(record);
  if (errors.length) {
    throw new Error(kind + ' does not conform to the canonical ' + version +
      ' schema: ' + errors.slice(0, 8).join('; ') +
      (errors.length > 8 ? '; plus ' + (errors.length - 8) + ' more' : ''));
  }
}

function validateAutonomyContractEpoch(constitution, coverage) {
  if (!plain(constitution) || !plain(coverage)) {
    throw new Error('constitution and coverage must be JSON objects');
  }
  var version = constitution.schema_version;
  if (!Object.prototype.hasOwnProperty.call(EPOCHS, version)) {
    throw new Error('unsupported autonomy constitution epoch: ' + String(version));
  }
  if (coverage.schema_version !== version) {
    throw new Error('constitution and coverage must declare one exact contract epoch');
  }
  validateRecord(constitution, version, 'constitution');
  validateRecord(coverage, version, 'coverage');
  if (coverage.constitution_digest !== constitution.constitution_digest) {
    throw new Error('coverage does not bind the declared constitution');
  }
  return version;
}

function loadAutonomyContractEpoch(constitutionPath, coveragePath) {
  var constitution = readBoundedJson(constitutionPath, 'constitution');
  var coverage = readBoundedJson(coveragePath, 'coverage');
  var version = validateAutonomyContractEpoch(constitution, coverage);
  return { constitution: constitution, coverage: coverage, version: version };
}

module.exports = {
  loadAutonomyContractEpoch: loadAutonomyContractEpoch,
  readBoundedJson: readBoundedJson,
  validateAutonomyContractEpoch: validateAutonomyContractEpoch
};
