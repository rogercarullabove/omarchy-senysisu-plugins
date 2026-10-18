#!/bin/bash
#
# senysisu.plymouth/install.sh [--theme <choice>] [--preview]
# senysisu.plymouth/install.sh --uninstall
#
# Installs the senysisu boot screen: the disk-unlock prompt drawn like the
# senysisu.lock lock screen. Renders the theme from its own settings file,
#
#   ~/.config/omarchy/plugins/senysisu.plymouth/settings.lua
#
# (created from this folder's settings.lua the first time, separate from the
# lock screen's) and the current Omarchy theme (as you), then with sudo:
#
#   /usr/share/plymouth/themes/senysisu/          the theme
#   /etc/initcpio/{install,hooks}/senysisu-plymouth   clock feeder hook
#   /etc/mkinitcpio.conf.d/zz-senysisu-plymouth.conf  runs it after plymouth
#   /etc/senysisu-plymouth/clock.conf             date format for the hook
#   /etc/pacman.d/hooks/95-senysisu-plymouth.hook  re-selects the theme after
#   /usr/local/lib/senysisu-plymouth/reapply       omarchy-settings upgrades
#
# selects it, test-builds a throwaway initramfs to check it, and only then
# rebuilds the real boot images. Re-run after changing the wallpaper, theme
# or that settings.lua — the boot screen is a snapshot of them.
#
#   --preview    show it in a window first (no root, nothing installed)
#   --uninstall  go back to Omarchy's boot screen and remove everything above
#                (your settings.lua is kept)
#
# Theme and wallpaper: run from a terminal, it shows the current Omarchy
# theme and wallpaper, what settings.lua says, and the installed themes with
# how many wallpapers each has, and asks which to use. --theme answers
# without asking:
#
#   --theme lua             what settings.lua says (also the default when
#                           not run from a terminal)
#   --theme current         the current Omarchy theme and wallpaper
#   --theme <name>[,<n>]    that theme, with its n-th wallpaper (e.g. nord,2)
#
# A choice other than settings.lua's is saved there as its `theme` (current
# as nil), so the file keeps describing the installed boot screen. --preview
# uses the choice but never saves it.
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR=/usr/share/plymouth/themes/senysisu
HOOK_NAME=senysisu-plymouth
DROPIN=/etc/mkinitcpio.conf.d/zz-senysisu-plymouth.conf
PACMAN_HOOK=/etc/pacman.d/hooks/95-senysisu-plymouth.hook
REAPPLY=/usr/local/lib/senysisu-plymouth/reapply
CONF_DIR=/etc/senysisu-plymouth
SETTINGS_FILE="${SETTINGS_FILE:-$HOME/.config/omarchy/plugins/senysisu.plymouth/settings.lua}"

# First run: give the user their own copy of the settings to edit, with the
# command to re-run filled in. Never overwrites an existing one.
seed_settings() {
    [[ -f $SETTINGS_FILE ]] && return
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    sed "s|@INSTALL@|$SRC_DIR/install.sh|" "$SRC_DIR/settings.lua" >"$SETTINGS_FILE"
    echo "==> Created $SETTINGS_FILE"
    echo "    Edit it to change the boot screen, then re-run $0"
}

# Theme prompt, --theme handling and saving, shared with senysisu.lock.
SCREEN_NAME="Boot screen"
# shellcheck source=../senysisu.lock/theme-choice.sh
source "$SRC_DIR/../senysisu.lock/theme-choice.sh"

rebuild_boot_images() {
    echo "==> Rebuilding the boot images (this takes a little while)"
    if command -v limine-mkinitcpio >/dev/null; then
        sudo limine-mkinitcpio
    else
        sudo mkinitcpio -P
    fi
}

usage() {
    sed -n '3,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
    exit 1
}

MODE=install
THEME_CHOICE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
    --preview) MODE=preview ;;
    --uninstall) MODE=uninstall ;;
    --theme) [[ -n ${2:-} ]] || usage; THEME_CHOICE=$2; shift ;;
    --theme=?*) THEME_CHOICE=${1#--theme=} ;;
    *) usage ;;
    esac
    shift
done

case "$MODE" in
uninstall)
    echo "==> Switching back to Omarchy's boot screen"
    if [[ $(plymouth-set-default-theme) == senysisu ]]; then
        sudo plymouth-set-default-theme omarchy
    fi
    sudo rm -f "$PACMAN_HOOK" "$REAPPLY" "$DROPIN" \
        "/etc/initcpio/install/$HOOK_NAME" "/etc/initcpio/hooks/$HOOK_NAME"
    sudo rm -rf "$CONF_DIR" "$THEME_DIR" "$(dirname "$REAPPLY")"
    rebuild_boot_images
    echo "Done. The boot screen is Omarchy's again (omarchy plymouth set by theme <name> recolors it)."
    exit 0
    ;;
esac

# ---- Theme and wallpaper -----------------------------------------------------

seed_settings
choose_theme "$THEME_CHOICE" || exit 1
# render.sh draws the choice; "lua" leaves it to settings.lua.
if [[ $THEME_CHOICE != lua ]]; then export THEME_OVERRIDE=$THEME_CHOICE; fi

if [[ $MODE == preview ]]; then
    exec "$SRC_DIR/preview.sh"
fi

echo "==> Checking requirements"
for cmd in magick lua jq plymouth-set-default-theme mkinitcpio lsinitcpio; do
    command -v "$cmd" >/dev/null || { echo "    missing: $cmd" >&2; exit 1; }
done
magick -list format | grep -q PANGO || { echo "    ImageMagick has no Pango support" >&2; exit 1; }
# The hook only works in a busybox-based initramfs that starts plymouth with
# the plymouth hook (Omarchy's default); with systemd hooks it'd be skipped.
# shellcheck disable=SC1091
hooks=$(bash -c '. /etc/mkinitcpio.conf; for f in /etc/mkinitcpio.conf.d/*.conf; do [[ $f == *zz-senysisu-plymouth.conf ]] || . "$f"; done; echo " ${HOOKS[*]} "' 2>/dev/null)
if [[ $hooks != *" plymouth "* || $hooks == *" systemd "* ]]; then
    echo "    This needs the busybox 'plymouth' mkinitcpio hook (HOOKS:$hooks)" >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "==> Rendering the theme"
"$SRC_DIR/render.sh" "$work"

echo "==> Installing (sudo)"
sudo -v
sudo rm -rf "$THEME_DIR"
sudo install -d -m 755 "$THEME_DIR" "$CONF_DIR" "$(dirname "$REAPPLY")" /etc/pacman.d/hooks
sudo install -m 644 "$work"/senysisu/* "$THEME_DIR/"
sudo install -m 644 "$work/clock.conf" "$CONF_DIR/clock.conf"
sudo install -m 644 "$SRC_DIR/initcpio/install/$HOOK_NAME" "/etc/initcpio/install/$HOOK_NAME"
sudo install -m 644 "$SRC_DIR/initcpio/hooks/$HOOK_NAME" "/etc/initcpio/hooks/$HOOK_NAME"
sudo install -m 644 "$SRC_DIR/mkinitcpio/zz-senysisu-plymouth.conf" "$DROPIN"
sudo install -m 755 "$SRC_DIR/pacman/reapply" "$REAPPLY"
sudo install -m 644 "$SRC_DIR/pacman/95-senysisu-plymouth.hook" "$PACMAN_HOOK"
previous_theme=$(plymouth-set-default-theme)
sudo plymouth-set-default-theme senysisu

# A throwaway image first: if mkinitcpio fails or leaves something out, put
# the old theme back before the real boot images are touched.
echo "==> Test build"
kernel=$(uname -r)
if [[ ! -d /usr/lib/modules/$kernel ]]; then   # kernel upgraded since boot
    kernel=$(basename "$(dirname "$(ls -1 /usr/lib/modules/*/vmlinuz | head -1)")")
fi
if ! sudo mkinitcpio -k "$kernel" -g "$work/test.img" >"$work/test.log" 2>&1 ||
    grep -q 'ERROR' "$work/test.log"; then
    cat "$work/test.log" >&2
    echo "!!  Test build failed; restoring the $previous_theme boot screen. Nothing was rebuilt." >&2
    sudo plymouth-set-default-theme "$previous_theme"
    exit 1
fi
contents=$(sudo lsinitcpio "$work/test.img")
for need in "hooks/$HOOK_NAME" "usr/share/plymouth/themes/senysisu/senysisu.script" \
    "usr/share/plymouth/themes/senysisu/c00.png" "etc/senysisu-plymouth/clock.conf" "etc/localtime" "usr/bin/date"; do
    if ! grep -qx "$need" <<<"$contents"; then
        echo "!!  Test image lacks $need; restoring the $previous_theme boot screen. Nothing was rebuilt." >&2
        sudo plymouth-set-default-theme "$previous_theme"
        exit 1
    fi
done
if ! sudo lsinitcpio -a "$work/test.img" 2>/dev/null | grep -q "plymouth $HOOK_NAME"; then
    echo "    warning: couldn't confirm $HOOK_NAME runs right after plymouth (lsinitcpio -a)"
fi
echo "    ok ($(du -h "$work/test.img" | cut -f1) image, hook and theme present)"

rebuild_boot_images
# Only now: settings.lua should describe the boot screen that is installed.
if [[ $THEME_CHOICE != lua ]]; then save_theme "$THEME_CHOICE"; fi

echo ""
echo "Done. You'll see it at the next boot. If it ever misbehaves at the disk"
echo "prompt: Esc switches to Plymouth's plain text prompt, and typing the"
echo "password blind followed by Enter works on any screen."
echo "Re-run after changing the wallpaper, theme or $SETTINGS_FILE"
echo "(saving it alone changes nothing). Undo: $0 --uninstall"
