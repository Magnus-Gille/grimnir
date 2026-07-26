#!/usr/bin/env bash

# Quote one argument for a POSIX shell. The output is safe to interpolate into
# the command string passed to ssh or rsync's remote shell.
posix_shell_quote() {
  local value=$1 quoted="'"
  while [[ "$value" == *"'"* ]]; do
    quoted+="${value%%\'*}'\\''"
    value="${value#*\'}"
  done
  printf "%s%s'" "$quoted" "$value"
}

# Registry-declared unit sources are installed byte-for-byte. Angle-bracket
# identifiers have no rendering semantics in Grimnir and indicate that a
# component-owned template was selected instead of an install-ready unit.
# Comments may document placeholders without making the unit unsafe.
unit_template_token_awk() {
  local render_enabled=${1:-false}
  local allowed=''
  if [[ "$render_enabled" == "true" ]]; then
    allowed=' token != "<user>" && token != "<home>" && token != "<deploy-path>" && token != "<install-dir>" &&'
  fi
  # shellcheck disable=SC2016 # emitted for awk, not expanded by this shell
  printf '%s' '/^[[:space:]]*[#;]/ { next } { rest=$0; while (match(rest, /<[A-Za-z][A-Za-z0-9_-]*>/)) { token=substr(rest, RSTART, RLENGTH); if ('
  printf '%s' "${allowed:-1 &&}"
  printf '%s' ' 1) { print token; exit } rest=substr(rest, RSTART + RLENGTH) } }'
}

resolve_local_unit_source() {
  local repo_path=$1 unit_file=$2 candidate
  for candidate in "$repo_path/systemd/$unit_file" "$repo_path/$unit_file"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

preflight_local_install_ready_unit_source() {
  local repo_path=$1 unit_file=$2 required=${3:-true} render_enabled=${4:-false}
  local source token

  if ! source=$(resolve_local_unit_source "$repo_path" "$unit_file"); then
    if [[ "$required" == "true" ]]; then
      printf 'ERROR: install-ready unit source missing: %s (looked in %s/systemd and %s)\n' \
        "$unit_file" "$repo_path" "$repo_path" >&2
      return 1
    fi
    return 0
  fi

  token=$(awk "$(unit_template_token_awk "$render_enabled")" "$source")
  if [[ -n "$token" ]]; then
    printf 'ERROR: unit source is not install-ready: %s (unit %s contains unresolved placeholder %s)\n' \
      "$source" "$unit_file" "$token" >&2
    return 1
  fi
}

# Emit the equivalent guard for the source selected on the remote host. This
# covers git-pull deployments and prevents a source change between local
# preflight and install from bypassing the byte-for-byte unit contract.
prepare_remote_install_ready_unit_check_command() {
  local source_var=$1 unit_file=$2 quoted_awk quoted_label
  case "$source_var" in
    unit_src|companion_src) ;;
    *) return 1 ;;
  esac
  quoted_awk=$(posix_shell_quote "$(unit_template_token_awk)")
  quoted_label=$(posix_shell_quote "$unit_file")

  # shellcheck disable=SC2016 # command substitution and source variable expand remotely
  printf '%s_placeholder=$(awk %s "$%s"); ' "$source_var" "$quoted_awk" "$source_var"
  printf '[ -z "$%s_placeholder" ] || { printf '\''ERROR: unit source is not install-ready: %%s (unit %%s contains unresolved placeholder %%s)\\n'\'' "$%s" %s "$%s_placeholder" >&2; exit 1; }' \
    "$source_var" "$source_var" "$quoted_label" "$source_var"
}

# Extract the directives a byte-for-byte unit's [Service] section declares
# that matter for issue #146 (the deploy that rsynced code to one path and
# installed a unit pointing systemd at another, then restarted a healthy
# service into a broken one). Prints exactly:
#   line 1:            the last WorkingDirectory= value, or empty
#   0+ following lines: "ENV:<value>" for each EnvironmentFile= value, in
#                       declaration order, with a leading "-" (systemd's
#                       "optional file" marker) stripped
#   last line:          "USER:<value>", the last User= value, or "USER:"
# Only [Service] is inspected; [Unit]/[Install]/[Timer] directives are
# irrelevant to WorkingDirectory/EnvironmentFile/User semantics.
unit_service_directives() {
  local source=$1
  SOURCE_PATH="$source" node --input-type=commonjs -e '
    var fs = require("fs");
    var text = fs.readFileSync(process.env.SOURCE_PATH, "utf8");
    var section = "";
    var workingDirectory = "";
    var user = "";
    var environmentFiles = [];
    text.split(/\r?\n/).forEach(function (raw) {
      var line = raw.trim();
      if (!line || line[0] === "#" || line[0] === ";") return;
      var sectionMatch = line.match(/^\[([A-Za-z]+)\]$/);
      if (sectionMatch) { section = sectionMatch[1]; return; }
      if (section !== "Service") return;
      var equals = line.indexOf("=");
      if (equals < 1) return;
      var key = line.slice(0, equals).trim();
      var value = line.slice(equals + 1).trim();
      if (key === "WorkingDirectory") {
        workingDirectory = value;
      } else if (key === "User") {
        user = value;
      } else if (key === "EnvironmentFile") {
        value.split(/\s+/).forEach(function (token) {
          if (!token) return;
          if (token[0] === "-") token = token.slice(1);
          environmentFiles.push(token);
        });
      }
    });
    process.stdout.write(workingDirectory + "\n");
    environmentFiles.forEach(function (file) { process.stdout.write("ENV:" + file + "\n"); });
    process.stdout.write("USER:" + user + "\n");
  '
}

# Parse unit_service_directives output (see above) into the caller's
# variables: WORKING_DIRECTORY (string), ENV_FILES (array), UNIT_USER
# (string). Bash has no multi-value return, so callers source this into their
# own locals via the printed lines.
read_unit_service_directives() {
  local source=$1 line first=true
  WORKING_DIRECTORY=""
  ENV_FILES=()
  UNIT_USER=""
  while IFS= read -r line; do
    if $first; then
      WORKING_DIRECTORY=$line
      first=false
    elif [[ "$line" == ENV:* ]]; then
      ENV_FILES+=("${line#ENV:}")
    elif [[ "$line" == USER:* ]]; then
      UNIT_USER="${line#USER:}"
    fi
  done < <(unit_service_directives "$source")
}

# A byte-for-byte unit's WorkingDirectory/EnvironmentFile are literal paths
# (unlike render_enabled units, which use <deploy-path>/<home> placeholders
# resolved and validated against the registry at render time). Refuse a
# deploy before ANY remote call -- before host resolution, marker
# invalidation, build, or rsync -- when either directive does not resolve
# under this component's registry deploy_path. This is the exact munin-memory
# incident (issue #146): services.json said deploy_path=/home/magnus/munin-
# memory, the owning repo's unit said WorkingDirectory=/srv/grimnir/munin-
# memory, and nothing refused the contradiction before systemd was told to
# restart into a path that did not exist on the host.
preflight_unit_target_containment() {
  local source=$1 unit_file=$2 deploy_path=$3 component=$4
  local WORKING_DIRECTORY ENV_FILES env_file
  # shellcheck disable=SC2034 # set by read_unit_service_directives; User= is not a path, unused here
  local UNIT_USER

  read_unit_service_directives "$source"

  if [[ -n "$WORKING_DIRECTORY" && "$WORKING_DIRECTORY" == /* ]] &&
     [[ "$WORKING_DIRECTORY" != "$deploy_path" && "$WORKING_DIRECTORY" != "$deploy_path"/* ]]; then
    printf 'ERROR: unit %s (component %s) declares WorkingDirectory=%s, which does not resolve under the registry deploy_path %s. A deploy that rsyncs code to %s and installs a unit pointing at %s must never restart the service -- reconcile services.json and the unit before redeploying (issue #146).\n' \
      "$unit_file" "$component" "$WORKING_DIRECTORY" "$deploy_path" "$deploy_path" "$WORKING_DIRECTORY" >&2
    return 1
  fi

  for env_file in "${ENV_FILES[@]+"${ENV_FILES[@]}"}"; do
    if [[ "$env_file" == /* ]] &&
       [[ "$env_file" != "$deploy_path" && "$env_file" != "$deploy_path"/* ]]; then
      printf 'ERROR: unit %s (component %s) declares EnvironmentFile=%s, which does not resolve under the registry deploy_path %s. A deploy that rsyncs code to %s and installs a unit pointing at %s must never restart the service -- reconcile services.json and the unit before redeploying (issue #146).\n' \
        "$unit_file" "$component" "$env_file" "$deploy_path" "$deploy_path" "$env_file" >&2
      return 1
    fi
  done
}

# Build the remote-shell fragment that runs immediately before a byte-for-
# byte unit is installed: preflight the declared User (system scope only --
# a user-scope unit already runs as the deploying account, so User= there is
# not a privilege boundary) and every declared EnvironmentFile, then back up
# whatever unit is currently at $dest (a remote-shell variable the caller
# must set before splicing this fragment in) to a predictable, timestamped
# path and print it. The returned fragment ends in "&& " so callers chain it
# directly ahead of the install command. All three checks -- and the backup
# -- run strictly before install, which runs strictly before daemon-reload
# and restart, so a violation or missing dependency never stops a running
# service (issue #146).
prepare_unit_target_preflight_and_backup_command() {
  local privileged=$1 unit_file=$2 user=$3
  shift 3
  local env_files=("$@")
  local sudo_prefix='' env_file q_check fail_msg

  [[ "$privileged" == "true" ]] && sudo_prefix='sudo '

  if [[ "$privileged" == "true" && -n "$user" ]]; then
    q_check=$(posix_shell_quote "$user")
    fail_msg=$(posix_shell_quote "ERROR: unit ${unit_file} declares User=${user} which does not exist on the deploy target")
    printf 'getent passwd %s >/dev/null || { echo %s >&2; exit 1; }; ' "$q_check" "$fail_msg"
  fi

  for env_file in "${env_files[@]+"${env_files[@]}"}"; do
    [[ -n "$env_file" ]] || continue
    q_check=$(posix_shell_quote "$env_file")
    fail_msg=$(posix_shell_quote "ERROR: unit ${unit_file} requires EnvironmentFile=${env_file} which is not present on the deploy target")
    printf '[ -f %s ] || { echo %s >&2; exit 1; }; ' "$q_check" "$fail_msg"
  done

  fail_msg=$(posix_shell_quote "ERROR: failed to back up existing unit ${unit_file} before install")
  # shellcheck disable=SC2016 # $dest/$backup/$(date ...) expand on the remote host, not now
  printf '%s' "if ${sudo_prefix}test -f \"\$dest\"; then "
  # shellcheck disable=SC2016 # $dest/$(date ...) expand on the remote host, not now
  printf '%s' 'backup="$dest.bak.$(date -u +%Y%m%dT%H%M%SZ)"; '
  printf '%s' "${sudo_prefix}cp -p -- \"\$dest\" \"\$backup\" || { echo ${fail_msg} >&2; exit 1; }; "
  # shellcheck disable=SC2016 # $dest/$backup expand on the remote host, not now
  printf '%s' 'echo "Backed up prior unit: $dest -> $backup"; '
  printf '%s' 'fi && '
}

# Rsync deployments are release directories, never Git checkouts. Remove any
# stale repository metadata before syncing: `.git` can be either a directory or
# a worktree pointer file, and leaving the latter can point the Pi at a path
# that only exists on the developer laptop.
prepare_rsync_destination_command() {
  local deploy_path=$1 quoted_path
  quoted_path=$(posix_shell_quote "$deploy_path")
  printf 'mkdir -p %s && rm -rf -- %s/.git' "$quoted_path" "$quoted_path"
}

# Build the remote command that transitions a deploy target from an accepted
# commit to "unknown" before code can change. A prior valid full SHA is emitted
# for the operator's rollback log; malformed/missing markers become `unknown`.
prepare_deploy_marker_invalidation_command() {
  local deploy_path=$1 quoted_marker
  quoted_marker=$(posix_shell_quote "${deploy_path}/.deployed-commit")
  printf 'marker=%s; prior=unknown; ' "$quoted_marker"
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' 'if [ -f "$marker" ] && [ ! -L "$marker" ]; then candidate=$(tr -d '\''\r\n'\'' < "$marker") || exit 1; case "$candidate" in ""|*[!0-9a-fA-F]*) ;; *) candidate_len=${#candidate}; if [ "$candidate_len" -ge 40 ] && [ "$candidate_len" -le 64 ]; then prior=$candidate; fi ;; esac; fi; '
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' 'rm -f -- "$marker" || exit 1; if [ -e "$marker" ] || [ -L "$marker" ]; then printf '\''ERROR: deploy marker invalidation failed\n'\'' >&2; exit 1; fi; '
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' 'printf '\''DEPLOY_MARKER_INVALIDATED:%s\n'\'' "$prior"'
}

# Shared awk predicate for recurring timer acceptance. At least one realtime or
# monotonic next-elapse property must contain a concrete trigger; active timers
# whose only values are empty/infinity/n/a/0 are elapsed, not scheduled.
recurring_timer_next_check_awk() {
  # shellcheck disable=SC2016 # emitted for awk, not expanded by this shell
  printf '%s' '/^NextElapseUSec(Realtime|Monotonic)=/ && $2 != "" && $2 != "0" && $2 != "infinity" && $2 != "n/a" { scheduled=1 } END { exit(scheduled ? 0 : 1) }'
}

# Build a bounded remote-shell gate for recurring timers. A timer using
# OnUnitInactiveSec can legitimately have no next trigger while its companion
# oneshot is still running immediately after restart. Poll long enough for that
# transition, but continue to reject permanently elapsed/unscheduled timers.
prepare_recurring_timer_next_check_command() {
  local scope=$1 timer_unit=$2 manager quoted_unit quoted_label quoted_awk

  case "$scope" in
    user) manager='systemctl --user' ;;
    system) manager='sudo systemctl' ;;
    *) return 1 ;;
  esac

  quoted_unit=$(posix_shell_quote "$timer_unit")
  quoted_label=$(posix_shell_quote "$timer_unit")
  quoted_awk=$(posix_shell_quote "$(recurring_timer_next_check_awk)")

  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' '{ timer_scheduled=false; timer_attempt=1; while [ "$timer_attempt" -le 30 ]; do if '
  printf '%s show %s --property=NextElapseUSecRealtime --property=NextElapseUSecMonotonic | awk -F= %s; then ' \
    "$manager" "$quoted_unit" "$quoted_awk"
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' 'timer_scheduled=true; break; fi; sleep 1; timer_attempt=$((timer_attempt + 1)); done; '
  # shellcheck disable=SC2016 # variables expand on the remote host
  printf '%s' '[ "$timer_scheduled" = true ] || { printf '\''ERROR: recurring timer has no concrete next trigger: %s\n'\'' '
  printf '%s >&2; exit 1; }; }' "$quoted_label"
}
