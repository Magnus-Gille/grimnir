'use strict';

var crypto = require('crypto');

function canonicalize(value) {
  if (Array.isArray(value)) {
    return '[' + value.map(canonicalize).join(',') + ']';
  }
  if (value !== null && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map(function (key) {
      return JSON.stringify(key) + ':' + canonicalize(value[key]);
    }).join(',') + '}';
  }
  return JSON.stringify(value);
}

function cloneWithoutOwnEvidenceDigest(record) {
  var copy = JSON.parse(JSON.stringify(record));
  if (copy && copy.evidence && typeof copy.evidence === 'object') {
    delete copy.evidence.digest;
  }
  return copy;
}

function evidenceDigest(record) {
  var canonical = canonicalize(cloneWithoutOwnEvidenceDigest(record));
  return 'sha256:' + crypto.createHash('sha256').update(canonical, 'utf8').digest('hex');
}

module.exports = {
  canonicalize: canonicalize,
  evidenceDigest: evidenceDigest
};
