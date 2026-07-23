#!/usr/bin/env bash
# Render registry-authorized systemd templates, preflight every rendered unit,
# then install them as one fail-closed phase. This script is streamed to the
# target by deploy.sh; it does not rely on component-owned deployment logic.

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "ERROR: usage: render-systemd-units.sh DEPLOY_PATH RUNTIME_JSON UNITS_JSON PERSISTENT_PATHS_JSON" >&2
  exit 2
fi

deploy_path=$1
runtime_json=$2
units_json=$3
persistent_paths_json=$4

json_field() {
  local json=$1 field=$2
  JSON_INPUT="$json" JSON_FIELD="$field" node --input-type=commonjs -e '
    var value = JSON.parse(process.env.JSON_INPUT)[process.env.JSON_FIELD];
    if (value === undefined || value === null) process.exit(1);
    process.stdout.write(typeof value === "object" ? JSON.stringify(value) : String(value));
  '
}

runtime_user=$(json_field "$runtime_json" user)
runtime_home=$(json_field "$runtime_json" home)
runtime_target=$(json_field "$runtime_json" deploy_target)

if [[ "$deploy_path" != "$runtime_target" ]]; then
  echo "ERROR: runtime deploy_target does not match registry deploy_path" >&2
  exit 1
fi

passwd_entry=$(getent passwd "$runtime_user" 2>/dev/null || true)
if [[ -z "$passwd_entry" ]]; then
  echo "ERROR: runtime user does not exist: $runtime_user" >&2
  exit 1
fi
IFS=: read -r passwd_user _ _ _ _ passwd_home _ <<< "$passwd_entry"
if [[ "$passwd_user" != "$runtime_user" || "$passwd_home" != "$runtime_home" ]]; then
  echo "ERROR: runtime user/home mismatch for $runtime_user: expected $runtime_home, got ${passwd_home:-unknown}" >&2
  exit 1
fi
if [[ ! -d "$deploy_path" || -L "$deploy_path" ]]; then
  echo "ERROR: deploy target is missing, not a directory, or symlinked: $deploy_path" >&2
  exit 1
fi

render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT
manifest="$render_dir/manifest"
: > "$manifest"

unit_rows() {
  UNITS_JSON="$units_json" node --input-type=commonjs -e '
    var units = JSON.parse(process.env.UNITS_JSON);
    units.forEach(function (unit) {
      process.stdout.write([
        unit.name,
        unit.type || "service",
        unit.scope || "system"
      ].join("|") + "\n");
    });
  '
}

resolve_source() {
  local unit_file=$1 candidate
  for candidate in "$deploy_path/systemd/$unit_file" "$deploy_path/$unit_file"; do
    if [[ -f "$candidate" && ! -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

render_one() {
  local unit_file=$1 scope=$2 required=$3 source destination install_dir token
  if ! source=$(resolve_source "$unit_file"); then
    if [[ "$required" == "true" ]]; then
      echo "ERROR: unit file missing: $unit_file" >&2
      return 1
    fi
    return 0
  fi

  destination="$render_dir/$unit_file"
  install_dir=${deploy_path##*/}
  RUNTIME_USER="$runtime_user" RUNTIME_HOME="$runtime_home" \
    DEPLOY_TARGET="$deploy_path" INSTALL_DIR="$install_dir" \
    awk '
      {
        gsub(/<user>/, ENVIRON["RUNTIME_USER"]);
        gsub(/<home>/, ENVIRON["RUNTIME_HOME"]);
        gsub(/<deploy-path>/, ENVIRON["DEPLOY_TARGET"]);
        gsub(/<install-dir>/, ENVIRON["INSTALL_DIR"]);
        print;
      }
    ' "$source" > "$destination"

  token=$(awk '/^[[:space:]]*[#;]/ { next } match($0, /<[A-Za-z][A-Za-z0-9_-]*>/) { print substr($0, RSTART, RLENGTH); exit }' "$destination")
  if [[ -n "$token" ]]; then
    echo "ERROR: rendered unit contains unresolved placeholder $token: $unit_file" >&2
    return 1
  fi
  printf '%s|%s\n' "$unit_file" "$scope" >> "$manifest"
}

rows=$(unit_rows)
while IFS='|' read -r unit_name unit_kind unit_scope; do
  [[ -n "$unit_name" ]] || continue
  render_one "${unit_name}.${unit_kind}" "$unit_scope" true
  if [[ "$unit_kind" == "timer" ]]; then
    render_one "${unit_name}.service" "$unit_scope" false
  fi
done <<< "$rows"

RUNTIME_JSON="$runtime_json" PERSISTENT_PATHS_JSON="$persistent_paths_json" \
  RENDER_MANIFEST="$manifest" RENDER_DIR="$render_dir" node <<'NODE'
const fs = require("fs");
const path = require("path");

const runtime = JSON.parse(process.env.RUNTIME_JSON);
const persistentPaths = JSON.parse(process.env.PERSISTENT_PATHS_JSON);
const manifest = fs.readFileSync(process.env.RENDER_MANIFEST, "utf8")
  .trim().split("\n").filter(Boolean).map((line) => {
    const split = line.lastIndexOf("|");
    return { file: line.slice(0, split), scope: line.slice(split + 1) };
  });
const errors = [];

function fail(file, message) {
  errors.push(file + ": " + message);
}

function within(candidate, root) {
  return candidate === root || candidate.startsWith(root + "/");
}

function canonicalAbsolute(value) {
  return typeof value === "string" && path.posix.isAbsolute(value) &&
    path.posix.normalize(value) === value && value !== "/";
}

function tokenize(value) {
  const tokens = [];
  let token = "";
  let quote = null;
  let escaped = false;
  for (const char of value) {
    if (escaped) {
      token += char;
      escaped = false;
    } else if (char === "\\") {
      escaped = true;
    } else if (quote) {
      if (char === quote) quote = null;
      else token += char;
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (/\s/.test(char)) {
      if (token) {
        tokens.push(token);
        token = "";
      }
    } else {
      token += char;
    }
  }
  if (escaped || quote) throw new Error("unsupported or unterminated quoting");
  if (token) tokens.push(token);
  return tokens;
}

function directives(source) {
  const logical = [];
  let pending = "";
  for (const physical of source.split(/\r?\n/)) {
    const line = pending + physical;
    if (line.endsWith("\\")) pending = line.slice(0, -1);
    else {
      logical.push(line);
      pending = "";
    }
  }
  if (pending) throw new Error("unterminated line continuation");

  let section = "";
  const result = new Map();
  for (const raw of logical) {
    const line = raw.trim();
    if (!line || line.startsWith("#") || line.startsWith(";")) continue;
    const sectionMatch = line.match(/^\[([A-Za-z]+)\]$/);
    if (sectionMatch) {
      section = sectionMatch[1];
      continue;
    }
    if (section !== "Service") continue;
    const equals = line.indexOf("=");
    if (equals < 1) continue;
    const key = line.slice(0, equals).trim();
    const value = line.slice(equals + 1).trim();
    if (!result.has(key)) result.set(key, []);
    result.get(key).push(value);
  }
  return result;
}

function last(map, key) {
  const values = map.get(key) || [];
  return values.length ? values[values.length - 1] : null;
}

function requireExisting(file, candidate, kind, allowSymlink = false) {
  if (!canonicalAbsolute(candidate)) {
    fail(file, kind + " is not a canonical absolute path: " + candidate);
    return false;
  }
  try {
    const info = fs.lstatSync(candidate);
    if (info.isSymbolicLink() && !allowSymlink) {
      fail(file, kind + " must not be a symlink: " + candidate);
      return false;
    }
    return true;
  } catch (_) {
    fail(file, kind + " does not exist: " + candidate);
    return false;
  }
}

const environmentFiles = runtime.environment_files || [];
const sandboxPaths = runtime.sandbox_paths || [];
const ownedSandboxRoots = [runtime.deploy_target].concat(persistentPaths);

function allowedSandboxPath(candidate, directive) {
  if (ownedSandboxRoots.some((root) => within(candidate, root))) return true;
  const exactExternalReadOnly = directive === "ReadOnlyPaths" ||
    directive === "BindReadOnlyPaths" || directive === "InaccessiblePaths";
  return exactExternalReadOnly && sandboxPaths.includes(candidate);
}

for (const envFile of environmentFiles) {
  requireExisting("runtime", envFile, "declared environment file");
}
for (const sandboxPath of sandboxPaths) {
  requireExisting("runtime", sandboxPath, "declared sandbox path");
}

for (const entry of manifest) {
  if (!entry.file.endsWith(".service")) continue;
  const fullPath = path.join(process.env.RENDER_DIR, entry.file);
  let parsed;
  try {
    parsed = directives(fs.readFileSync(fullPath, "utf8"));
  } catch (error) {
    fail(entry.file, error.message);
    continue;
  }

  const user = last(parsed, "User");
  if (entry.scope === "system" && user !== runtime.user) {
    fail(entry.file, "User must equal registered runtime user " + runtime.user);
  } else if (entry.scope === "user" && user && user !== runtime.user) {
    fail(entry.file, "User conflicts with registered runtime user " + runtime.user);
  }

  const workingDirectory = last(parsed, "WorkingDirectory");
  if (workingDirectory !== runtime.deploy_target) {
    fail(entry.file, "WorkingDirectory must equal registered deploy target " + runtime.deploy_target);
  } else {
    requireExisting(entry.file, workingDirectory, "WorkingDirectory");
  }

  const execStarts = (parsed.get("ExecStart") || []).filter(Boolean);
  if (execStarts.length === 0) {
    fail(entry.file, "ExecStart is required");
  }
  for (const execStart of execStarts) {
    let tokens;
    try {
      tokens = tokenize(execStart);
    } catch (error) {
      fail(entry.file, "ExecStart " + error.message);
      continue;
    }
    if (!tokens.length) {
      fail(entry.file, "ExecStart is empty");
      continue;
    }
    const executable = tokens[0].replace(/^[+\-!:@]+/, "");
    if (!requireExisting(entry.file, executable, "ExecStart executable", true)) continue;
    try {
      fs.accessSync(executable, fs.constants.X_OK);
    } catch (_) {
      fail(entry.file, "ExecStart executable is not executable: " + executable);
    }
    for (const argument of tokens.slice(1)) {
      let candidate = argument;
      const equals = candidate.indexOf("=/");
      if (equals >= 0) candidate = candidate.slice(equals + 1);
      if (!candidate.startsWith("/")) continue;
      if (!within(candidate, runtime.deploy_target)) {
        fail(entry.file, "ExecStart path is outside registered deploy target: " + candidate);
      }
      requireExisting(entry.file, candidate, "ExecStart path");
    }
  }

  const actualEnvironmentFiles = [];
  for (const value of parsed.get("EnvironmentFile") || []) {
    let tokens;
    try {
      tokens = tokenize(value);
    } catch (error) {
      fail(entry.file, "EnvironmentFile " + error.message);
      continue;
    }
    for (let candidate of tokens) {
      if (candidate.startsWith("-")) {
        fail(entry.file, "registered private environment file must not be optional: " + candidate);
        candidate = candidate.slice(1);
      }
      actualEnvironmentFiles.push(candidate);
      if (!environmentFiles.includes(candidate)) {
        fail(entry.file, "EnvironmentFile is not registered: " + candidate);
      }
      requireExisting(entry.file, candidate, "EnvironmentFile");
    }
  }
  for (const required of environmentFiles) {
    if (!actualEnvironmentFiles.includes(required)) {
      fail(entry.file, "required EnvironmentFile is absent: " + required);
    }
  }

  const sandboxDirectives = [
    "ReadWritePaths", "ReadOnlyPaths", "InaccessiblePaths",
    "BindPaths", "BindReadOnlyPaths"
  ];
  for (const key of sandboxDirectives) {
    for (const value of parsed.get(key) || []) {
      let tokens;
      try {
        tokens = tokenize(value);
      } catch (error) {
        fail(entry.file, key + " " + error.message);
        continue;
      }
      for (let token of tokens) {
        token = token.replace(/^[+\-]+/, "");
        const candidates = key.startsWith("Bind") ? token.split(":").slice(0, 2) : [token];
        for (const candidate of candidates) {
          if (!candidate || !candidate.startsWith("/")) {
            fail(entry.file, key + " contains a non-absolute path: " + candidate);
            continue;
          }
          if (!allowedSandboxPath(candidate, key)) {
            fail(entry.file, key + " path is outside registered roots: " + candidate);
          }
          requireExisting(entry.file, candidate, key + " path");
        }
      }
    }
  }
}

if (errors.length) {
  console.error("ERROR: rendered systemd preflight failed:");
  for (const error of errors) console.error("  - " + error);
  process.exit(1);
}
NODE

system_root="${SYSTEMD_SYSTEM_ROOT:-/etc/systemd/system}"
install_plan="$render_dir/install-plan"
installed_plan="$render_dir/installed-plan"
mkdir -p "$render_dir/backups"
: > "$install_plan"
: > "$installed_plan"

destination_is_symlink() {
  local privileged=$1 destination=$2
  if [[ "$privileged" == "true" ]]; then
    sudo test -L "$destination"
  else
    [[ -L "$destination" ]]
  fi
}

destination_is_file() {
  local privileged=$1 destination=$2
  if [[ "$privileged" == "true" ]]; then
    sudo test -f "$destination"
  else
    [[ -f "$destination" ]]
  fi
}

copy_preserving() {
  local privileged=$1 source=$2 destination=$3
  if [[ "$privileged" == "true" ]]; then
    sudo cp -p -- "$source" "$destination"
  else
    cp -p -- "$source" "$destination"
  fi
}

install_rendered() {
  local privileged=$1 source=$2 destination=$3
  if [[ "$privileged" == "true" ]]; then
    sudo install -D -m644 "$source" "$destination"
  else
    install -D -m644 "$source" "$destination"
  fi
}

remove_destination() {
  local privileged=$1 destination=$2
  if [[ "$privileged" == "true" ]]; then
    sudo rm -f -- "$destination"
  else
    rm -f -- "$destination"
  fi
}

install_index=0
while IFS='|' read -r unit_file unit_scope; do
  [[ -n "$unit_file" ]] || continue
  install_index=$((install_index + 1))
  privileged=false
  if [[ "$unit_scope" == "user" ]]; then
    unit_destination="$runtime_home/.config/systemd/user/$unit_file"
  elif [[ "$system_root" == "/etc/systemd/system" ]]; then
    unit_destination="$system_root/$unit_file"
    privileged=true
  else
    unit_destination="$system_root/$unit_file"
  fi

  if destination_is_symlink "$privileged" "$unit_destination"; then
    echo "ERROR: refusing to replace symlinked unit destination: $unit_destination" >&2
    exit 1
  fi

  backup="$render_dir/backups/$install_index"
  had_previous=false
  if destination_is_file "$privileged" "$unit_destination"; then
    copy_preserving "$privileged" "$unit_destination" "$backup"
    copy_preserving "$privileged" "$backup" "${unit_destination}.grimnir-previous"
    had_previous=true
  fi
  printf '%s|%s|%s|%s|%s\n' \
    "$unit_file" "$unit_destination" "$privileged" "$had_previous" "$backup" >> "$install_plan"
done < "$manifest"

install_failed=false
while IFS='|' read -r unit_file unit_destination privileged had_previous backup; do
  [[ -n "$unit_file" ]] || continue
  if install_rendered "$privileged" "$render_dir/$unit_file" "$unit_destination"; then
    printf '%s|%s|%s|%s|%s\n' \
      "$unit_file" "$unit_destination" "$privileged" "$had_previous" "$backup" >> "$installed_plan"
  else
    echo "ERROR: failed to install rendered unit: $unit_destination" >&2
    install_failed=true
    break
  fi
done < "$install_plan"

if [[ "$install_failed" == "true" ]]; then
  rollback_failed=false
  while IFS='|' read -r unit_file unit_destination privileged had_previous backup; do
    [[ -n "$unit_file" ]] || continue
    if [[ "$had_previous" == "true" ]]; then
      if ! copy_preserving "$privileged" "$backup" "$unit_destination"; then
        echo "ERROR: failed to restore prior unit after install failure: $unit_destination" >&2
        rollback_failed=true
      fi
    elif ! remove_destination "$privileged" "$unit_destination"; then
      echo "ERROR: failed to remove newly installed unit after install failure: $unit_destination" >&2
      rollback_failed=true
    fi
  done < "$installed_plan"
  if [[ "$rollback_failed" == "true" ]]; then
    echo "ERROR: rendered unit rollback was incomplete; inspect destinations before daemon-reload" >&2
  else
    echo "ERROR: restored all previously replaced units; daemon-reload was not requested" >&2
  fi
  exit 1
fi

echo "SYSTEMD_UNITS_PREPARED"
