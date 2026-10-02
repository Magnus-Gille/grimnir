#!/usr/bin/env bash
# Regression coverage for issue #208: local dependency preparation only needs
# the build toolchain, so native dependency lifecycle scripts must not run on
# the workstation. The remote production install remains responsible for
# native modules and must keep its lifecycle scripts enabled.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

pass() {
  echo "  PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/repos"

cat > "$TMP_DIR/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_CAPTURE"
command=${*: -1}
if [[ "$command" == "true" ]]; then
  exit 0
elif [[ "$command" == *"DEPLOY_MARKER_INVALIDATED"* ]]; then
  printf '%s\n' DEPLOY_MARKER_INVALIDATED:unknown
elif [[ "$command" == *"DEPLOY_OK"* ]]; then
  printf '%s\n' DEPLOY_OK
fi
exit 0
EOF

cat > "$TMP_DIR/bin/rsync" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RSYNC_CAPTURE"
EOF

cat > "$TMP_DIR/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NPM_CAPTURE"
if [[ "$1" == "ci" || "$1" == "install" ]] && [[ " $* " != *" --ignore-scripts "* ]]; then
  printf '%s\n' "$*" >> "$NATIVE_SCRIPT_CAPTURE"
  exit 42
fi
if [[ "$1" == "run" && "$2" == "build" && -e "$NATIVE_SCRIPT_CAPTURE" ]]; then
  exit 43
fi
exit 0
EOF

chmod +x "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/rsync" "$TMP_DIR/bin/npm"
SSH_CAPTURE="$TMP_DIR/ssh.calls"
RSYNC_CAPTURE="$TMP_DIR/rsync.calls"
NPM_CAPTURE="$TMP_DIR/npm.calls"
NATIVE_SCRIPT_CAPTURE="$TMP_DIR/native-script.calls"
export SSH_CAPTURE RSYNC_CAPTURE NPM_CAPTURE NATIVE_SCRIPT_CAPTURE

commit_fixture_repo() {
  local repo_path=$1
  git init -q -b main "$repo_path"
  git -C "$repo_path" add .
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -C "$repo_path" commit -q -m seed
}

make_fixture_repo() {
  local repo_path=$1 with_lockfile=$2
  local service_name
  service_name=$(basename "$repo_path")
  mkdir -p "$repo_path/systemd"
  printf '%s\n' '{"name":"fixture","scripts":{"build":"tsc"}}' > "$repo_path/package.json"
  printf '%s\n' '[Service]' 'ExecStart=/bin/true' > "$repo_path/systemd/$service_name.service"
  if [[ "$with_lockfile" == true ]]; then
    printf '%s\n' '{"name":"fixture","lockfileVersion":3,"requires":true,"packages":{}}' \
      > "$repo_path/package-lock.json"
  fi
  commit_fixture_repo "$repo_path"
}

make_registry() {
  local path=$1 service=$2
  cat > "$path" <<EOF
{
  "components": [
    {
      "name": "$service", "repo": "$service", "host": "h1", "port": null,
      "deploy": true, "scan": false, "deploy_path": "/srv/$service",
      "persistent_paths": [], "needs_build": true, "systemd_units": []
    }
  ]
}
EOF
}

run_case() {
  local service=$1 repo_path=$2 expected_local_install=$3 expected_remote_install=$4
  local expected_sha registry output rc
  expected_sha=$(git -C "$repo_path" rev-parse HEAD)
  registry="$TMP_DIR/$service-registry.json"
  output="$TMP_DIR/$service.out"
  make_registry "$registry" "$service"
  rm -f "$SSH_CAPTURE" "$RSYNC_CAPTURE" "$NPM_CAPTURE" "$NATIVE_SCRIPT_CAPTURE"

  rc=0
  REGISTRY_PATH="$registry" LOCAL_REPOS_ROOT="$TMP_DIR/repos" \
    PATH="$TMP_DIR/bin:$PATH" bash "$DEPLOY" \
      "$service=$repo_path@$expected_sha" >"$output" 2>&1 || rc=$?
  if [[ "$rc" == 0 ]]; then
    pass "$service deploy completes through local and remote preparation"
  else
    fail "$service deploy must complete through local and remote preparation"
    sed -n '1,120p' "$output"
    return
  fi
  if [[ ! -e "$NATIVE_SCRIPT_CAPTURE" ]]; then
    pass "$service local preparation never executes a native lifecycle script"
  else
    fail "$service local preparation must never execute a native lifecycle script"
  fi

  if grep -Fqx -- "$expected_local_install --ignore-scripts" "$NPM_CAPTURE"; then
    pass "$service local install disables lifecycle scripts"
  else
    fail "$service local install must disable lifecycle scripts"
  fi
  if grep -Fqx -- "run build" "$NPM_CAPTURE"; then
    pass "$service local build still runs after dependency preparation"
  else
    fail "$service local build must still run after dependency preparation"
  fi
  if grep -Fq -- "npm $expected_remote_install" "$SSH_CAPTURE"; then
    pass "$service remote install retains native lifecycle scripts"
  else
    fail "$service remote install must retain native lifecycle scripts"
  fi
  if grep -Fq -- "--ignore-scripts" "$SSH_CAPTURE"; then
    fail "$service remote preparation must not inherit local --ignore-scripts"
  else
    pass "$service remote preparation does not inherit local --ignore-scripts"
  fi
}

make_fixture_repo "$TMP_DIR/repos/lock-service" true
make_fixture_repo "$TMP_DIR/repos/lockless-service" false
run_case lock-service "$TMP_DIR/repos/lock-service" "ci" "ci --omit=dev"
run_case lockless-service "$TMP_DIR/repos/lockless-service" "install" "install --omit=dev"

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
