#!/usr/bin/env node
'use strict';
const path = require('node:path');
const { resolveNode, OperationalError } = require('./lib/operational-registry.js');
const args = process.argv.slice(2);
if (args.length < 1 || args.length > 2 || !/^node-[a-z0-9-]+$/.test(args[0]) ||
    (args.length === 2 && args[1] !== '--private')) {
  process.stderr.write('resolve-node: USAGE (node-id [--private])\n');
  process.exit(2);
}
try {
  const result = resolveNode(process.env.REGISTRY_PATH || path.join(__dirname, '..', 'services.json'), args[0],
    { privateOutput: args[1] === '--private' });
  process.stdout.write(JSON.stringify(result) + '\n');
} catch (err) {
  process.stderr.write('resolve-node: ' + (err instanceof OperationalError ? err.code : 'INTERNAL_ERROR') + '\n');
  process.exit(1);
}
