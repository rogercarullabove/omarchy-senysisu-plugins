#!/bin/bash
#
# install-airplane-mode-plugin.sh
#
# Installs the VERIFIED WORKING roger.airplane-mode bar-widget plugin —
# pulled directly from a confirmed-functional install (2026-08-29).
#
# Single Panel.qml as the barWidget entry point (not a separate
# BarWidget.qml), plus Model.js for icon/tooltip logic — matches Omarchy's
# real plugin structure (see README for why this matters).
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="roger.airplane-mode"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

echo "==> Installing backing scripts to ~/.local/bin"
mkdir -p "$HOME/.local/bin"
cp "$SRC_DIR/omarchy-airplane-mode-data" "$HOME/.local/bin/omarchy-airplane-mode-data"
cp "$SRC_DIR/omarchy-airplane-mode-toggle" "$HOME/.local/bin/omarchy-airplane-mode-toggle"
chmod +x "$HOME/.local/bin/omarchy-airplane-mode-data" "$HOME/.local/bin/omarchy-airplane-mode-toggle"

echo "==> Testing data script output"
"$HOME/.local/bin/omarchy-airplane-mode-data"

echo "==> Installing plugin files to $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp "$SRC_DIR/roger.airplane-mode/manifest.json" "$PLUGIN_DIR/"
cp "$SRC_DIR/roger.airplane-mode/Panel.qml" "$PLUGIN_DIR/"
cp "$SRC_DIR/roger.airplane-mode/Model.js" "$PLUGIN_DIR/"

echo "==> Validating plugin"
if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin validate "$PLUGIN_DIR" || echo "    (validation reported issues — see above)"
fi

echo "==> Enabling the plugin, placed right after omarchy.weather in the center section"
if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin enable "$PLUGIN_ID" --section center --after omarchy.weather
fi

echo "==> Forcing a full shell restart (a plain rescan was NOT enough during testing)"
if command -v omarchy >/dev/null 2>&1; then
    omarchy restart shell
    sleep 3
fi

echo "==> Confirming plugin is enabled and placed in the bar"
if command -v omarchy >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    omarchy plugin list --json | jq --arg id "$PLUGIN_ID" '.[] | select(.id == $id)'
fi

echo ""
echo "Done. Check the bar for the plane icon just right of the weather pill."
echo "Click it to toggle WiFi + Bluetooth + LTE off together; click again to"
echo "restore each to whatever it was before."
echo ""
echo "Note: 'active' in the listing above is expected to read false — that"
echo "field is only ever true for a whole-bar (kind: \"bar\") plugin, never"
echo "for a bar-widget. 'enabled: true' plus the icon actually showing in the"
echo "bar is the real signal. If nothing appears, check:"
echo "  qs log -p \"\$OMARCHY_PATH/shell\" --tail 100"
