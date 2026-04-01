// registry.js — Query the Grimnir service registry (services.json)
//
// Usage from bash:
//   REGISTRY_PATH=/path/to/services.json QUERY=<query> node --input-type=commonjs scripts/lib/registry.js
//
// Queries:
//   deploy       — components where deploy=true, output: name|repo|host|unit_type|needs_build (deploy.sh format)
//   scan         — components where scan=true, output: space-separated repo names
//   components   — all component names, space-separated
//   systemd      — all systemd unit names, space-separated
//   ports        — components with ports, output: name|port per line
//   validate     — host-aware output for validation: name|host|port|units_json per line
//   json:<field>=<value> — filter by field, output full JSON array
//   all          — full JSON array of all components

var fs = require('fs');
var path = require('path');

var registryPath = process.env.REGISTRY_PATH;
var query = process.env.QUERY;

if (!registryPath) {
  process.stderr.write('ERROR: REGISTRY_PATH env var not set\n');
  process.exit(1);
}
if (!query) {
  process.stderr.write('ERROR: QUERY env var not set\n');
  process.exit(1);
}

var data;
try {
  var raw = fs.readFileSync(registryPath, 'utf8');
  data = JSON.parse(raw);
} catch (err) {
  process.stderr.write('ERROR: Failed to read/parse ' + registryPath + ': ' + err.message + '\n');
  process.exit(1);
}

if (!data.components || !Array.isArray(data.components)) {
  process.stderr.write('ERROR: services.json missing "components" array\n');
  process.exit(1);
}

var components = data.components;

switch (query) {
  case 'deploy': {
    // Output format matches what deploy.sh needs: name|host|path|primary_unit_type|needs_build
    var deployable = components.filter(function (c) { return c.deploy; });
    deployable.forEach(function (c) {
      // Determine primary unit type from first systemd unit, default to "service"
      var unitType = 'service';
      if (c.systemd_units && c.systemd_units.length > 0) {
        unitType = c.systemd_units[0].type;
      }
      var repoPath = '~/repos/' + c.repo;
      var needsBuild = c.needs_build ? 'true' : 'false';
      process.stdout.write(c.name + '|' + c.host + '|' + repoPath + '|' + unitType + '|' + needsBuild + '\n');
    });
    break;
  }
  case 'scan': {
    var scannable = components.filter(function (c) { return c.scan; });
    process.stdout.write(scannable.map(function (c) { return c.repo; }).join(' ') + '\n');
    break;
  }
  case 'components': {
    process.stdout.write(components.map(function (c) { return c.name; }).join(' ') + '\n');
    break;
  }
  case 'systemd': {
    var units = [];
    components.forEach(function (c) {
      if (c.systemd_units) {
        c.systemd_units.forEach(function (u) { units.push(u.name); });
      }
    });
    process.stdout.write(units.join(' ') + '\n');
    break;
  }
  case 'ports': {
    components.forEach(function (c) {
      if (c.port) {
        process.stdout.write(c.name + '|' + c.port + '\n');
      }
    });
    break;
  }
  case 'validate': {
    // Host-aware output for validation: name|host|port|repo|units_json
    // Includes all components so validator can check each on the correct host
    components.forEach(function (c) {
      var port = c.port || '';
      var host = c.host || '';
      var units = JSON.stringify(c.systemd_units || []);
      process.stdout.write(c.name + '|' + host + '|' + port + '|' + c.repo + '|' + units + '\n');
    });
    break;
  }
  case 'all': {
    process.stdout.write(JSON.stringify(components) + '\n');
    break;
  }
  default: {
    // json:<field>=<value> — filter and return JSON
    var match = query.match(/^json:(\w+)=(.+)$/);
    if (match) {
      var field = match[1];
      var value = match[2];
      // Parse booleans
      if (value === 'true') value = true;
      else if (value === 'false') value = false;
      var filtered = components.filter(function (c) { return c[field] === value; });
      process.stdout.write(JSON.stringify(filtered) + '\n');
    } else {
      process.stderr.write('ERROR: Unknown query: ' + query + '\n');
      process.stderr.write('Valid queries: deploy, scan, components, systemd, ports, all, json:<field>=<value>\n');
      process.exit(1);
    }
  }
}
