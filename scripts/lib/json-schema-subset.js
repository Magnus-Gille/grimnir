'use strict';

var path = require('path');

var SUPPORTED = new Set([
  '$schema', '$id', '$defs', '$ref', 'title', 'description', 'oneOf',
  'const', 'enum', 'type', 'minLength', 'pattern', 'format', 'minimum',
  'minItems', 'uniqueItems', 'items', 'required', 'properties',
  'additionalProperties'
]);

function plain(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (plain(value)) {
    return '{' + Object.keys(value).sort().map(function (key) {
      return JSON.stringify(key) + ':' + canonical(value[key]);
    }).join(',') + '}';
  }
  return JSON.stringify(value);
}

function realDateTime(value) {
  var match = typeof value === 'string' &&
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/.exec(value);
  if (!match) return false;
  var parsed = Date.parse(value);
  if (Number.isNaN(parsed)) return false;
  var date = new Date(parsed);
  return date.getUTCFullYear() === Number(match[1]) &&
    date.getUTCMonth() + 1 === Number(match[2]) &&
    date.getUTCDate() === Number(match[3]) &&
    date.getUTCHours() === Number(match[4]) &&
    date.getUTCMinutes() === Number(match[5]) &&
    date.getUTCSeconds() === Number(match[6]);
}

function inspectSchema(node, at, currentName, refs) {
  if (typeof node === 'boolean') return;
  if (!plain(node)) throw new Error('schema node must be an object at ' + at);
  Object.keys(node).forEach(function (keyword) {
    if (!SUPPORTED.has(keyword)) {
      throw new Error('unsupported JSON Schema keyword ' + keyword + ' at ' + at);
    }
  });
  if (node.type !== undefined &&
      ['object', 'array', 'string', 'integer', 'boolean', 'null'].indexOf(node.type) === -1) {
    throw new Error('unsupported JSON Schema type at ' + at);
  }
  if (node.$ref !== undefined) {
    if (typeof node.$ref !== 'string') throw new Error('$ref must be a string at ' + at);
    var siblings = Object.keys(node).filter(function (key) {
      return ['$ref', 'title', 'description'].indexOf(key) === -1;
    });
    if (siblings.length) throw new Error('unsupported $ref siblings at ' + at);
    refs.push({ ref: node.$ref, currentName: currentName });
  }
  if (node.format !== undefined && node.format !== 'date-time') {
    throw new Error('unsupported JSON Schema format at ' + at);
  }
  if (node.additionalProperties !== undefined &&
      typeof node.additionalProperties !== 'boolean') {
    throw new Error('unsupported additionalProperties schema at ' + at);
  }
  if (node.properties !== undefined && !plain(node.properties)) {
    throw new Error('properties must be an object at ' + at);
  }
  if (node.$defs !== undefined && !plain(node.$defs)) {
    throw new Error('$defs must be an object at ' + at);
  }
  if (node.required !== undefined &&
      (!Array.isArray(node.required) || !node.required.every(function (item) { return typeof item === 'string'; }))) {
    throw new Error('required must be a string array at ' + at);
  }
  if (node.oneOf !== undefined && !Array.isArray(node.oneOf)) {
    throw new Error('oneOf must be an array at ' + at);
  }
  if (node.enum !== undefined && !Array.isArray(node.enum)) {
    throw new Error('enum must be an array at ' + at);
  }
  if (node.pattern !== undefined) {
    if (typeof node.pattern !== 'string') throw new Error('pattern must be a string at ' + at);
    try { new RegExp(node.pattern); } catch (error) { throw new Error('invalid pattern at ' + at); }
  }
  ['minLength', 'minimum', 'minItems'].forEach(function (keyword) {
    if (node[keyword] !== undefined &&
        (!Number.isInteger(node[keyword]) || node[keyword] < 0)) {
      throw new Error(keyword + ' must be a non-negative integer at ' + at);
    }
  });
  if (node.uniqueItems !== undefined && typeof node.uniqueItems !== 'boolean') {
    throw new Error('uniqueItems must be boolean at ' + at);
  }
  Object.keys(node.properties || {}).forEach(function (key) {
    inspectSchema(node.properties[key], at + '.properties.' + key, currentName, refs);
  });
  Object.keys(node.$defs || {}).forEach(function (key) {
    inspectSchema(node.$defs[key], at + '.$defs.' + key, currentName, refs);
  });
  if (node.items !== undefined) inspectSchema(node.items, at + '.items', currentName, refs);
  (node.oneOf || []).forEach(function (child, index) {
    inspectSchema(child, at + '.oneOf[' + index + ']', currentName, refs);
  });
}

function typeMatches(type, value) {
  return {
    object: plain(value),
    array: Array.isArray(value),
    string: typeof value === 'string',
    integer: Number.isInteger(value),
    boolean: typeof value === 'boolean',
    null: value === null
  }[type];
}

function fragment(root, pointer) {
  if (!pointer || pointer === '#') return root;
  if (pointer.indexOf('#/') !== 0) throw new Error('unsupported schema fragment ' + pointer);
  return pointer.slice(2).split('/').reduce(function (value, raw) {
    var key = raw.replace(/~1/g, '/').replace(/~0/g, '~');
    return value && value[key];
  }, root);
}

function createValidator(options) {
  if (!options || !Array.isArray(options.schemas) || !options.rootName) {
    throw new Error('schema validator requires schemas and rootName');
  }
  var byName = {};
  var refs = [];
  options.schemas.forEach(function (entry) {
    if (!entry || typeof entry.name !== 'string' || !plain(entry.schema)) {
      throw new Error('invalid schema registration');
    }
    inspectSchema(entry.schema, entry.name, entry.name, refs);
    byName[entry.name] = entry.schema;
    byName[path.basename(entry.name)] = entry.schema;
    if (typeof entry.schema.$id === 'string') byName[entry.schema.$id] = entry.schema;
  });
  if (!byName[options.rootName]) throw new Error('root schema is not registered: ' + options.rootName);

  function resolve(ref, currentName) {
    var parts = ref.split('#');
    var targetName = parts[0] || currentName;
    var target = byName[targetName] || byName[path.basename(targetName)];
    if (!target) throw new Error('unresolved external schema ref ' + ref);
    var resolved = fragment(target, parts.length > 1 ? '#' + parts[1] : '#');
    if (resolved === undefined) throw new Error('unresolved schema fragment ' + ref);
    return { schema: resolved, rootName: targetName };
  }
  refs.forEach(function (entry) {
    resolve(entry.ref, entry.currentName);
  });

  function errorsFor(node, value, at, currentName) {
    if (node === true) return [];
    if (node === false) return [at + ': forbidden'];
    if (node.$ref) {
      var target = resolve(node.$ref, currentName);
      return errorsFor(target.schema, value, at, target.rootName);
    }
    if (node.oneOf) {
      var attempts = node.oneOf.map(function (child) {
        return errorsFor(child, value, at, currentName);
      });
      return attempts.filter(function (attempt) { return attempt.length === 0; }).length === 1
        ? [] : [at + ': expected exactly one schema branch'];
    }
    var errors = [];
    if (Object.prototype.hasOwnProperty.call(node, 'const') &&
        canonical(value) !== canonical(node.const)) errors.push(at + ': const mismatch');
    if (node.enum && !node.enum.some(function (candidate) {
      return canonical(candidate) === canonical(value);
    })) errors.push(at + ': enum mismatch');
    if (node.type && !typeMatches(node.type, value)) {
      return errors.concat([at + ': expected ' + node.type]);
    }
    if (typeof value === 'string') {
      if (node.minLength !== undefined && value.length < node.minLength) errors.push(at + ': minLength');
      if (node.pattern && !new RegExp(node.pattern).test(value)) errors.push(at + ': pattern');
      if (node.format === 'date-time' && !realDateTime(value)) errors.push(at + ': invalid date-time');
    }
    if (typeof value === 'number' && node.minimum !== undefined && value < node.minimum) {
      errors.push(at + ': minimum');
    }
    if (Array.isArray(value)) {
      if (node.minItems !== undefined && value.length < node.minItems) errors.push(at + ': minItems');
      if (node.uniqueItems &&
          new Set(value.map(canonical)).size !== value.length) errors.push(at + ': duplicate items');
      if (node.items) value.forEach(function (item, index) {
        errors.push.apply(errors, errorsFor(node.items, item, at + '[' + index + ']', currentName));
      });
    }
    if (plain(value)) {
      (node.required || []).forEach(function (field) {
        if (!Object.prototype.hasOwnProperty.call(value, field)) errors.push(at + '.' + field + ': required');
      });
      Object.keys(node.properties || {}).forEach(function (field) {
        if (Object.prototype.hasOwnProperty.call(value, field)) {
          errors.push.apply(errors, errorsFor(node.properties[field], value[field], at + '.' + field, currentName));
        }
      });
      if (node.additionalProperties === false) {
        Object.keys(value).forEach(function (field) {
          if (!Object.prototype.hasOwnProperty.call(node.properties || {}, field)) {
            errors.push(at + '.' + field + ': additional property');
          }
        });
      }
    }
    return errors;
  }

  return {
    validate: function (value) {
      return errorsFor(byName[options.rootName], value, '$', options.rootName);
    }
  };
}

module.exports = {
  createValidator: createValidator
};
