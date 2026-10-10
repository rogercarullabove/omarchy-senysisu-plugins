#!/bin/bash
#
# senysisu.lock/install.sh [--uninstall]
#
# Installs the senysisu.lock lock screen: copies this folder's plugin files to
# ~/.config/omarchy/plugins/senysisu.lock (keeping an existing settings.lua),
# validates it, swaps it in for the built-in omarchy.lock, restarts the
# shell, and confirms. --uninstall swaps back to omarchy.lock and leaves the
# installed files in place.
#
# If anything fails after the built-in lock was disabled, it is re-enabled,
# so the machine is never left without a lock screen.
#
# Also reachable through the repo's shared installer: ./install.sh senysisu.lock
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="senysisu.lock"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
PLUGIN_FILES=(manifest.json Service.qml LockView.qml WeatherBackdrop.qml settings-loader.lua README.md)

command -v omarchy >/dev/null 2>&1 || { echo "omarchy not found — this only installs on Omarchy." >&2; exit 1; }

# Swapping lock plugins disables the one holding the lock, which strands a
# locked session behind Hyprland's failsafe (easy to hit over ssh while the
# machine sits at its lock screen). Only install or uninstall when unlocked.
if omarchy-hyprland-session-locked 2>/dev/null ||
    [[ "$(omarchy-shell lock status 2>/dev/null | jq -r '.locked or .sessionLocked' 2>/dev/null)" == "true" ]]; then
    echo "The session is locked — unlock it first, then re-run this installer." >&2
    exit 1
fi

restore_builtin() {
    echo "!!  Install failed — re-enabling the built-in omarchy.lock" >&2
    omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
    omarchy plugin enable omarchy.lock >/dev/null 2>&1 || true
    omarchy restart shell >/dev/null 2>&1 || true
}

confirm() {
    if command -v jq >/dev/null 2>&1; then
        omarchy plugin list --json | jq -c '.[] | select(.id == "omarchy.lock" or .id == "senysisu.lock") | {id, enabled}'
    else
        omarchy plugin list | grep -i lock
    fi
}

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "==> Switching back to the built-in omarchy.lock"
    omarchy plugin disable "$PLUGIN_ID"
    omarchy plugin enable omarchy.lock
    omarchy restart shell
    sleep 3
    confirm
    echo "Done. Files remain in $PLUGIN_DIR; delete with: omarchy plugin remove $PLUGIN_ID"
    exit 0
fi

echo "==> Checking requirements"
missing=0
for cmd in lua curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "    missing: $cmd"
        missing=1
    fi
done
if ! fc-list : family | grep -i "Adwaita Sans" >/dev/null; then
    echo "    missing font: Adwaita Sans (clock falls back to another font)"
fi
if (( missing )); then
    echo "    lua is needed for settings.lua (defaults are used without it); curl + jq for weather."
    echo "    Install with: omarchy pkg add lua curl jq"
fi

echo "==> Installing plugin files to $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
for file in "${PLUGIN_FILES[@]}"; do
    cp "$SRC_DIR/$file" "$PLUGIN_DIR/"
done
rm -rf "$PLUGIN_DIR/assets"
cp -r "$SRC_DIR/assets" "$PLUGIN_DIR/assets"
if [[ -f "$PLUGIN_DIR/settings.lua" ]]; then
    echo "    kept existing settings.lua (repo default: $SRC_DIR/settings.lua)"
    if ! grep -q '^[[:space:]]*effects[[:space:]]*=' "$PLUGIN_DIR/settings.lua"; then
        echo "    note: your settings.lua has no 'effects' section, so weather effects run"
        echo "    with their defaults (mode = \"auto\"). Copy that section from the repo"
        echo "    default to configure them, or set mode = \"off\" there to disable."
    fi
else
    cp "$SRC_DIR/settings.lua" "$PLUGIN_DIR/"
    echo "    installed default settings.lua"
fi

echo "==> Validating plugin"
omarchy plugin validate "$PLUGIN_DIR" || echo "    (validation reported issues — see above)"

echo "==> Swapping in $PLUGIN_ID for omarchy.lock"
trap restore_builtin ERR
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin disable omarchy.lock
omarchy plugin enable "$PLUGIN_ID"

echo "==> Restarting the shell (the lock screen does not hot-reload its code)"
omarchy restart shell
sleep 3
[[ "$(omarchy-shell lock isLocked 2>/dev/null)" =~ ^(true|false)$ ]] || false
trap - ERR

echo "==> Confirming"
confirm

echo ""
echo "Done. Preview without locking: omarchy-shell lock preview (click to close)"
echo "Settings: $PLUGIN_DIR/settings.lua (applies live on save)"
echo "Undo:     $SRC_DIR/install.sh --uninstall"
