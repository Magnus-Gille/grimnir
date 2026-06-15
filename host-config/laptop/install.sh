#!/usr/bin/env bash
#
# install.sh — install the laptop-local Grimnir Homebrew maintenance job.
# Idempotent. Run on Magnus's macOS laptop:  host-config/laptop/install.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
AGENT_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/.local/share/grimnir-maintenance/logs"
PLIST="com.magnusgille.brew-update.plist"
LABEL="com.magnusgille.brew-update"

mkdir -p "$BIN_DIR" "$AGENT_DIR" "$LOG_DIR"

install -m755 "$SRC_DIR/grimnir-brew-update.sh" "$BIN_DIR/grimnir-brew-update.sh"
install -m644 "$SRC_DIR/$PLIST" "$AGENT_DIR/$PLIST"

# Reload the LaunchAgent.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_DIR/$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"

echo "Installed $LABEL (weekly Sunday 11:00)."
echo "Run now with: launchctl kickstart -k gui/$(id -u)/$LABEL"
