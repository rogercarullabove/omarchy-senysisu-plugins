#!/bin/bash
#
# senysisu.lock/install.sh [--theme <choice>]
# senysisu.lock/install.sh --uninstall
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
# Theme and wallpaper: run from a terminal, it shows the current Omarchy
# theme and wallpaper, what settings.lua says, and the installed themes with
# how many wallpapers each has, and asks which to use. --theme answers
# without asking, the same as senysisu.plymouth/install.sh:
#
#   --theme lua             keep what settings.lua says (also the default
#                           when not run from a terminal)
#   --theme current         follow the current Omarchy theme, live
#   --theme <name>[,<n>]    that theme, with its n-th wallpaper (e.g. nord,2)
#
# The lock reads settings.lua live, so a choice is applied by writing it
# there as `theme` (current as nil).
#
# Also reachable through the repo's shared installer: ./install.sh senysisu.lock
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="senysisu.lock"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
PLUGIN_FILES=(manifest.json Service.qml LockView.qml WeatherBackdrop.qml settings-loader.lua theme-stage.sh README.md)

usage() {
    sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
    exit 1
}

MODE=install
THEME_CHOICE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
    --uninstall) MODE=uninstall ;;
    --theme) [[ -n ${2:-} ]] || usage; THEME_CHOICE=$2; shift ;;
    --theme=?*) THEME_CHOICE=${1#--theme=} ;;
    *) usage ;;
    esac
    shift
done

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

if [[ $MODE == uninstall ]]; then
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

# The prompt reads the installed settings.lua, or the repo default the first
# time. Asked before anything changes, so Ctrl+C here leaves things as they are.
SETTINGS_FILE="$PLUGIN_DIR/settings.lua"
[[ -f $SETTINGS_FILE ]] || SETTINGS_FILE="$SRC_DIR/settings.lua"
SCREEN_NAME="Lock screen"
CURRENT_NOTE="follows theme switches"
# shellcheck source=theme-choice.sh
source "$SRC_DIR/theme-choice.sh"
choose_theme "$THEME_CHOICE" || exit 1

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

SETTINGS_FILE="$PLUGIN_DIR/settings.lua"
if [[ $THEME_CHOICE != lua ]]; then save_theme "$THEME_CHOICE"; fi

# Stage a pinned theme once now, so a bad name or wallpaper number is
# reported here and not only in the journal when the lock shows.
if command -v lua >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    pinned_theme=$(lua "$PLUGIN_DIR/settings-loader.lua" "$PLUGIN_DIR/settings.lua" 2>/dev/null |
        jq -r '.theme | if type == "string" then . else "" end' 2>/dev/null || true)
    if [[ -n $pinned_theme ]]; then
        stage_dir=$(mktemp -d)
        if bash "$PLUGIN_DIR/theme-stage.sh" "$pinned_theme" "$stage_dir/out" 2>"$stage_dir/err"; then
            sed 's/^/    warning: /' "$stage_dir/err" >&2
            staged_wallpaper=$(readlink "$stage_dir/out/background" 2>/dev/null || true); staged_wallpaper=${staged_wallpaper##*/}
            echo "    theme: $pinned_theme (${staged_wallpaper:-no wallpaper})"
        else
            sed 's/^/    warning: /' "$stage_dir/err" >&2
            echo "    warning: the lock will follow the current theme instead" >&2
        fi
        rm -rf "$stage_dir"
    fi
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
