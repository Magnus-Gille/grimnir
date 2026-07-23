#!/usr/bin/env bash
# Regression for grimnir#107: registry-owned runtime identity must render
# clean-install units, fail closed before restart, and stay markerless.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy.sh"
RENDER_HELPER="$SCRIPT_DIR/../lib/render-systemd-units.sh"
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

assert_file_contains() {
  local desc=$1 file=$2 expected=$3
  if grep -Fq -- "$expected" "$file"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

echo "systemd runtime rendering tests"
echo "==============================="

RUNTIME_HOME="$TMP_DIR/home/alpha"
DEPLOY_TARGET="$RUNTIME_HOME/app"
SANDBOX_PATH="$RUNTIME_HOME/state"
CROSS_COMPONENT_PATH="$RUNTIME_HOME/cross-component"
PRIVATE_ENV="$SANDBOX_PATH/env"
SYSTEM_ROOT="$TMP_DIR/etc/systemd/system"
mkdir -p "$DEPLOY_TARGET/systemd" "$SANDBOX_PATH" "$CROSS_COMPONENT_PATH/child" \
  "$SYSTEM_ROOT" "$TMP_DIR/bin"
printf '%s\n' 'PRIVATE_LISTENER=tailnet-only-value' > "$PRIVATE_ENV"
printf '%s\n' 'exit 0' > "$DEPLOY_TARGET/server.sh"
chmod +x "$DEPLOY_TARGET/server.sh"
printf '%s\n' 'Environment=PRIVATE_LISTENER=legacy-private-value' > "$SYSTEM_ROOT/alpha.service"
EXEC_SYMLINK="$TMP_DIR/system-sh"
ln -s /bin/sh "$EXEC_SYMLINK"

cat > "$DEPLOY_TARGET/systemd/alpha.service" << EOF
[Unit]
Description=Clean-install template
[Service]
User=<user>
WorkingDirectory=<deploy-path>
EnvironmentFile=<home>/state/env
ExecStart=$EXEC_SYMLINK <deploy-path>/server.sh
ReadWritePaths=<home>/state
ReadOnlyPaths=<home>/cross-component
EOF

cat > "$TMP_DIR/bin/getent" << 'EOF'
#!/usr/bin/env bash
[[ "$1" == "passwd" && "$2" == "alpha" ]]
printf 'alpha:x:1000:1000:Alpha:%s:/bin/sh\n' "$RUNTIME_HOME"
EOF

SYSTEMD_ANALYZE_CAPTURE="$TMP_DIR/systemd-analyze"
export SYSTEMD_ANALYZE_CAPTURE
cat > "$TMP_DIR/bin/systemd-analyze" << 'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "${SYSTEMD_UNIT_PATH:-}" "$*" >> "$SYSTEMD_ANALYZE_CAPTURE"
if [[ "${SYSTEMD_ANALYZE_FAIL_SCOPE:-}" == "${1#--}" ]]; then
  printf 'synthetic %s unit verification failure\n' "$1" >&2
  exit 78
fi
EOF
chmod +x "$TMP_DIR/bin/getent" "$TMP_DIR/bin/systemd-analyze"

runtime_json=$(RUNTIME_HOME="$RUNTIME_HOME" DEPLOY_TARGET="$DEPLOY_TARGET" \
  PRIVATE_ENV="$PRIVATE_ENV" CROSS_COMPONENT_PATH="$CROSS_COMPONENT_PATH" node -e '
    process.stdout.write(JSON.stringify({
      user: "alpha",
      home: process.env.RUNTIME_HOME,
      deploy_target: process.env.DEPLOY_TARGET,
      environment_files: [process.env.PRIVATE_ENV],
      sandbox_paths: [process.env.CROSS_COMPONENT_PATH]
    }));
  ')
units_json='[{"name":"alpha","type":"service","scope":"system"}]'
persistent_json=$(SANDBOX_PATH="$SANDBOX_PATH" node -e \
  'process.stdout.write(JSON.stringify([process.env.SANDBOX_PATH]));')

if RUNTIME_HOME="$RUNTIME_HOME" PATH="$TMP_DIR/bin:$PATH" \
    SYSTEMD_SYSTEM_ROOT="$SYSTEM_ROOT" \
    bash "$RENDER_HELPER" "$DEPLOY_TARGET" "$runtime_json" "$units_json" "$persistent_json"; then
  pass "clean-install template renders and preflights"
else
  fail "clean-install template must render and preflight"
fi
if grep -Eq -- '^[^|]+:\|--system verify ' "$SYSTEMD_ANALYZE_CAPTURE"; then
  pass "system units are verified in system-manager scope before install"
else
  fail "system units must be verified in system-manager scope before install"
fi

rendered_unit="$SYSTEM_ROOT/alpha.service"
assert_file_contains "runtime user is rendered" "$rendered_unit" "User=alpha"
assert_file_contains "deploy target is rendered" "$rendered_unit" "WorkingDirectory=$DEPLOY_TARGET"
assert_file_contains "private environment path is retained" "$rendered_unit" "EnvironmentFile=$PRIVATE_ENV"
assert_file_contains "sandbox path is rendered" "$rendered_unit" "ReadWritePaths=$SANDBOX_PATH"
assert_file_contains "exact external dependency path is rendered" \
  "$rendered_unit" "ReadOnlyPaths=$CROSS_COMPONENT_PATH"
assert_file_contains "previous installed unit is retained for rollback" \
  "$rendered_unit.grimnir-previous" "PRIVATE_LISTENER=legacy-private-value"
pass "symlinked system executable is accepted after executable access validation"
if grep -Fq 'tailnet-only-value' "$rendered_unit"; then
  fail "private environment values must not be copied into the unit"
else
  pass "private environment values stay outside the rendered unit"
fi

VERIFY_FAIL_ROOT="$TMP_DIR/verify-fail-systemd"
mkdir -p "$VERIFY_FAIL_ROOT"
printf '%s\n' 'OLD-VERIFIED-UNIT' > "$VERIFY_FAIL_ROOT/alpha.service"
if RUNTIME_HOME="$RUNTIME_HOME" PATH="$TMP_DIR/bin:$PATH" \
    SYSTEMD_ANALYZE_FAIL_SCOPE=system SYSTEMD_SYSTEM_ROOT="$VERIFY_FAIL_ROOT" \
    bash "$RENDER_HELPER" "$DEPLOY_TARGET" "$runtime_json" "$units_json" "$persistent_json" \
    >"$TMP_DIR/verify-fail.out" 2>&1; then
  fail "systemd-analyze failure must fail the rendering phase"
else
  pass "systemd-analyze failure fails the rendering phase"
fi
if [[ "$(cat "$VERIFY_FAIL_ROOT/alpha.service")" == "OLD-VERIFIED-UNIT" &&
      ! -e "$VERIFY_FAIL_ROOT/alpha.service.grimnir-previous" ]]; then
  pass "systemd-analyze failure occurs before unit or rollback-snapshot mutation"
else
  fail "systemd-analyze failure must install nothing and create no rollback snapshot"
fi

user_units_json='[{"name":"alpha","type":"service","scope":"user"}]'
mkdir -p "$RUNTIME_HOME/.config/systemd/user"
if RUNTIME_HOME="$RUNTIME_HOME" PATH="$TMP_DIR/bin:$PATH" \
    SYSTEMD_SYSTEM_ROOT="$TMP_DIR/user-scope-unused" \
    bash "$RENDER_HELPER" "$DEPLOY_TARGET" "$runtime_json" "$user_units_json" "$persistent_json" \
    >"$TMP_DIR/user-verify.out" 2>&1 &&
    grep -Fq -- "--user verify " "$SYSTEMD_ANALYZE_CAPTURE"; then
  pass "user units are verified in user-manager scope"
else
  sed 's/^/    /' "$TMP_DIR/user-verify.out" >&2
  fail "user units must be verified in user-manager scope"
fi

bad_runtime_json=$(RUNTIME_HOME="$RUNTIME_HOME" DEPLOY_TARGET="$DEPLOY_TARGET" \
  PRIVATE_ENV="$PRIVATE_ENV" CROSS_COMPONENT_PATH="$CROSS_COMPONENT_PATH" node -e '
    process.stdout.write(JSON.stringify({
      user: "missing-user",
      home: process.env.RUNTIME_HOME,
      deploy_target: process.env.DEPLOY_TARGET,
      environment_files: [process.env.PRIVATE_ENV],
      sandbox_paths: [process.env.CROSS_COMPONENT_PATH]
    }));
  ')
if RUNTIME_HOME="$RUNTIME_HOME" PATH="$TMP_DIR/bin:$PATH" \
    SYSTEMD_SYSTEM_ROOT="$TMP_DIR/bad-systemd" \
    bash "$RENDER_HELPER" "$DEPLOY_TARGET" "$bad_runtime_json" "$units_json" "$persistent_json" \
    >"$TMP_DIR/bad-render.out" 2>&1; then
  fail "unknown rendered user must fail preflight"
else
  pass "unknown rendered user fails preflight"
fi
if [[ -e "$TMP_DIR/bad-systemd/alpha.service" ]]; then
  fail "failed preflight must not install a unit"
else
  pass "failed preflight installs no unit"
fi

valid_template="$TMP_DIR/valid-alpha.service"
cp "$DEPLOY_TARGET/systemd/alpha.service" "$valid_template"

assert_path_preflight_rejected() {
  local desc=$1 expected=$2 system_root="$TMP_DIR/rejected-${PASS}-${FAIL}"
  if RUNTIME_HOME="$RUNTIME_HOME" PATH="$TMP_DIR/bin:$PATH" \
      SYSTEMD_SYSTEM_ROOT="$system_root" \
      bash "$RENDER_HELPER" "$DEPLOY_TARGET" "$runtime_json" "$units_json" "$persistent_json" \
      >"$TMP_DIR/path-rejected.out" 2>&1; then
    fail "$desc must fail preflight"
  elif grep -Fq -- "$expected" "$TMP_DIR/path-rejected.out"; then
    pass "$desc fails preflight"
  else
    fail "$desc must report $expected"
  fi
  if [[ -e "$system_root/alpha.service" ]]; then
    fail "$desc must not install a unit"
  else
    pass "$desc installs no unit"
  fi
}

cat > "$DEPLOY_TARGET/systemd/alpha.service" << 'EOF'
[Service]
User=<user>
WorkingDirectory=<home>
EnvironmentFile=<home>/state/env
ExecStart=/bin/sh <deploy-path>/server.sh
ReadWritePaths=<home>/state
ReadOnlyPaths=<home>/cross-component
EOF
assert_path_preflight_rejected "mismatched WorkingDirectory" \
  "WorkingDirectory must equal registered deploy target"

outside_exec="$TMP_DIR/outside.sh"
printf '%s\n' 'exit 0' > "$outside_exec"
cat > "$DEPLOY_TARGET/systemd/alpha.service" << EOF
[Service]
User=<user>
WorkingDirectory=<deploy-path>
EnvironmentFile=<home>/state/env
ExecStart=/bin/sh $outside_exec
ReadWritePaths=<home>/state
ReadOnlyPaths=<home>/cross-component
EOF
assert_path_preflight_rejected "ExecStart path outside deploy target" \
  "ExecStart path is outside registered deploy target"

cat > "$DEPLOY_TARGET/systemd/alpha.service" << 'EOF'
[Service]
User=<user>
WorkingDirectory=<deploy-path>
EnvironmentFile=<home>/unregistered.env
ExecStart=/bin/sh <deploy-path>/server.sh
ReadWritePaths=<home>/state
ReadOnlyPaths=<home>/cross-component
EOF
assert_path_preflight_rejected "unregistered private environment file" \
  "EnvironmentFile is not registered"

cat > "$DEPLOY_TARGET/systemd/alpha.service" << 'EOF'
[Service]
User=<user>
WorkingDirectory=<deploy-path>
EnvironmentFile=<home>/state/env
ExecStart=/bin/sh <deploy-path>/server.sh
ReadWritePaths=<home>/unregistered-state
ReadOnlyPaths=<home>/cross-component
EOF
assert_path_preflight_rejected "unregistered sandbox path" \
  "ReadWritePaths path is outside registered roots"

cat > "$DEPLOY_TARGET/systemd/alpha.service" << 'EOF'
[Service]
User=<user>
WorkingDirectory=<deploy-path>
EnvironmentFile=<home>/state/env
ExecStart=/bin/sh <deploy-path>/server.sh
ReadWritePaths=<home>/state
ReadOnlyPaths=<home>/cross-component/child
EOF
assert_path_preflight_rejected "descendant of exact external dependency" \
  "ReadOnlyPaths path is outside registered roots"

cat > "$DEPLOY_TARGET/systemd/alpha.service" << 'EOF'
[Service]
User=<user>
WorkingDirectory=<deploy-path>
EnvironmentFile=<home>/state/env
ExecStart=/bin/sh <deploy-path>/server.sh
ReadWritePaths=<home>/state <home>/cross-component
ReadOnlyPaths=<home>/cross-component
EOF
assert_path_preflight_rejected "write access to exact external dependency" \
  "ReadWritePaths path is outside registered roots"

cp "$valid_template" "$DEPLOY_TARGET/systemd/alpha.service"

# A later install failure must restore every already-replaced unit so a future
# daemon-reload cannot activate a mixed old/new set.
MULTI_TARGET="$RUNTIME_HOME/multi-app"
MULTI_SYSTEM_ROOT="$TMP_DIR/multi-systemd"
mkdir -p "$MULTI_TARGET/systemd" "$MULTI_SYSTEM_ROOT"
printf '%s\n' 'exit 0' > "$MULTI_TARGET/server.sh"
chmod +x "$MULTI_TARGET/server.sh"
for unit in alpha beta; do
  cat > "$MULTI_TARGET/systemd/${unit}.service" << EOF
[Service]
User=<user>
WorkingDirectory=<deploy-path>
EnvironmentFile=<home>/state/env
ExecStart=$EXEC_SYMLINK <deploy-path>/server.sh
ReadWritePaths=<home>/state
ReadOnlyPaths=<home>/cross-component
EOF
  printf 'OLD-%s\n' "$unit" > "$MULTI_SYSTEM_ROOT/${unit}.service"
done
multi_runtime_json=$(RUNTIME_HOME="$RUNTIME_HOME" MULTI_TARGET="$MULTI_TARGET" \
  PRIVATE_ENV="$PRIVATE_ENV" CROSS_COMPONENT_PATH="$CROSS_COMPONENT_PATH" node -e '
    process.stdout.write(JSON.stringify({
      user: "alpha",
      home: process.env.RUNTIME_HOME,
      deploy_target: process.env.MULTI_TARGET,
      environment_files: [process.env.PRIVATE_ENV],
      sandbox_paths: [process.env.CROSS_COMPONENT_PATH]
    }));
  ')
multi_units_json='[
  {"name":"alpha","type":"service","scope":"system"},
  {"name":"beta","type":"service","scope":"system"}
]'
REAL_INSTALL=$(command -v install)
INSTALL_COUNT="$TMP_DIR/install-count"
export REAL_INSTALL INSTALL_COUNT
cat > "$TMP_DIR/bin/install" << 'EOF'
#!/usr/bin/env bash
count=0
[[ -f "$INSTALL_COUNT" ]] && count=$(cat "$INSTALL_COUNT")
count=$((count + 1))
printf '%s\n' "$count" > "$INSTALL_COUNT"
[[ "$count" -eq 2 ]] && exit 91
exec "$REAL_INSTALL" "$@"
EOF
chmod +x "$TMP_DIR/bin/install"
if RUNTIME_HOME="$RUNTIME_HOME" PATH="$TMP_DIR/bin:$PATH" \
    SYSTEMD_SYSTEM_ROOT="$MULTI_SYSTEM_ROOT" \
    bash "$RENDER_HELPER" "$MULTI_TARGET" "$multi_runtime_json" \
      "$multi_units_json" "$persistent_json" >"$TMP_DIR/partial-install.out" 2>&1; then
  fail "second unit install failure must fail rendering phase"
else
  pass "second unit install failure fails rendering phase"
fi
if grep -E -- '--system verify .*alpha\.service .*beta\.service' \
    "$SYSTEMD_ANALYZE_CAPTURE" >/dev/null; then
  pass "each scope is verified as one complete rendered unit set"
else
  fail "systemd-analyze must receive the complete rendered unit set for its scope"
fi
if [[ "$(cat "$MULTI_SYSTEM_ROOT/alpha.service")" == "OLD-alpha" &&
      "$(cat "$MULTI_SYSTEM_ROOT/beta.service")" == "OLD-beta" ]]; then
  pass "partial install failure restores the complete previous unit set"
else
  fail "partial install failure must not leave a mixed unit set"
fi
rm -f "$TMP_DIR/bin/install" "$INSTALL_COUNT"

# Full deploy regression: once mutation begins, render/preflight failure must
# leave the accepted marker absent and must prevent any restart round trip.
REPO="$TMP_DIR/repos/alpha"
mkdir -p "$REPO/systemd"
cp "$DEPLOY_TARGET/systemd/alpha.service" "$REPO/systemd/alpha.service"
printf '%s\n' '{"name":"alpha","version":"1.0.0"}' > "$REPO/package.json"
printf '%s\n' 'exit 0' > "$REPO/server.sh"
git init -q -b main "$REPO"
git -C "$REPO" add .
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$REPO" commit -q -m seed
REPO_SHA=$(git -C "$REPO" rev-parse HEAD)
ALPHA_REQUEST="alpha=$REPO@$REPO_SHA"

registry="$TMP_DIR/services.json"
RUNTIME_HOME="$RUNTIME_HOME" PRIVATE_ENV="$PRIVATE_ENV" SANDBOX_PATH="$SANDBOX_PATH" \
  node - "$registry" <<'NODE'
const fs = require("fs");
fs.writeFileSync(process.argv[2], JSON.stringify({
  components: [{
    name: "alpha",
    repo: "alpha",
    host: "h1",
    port: 3030,
    deploy: true,
    scan: false,
    deploy_path: process.env.RUNTIME_HOME + "/app",
    persistent_paths: [process.env.SANDBOX_PATH],
    needs_build: false,
    systemd_runtime: {
      user: "missing-user",
      home: process.env.RUNTIME_HOME,
      deploy_target: process.env.RUNTIME_HOME + "/app",
      environment_files: [process.env.PRIVATE_ENV],
      sandbox_paths: [process.env.SANDBOX_PATH]
    },
    health_check: { boundary: "network", host: "health-h1", paths: ["/health"] },
    systemd_units: [{ name: "alpha", type: "service", scope: "system" }]
  }]
}, null, 2));
NODE

ORDER_CAPTURE="$TMP_DIR/order"
REMOTE_MARKER_STATE="$TMP_DIR/marker"
SSH_CAPTURE="$TMP_DIR/ssh"
export ORDER_CAPTURE REMOTE_MARKER_STATE SSH_CAPTURE
printf '%040d\n' 1 > "$REMOTE_MARKER_STATE"

cat > "$TMP_DIR/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SSH_CAPTURE"
command=${*: -1}
if [[ "$command" == *"DEPLOY_MARKER_INVALIDATED"* ]]; then
  printf '%s\n' invalidate >> "$ORDER_CAPTURE"
  prior=$(cat "$REMOTE_MARKER_STATE")
  rm -f "$REMOTE_MARKER_STATE"
  printf 'DEPLOY_MARKER_INVALIDATED:%s\n' "$prior"
elif [[ "$command" == *"rm -rf --"*"/.git"* ]]; then
  printf '%s\n' prepare >> "$ORDER_CAPTURE"
elif [[ "$command" == *"npm ci --omit=dev"* ]]; then
  printf '%s\n' npm >> "$ORDER_CAPTURE"
elif [[ "$*" == *"bash -s --"* ]]; then
  cat >/dev/null
  printf '%s\n' preflight >> "$ORDER_CAPTURE"
  printf '%s\n' verify >> "$ORDER_CAPTURE"
  if [[ "${SSH_SYSTEMD_VERIFY_FAIL:-false}" == "true" ]]; then
    printf '%s\n' 'ERROR: systemd-analyze verify failed for system units' >&2
    exit 1
  fi
  printf '%s\n' SYSTEMD_UNITS_PREPARED
elif [[ "$command" == *"systemctl"*"restart"* ]]; then
  printf '%s\n' restart >> "$ORDER_CAPTURE"
  [[ "$command" == *"DEPLOY_READY"* ]] && printf '%s\n' DEPLOY_READY
elif [[ "$command" == *".deployed-commit"*"DEPLOY_OK"* ]]; then
  printf '%s\n' stamp >> "$ORDER_CAPTURE"
  printf '%s\n' accepted > "$REMOTE_MARKER_STATE"
  printf '%s\n' DEPLOY_OK
fi
exit 0
EOF

cat > "$TMP_DIR/bin/rsync" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' rsync >> "$ORDER_CAPTURE"
exit 0
EOF

cat > "$TMP_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "curl:$*" >> "$ORDER_CAPTURE"
exit 0
EOF
chmod +x "$TMP_DIR/bin/ssh" "$TMP_DIR/bin/rsync" "$TMP_DIR/bin/curl"

rc=0
SSH_SYSTEMD_VERIFY_FAIL=true REGISTRY_PATH="$registry" LOCAL_REPOS_ROOT="$TMP_DIR/repos" PATH="$TMP_DIR/bin:$PATH" \
  bash "$DEPLOY" "$ALPHA_REQUEST" >"$TMP_DIR/deploy.out" 2>&1 || rc=$?
if [[ "$rc" == 1 ]]; then
  pass "systemd verification failure fails deployment"
else
  fail "systemd verification failure must fail deployment"
fi
if [[ ! -e "$REMOTE_MARKER_STATE" ]]; then
  pass "systemd verification failure leaves accepted marker absent"
else
  fail "systemd verification failure must leave accepted marker absent"
fi
if grep -Fxq verify "$ORDER_CAPTURE" && ! grep -Fxq restart "$ORDER_CAPTURE"; then
  pass "systemd verification failure occurs before restart"
else
  fail "systemd verification failure must prevent restart"
fi
if grep -Fq 'curl:' "$ORDER_CAPTURE"; then
  fail "network health must not run after systemd verification failure"
else
  pass "network health is skipped after systemd verification failure"
fi

# A valid rendered deployment must probe the explicit consumer-health host
# from the deploy client, independently of the SSH endpoint, before repairing
# the accepted marker.
node - "$registry" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
data.components[0].systemd_runtime.user = "alpha";
fs.writeFileSync(file, JSON.stringify(data, null, 2));
NODE
rm -f "$ORDER_CAPTURE" "$SSH_CAPTURE" "$REMOTE_MARKER_STATE"
printf '%040d\n' 2 > "$REMOTE_MARKER_STATE"
if REGISTRY_PATH="$registry" LOCAL_REPOS_ROOT="$TMP_DIR/repos" PATH="$TMP_DIR/bin:$PATH" \
    bash "$DEPLOY" "$ALPHA_REQUEST" >"$TMP_DIR/deploy-success.out" 2>&1; then
  pass "rendered deployment passes network-boundary health"
else
  fail "rendered deployment must pass network-boundary health"
fi
if grep -Fq 'curl:-fsS --max-time 3 http://health-h1:3030/health' "$ORDER_CAPTURE"; then
  pass "health is verified from the deploy client against the explicit health host"
else
  fail "network health must use the explicit health host and registered port"
fi
if grep -Fq 'magnus@h1' "$SSH_CAPTURE" &&
    ! grep -Fq 'magnus@health-h1' "$SSH_CAPTURE"; then
  pass "health host is independent of the SSH deployment host"
else
  fail "SSH transport must continue using the component host"
fi
preflight_line=$(grep -n '^preflight$' "$ORDER_CAPTURE" | cut -d: -f1)
restart_line=$(grep -n '^restart$' "$ORDER_CAPTURE" | cut -d: -f1)
curl_line=$(grep -n '^curl:' "$ORDER_CAPTURE" | cut -d: -f1)
stamp_line=$(grep -n '^stamp$' "$ORDER_CAPTURE" | cut -d: -f1)
if [[ -n "$preflight_line" && -n "$restart_line" && -n "$curl_line" && -n "$stamp_line" ]] &&
   [[ "$preflight_line" -lt "$restart_line" && "$restart_line" -lt "$curl_line" &&
      "$curl_line" -lt "$stamp_line" ]]; then
  pass "preflight, restart, network health, and acceptance stamp are ordered"
else
  fail "acceptance ordering must be preflight -> restart -> network health -> stamp"
fi
if [[ "$(cat "$REMOTE_MARKER_STATE")" == "accepted" ]]; then
  pass "marker is repaired only after network health succeeds"
else
  fail "successful network-boundary deployment must repair the marker"
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
