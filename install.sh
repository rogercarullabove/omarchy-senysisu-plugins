#!/bin/bash
#
# install.sh <plugin-id> [--section left|center|right] [--before|--after <widget-id>]
#
# Installs one of this repo's Omarchy bar-widget plugins: copies its
# backing scripts (plugin-dir/bin/*) into ~/.local/bin, its manifest.json
# and every *.qml/*.js file into ~/.config/omarchy/plugins/<plugin-id>,
# validates it, enables it (in --section if given, placed before/after
# another widget if given, otherwise appended to whatever section its
# manifest's defaultSection says), forces a full shell restart, and confirms.
#
# Examples:
#   ./install.sh senysisu.airplane-mode --after omarchy.weather
#   ./install.sh senysisu.lte
#   ./install.sh senysisu.cpu --section left
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 <bar-widget-plugin-id> [--section left|center|right] [--before|--after <widget-id>]" >&2
    echo "       $0 senysisu.lock [--uninstall]" >&2
    echo "       $0 senysisu.plymouth [--preview|--uninstall]" >&2
    exit 1
}

PLUGIN_ID="${1:-}"
[[ -n "$PLUGIN_ID" ]] || usage
shift || true

PLUGIN_SRC="$SRC_DIR/$PLUGIN_ID"
[[ -d "$PLUGIN_SRC" ]] || { echo "Unknown plugin: $PLUGIN_ID (looked for $PLUGIN_SRC)" >&2; exit 1; }

# Plugins that aren't bar widgets (e.g. senysisu.lock) ship their own installer.
if [[ -f "$PLUGIN_SRC/install.sh" ]]; then
    exec bash "$PLUGIN_SRC/install.sh" "$@"
fi

# Placement flags are handed to `omarchy plugin enable` as-is; it validates
# them (one of --before/--after, section left/center/right).
PLACEMENT=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --section|--before|--after)
            [[ -n "${2:-}" ]] || usage
            PLACEMENT+=("$1" "$2")
            shift 2
            ;;
        *) usage ;;
    esac
done

echo "==> Installing backing scripts to ~/.local/bin"
mkdir -p "$HOME/.local/bin"
if [[ -d "$PLUGIN_SRC/bin" ]]; then
    for script in "$PLUGIN_SRC"/bin/*; do
        name="$(basename "$script")"
        cp "$script" "$HOME/.local/bin/$name"
        chmod +x "$HOME/.local/bin/$name"
        echo "    installed $name"
    done
fi

PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
echo "==> Installing plugin files to $PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
shopt -s nullglob
cp "$PLUGIN_SRC/manifest.json" "$PLUGIN_SRC"/*.qml "$PLUGIN_SRC"/*.js "$PLUGIN_DIR/"
shopt -u nullglob

echo "==> Validating plugin"
if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin validate "$PLUGIN_DIR" || echo "    (validation reported issues — see above)"
fi

echo "==> Enabling $PLUGIN_ID"
if command -v omarchy >/dev/null 2>&1; then
    # A plugin installed for the first time isn't known to the running shell
    # until it rescans, and `omarchy plugin enable` refuses unknown ids.
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    omarchy plugin enable "$PLUGIN_ID" "${PLACEMENT[@]}"
fi

echo "==> Forcing a full shell restart (a plain rescan has not been reliable — see README)"
if command -v omarchy >/dev/null 2>&1; then
    omarchy restart shell
    sleep 3
fi

echo "==> Confirming"
if command -v omarchy >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    omarchy plugin list --json | jq --arg id "$PLUGIN_ID" '.[] | select(.id == $id)'
fi

echo ""
echo "Done. 'active' in the listing above is expected to read false — see README"
echo "(that field only applies to whole-bar kind:\"bar\" plugins, never to a"
echo "bar-widget). 'enabled: true' plus the widget actually showing in the bar"
echo "is the real signal. If nothing shows up, check:"
echo "  qs log -p \"\$OMARCHY_PATH/shell\" --tail 100"
