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

STAGE="$SRC_DIR/../senysisu.lock/theme-stage.sh"
CURRENT_STATE="$HOME/.local/state/omarchy/current"

# Number of wallpapers a theme has, in the order "<theme>,<n>" counts them.
wallpaper_count() {
    "$STAGE" --wallpapers "$1" 2>/dev/null | wc -l
}

# Position of the current wallpaper among the current theme's (empty if it
# isn't one of them, e.g. a one-off picked from elsewhere).
current_wallpaper_index() {
    local current
    current=$(basename "$(readlink -f "$CURRENT_STATE/background" 2>/dev/null)" 2>/dev/null) || return 0
    "$STAGE" --wallpapers "$CURRENT_THEME" 2>/dev/null | awk -F/ -v want="$current" '$NF == want { print NR; exit }'
}

# settings.lua's theme as a string, "" for nil (follow the current theme).
settings_theme() {
    lua "$SRC_DIR/../senysisu.lock/settings-loader.lua" "$SETTINGS_FILE" 2>/dev/null |
        jq -r '.theme | if type == "string" then . else "" end' 2>/dev/null || true
}

# "Tokyo Night,2" -> "tokyo-night,2", as theme-stage.sh and omarchy-theme-set do.
normalize() {
    local name=${1%%,*} rest=""
    [[ $1 == *,* ]] && rest=",${1#*,}"
    name=$(sed -E 's/<[^>]+>//g; s/^[[:space:]]+|[[:space:]]+$//g' <<<"$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    echo "$name$(tr -d '[:space:]' <<<"$rest")"
}

describe() {   # describe <theme>[,<n>] -> "nord, wallpaper 2"
    local name=${1%,*} n=""
    [[ $1 == *,* ]] && n=${1##*,}
    if [[ -n $n ]]; then echo "$name, wallpaper $n"
    elif [[ $name == "$CURRENT_THEME" ]]; then echo "$name, its current wallpaper"
    else echo "$name, wallpaper 1"
    fi
}

# Sets THEME_CHOICE: "lua", "current" or "<theme>,<n>".
ask_theme() {
    local lua_theme cur_index themes=() counts=() i answer name n count
    lua_theme=$(settings_theme)
    cur_index=$(current_wallpaper_index)
    mapfile -t themes < <("$STAGE" --list)
    for name in "${themes[@]}"; do counts+=("$(wallpaper_count "$name")"); done

    echo "==> Boot screen theme"
    echo "    Current Omarchy theme:  $CURRENT_THEME, wallpaper ${cur_index:-?} ($(basename "$(readlink -f "$CURRENT_STATE/background" 2>/dev/null)" 2>/dev/null))"
    if [[ -n $lua_theme ]]; then
        echo "    settings.lua:           $(describe "$lua_theme")"
    else
        echo "    settings.lua:           the current theme (theme = nil)"
    fi
    echo "    Installed themes (wallpapers):"
    for i in "${!themes[@]}"; do
        printf '    %3d %-20s' "$((i + 1))" "${themes[i]} (${counts[i]})"
        if (((i + 1) % 3 == 0)); then echo; fi
    done
    if ((${#themes[@]} % 3 != 0)); then echo; fi

    # Examples use a real entry of this list: nord if installed, else the first.
    local ex=0
    for i in "${!themes[@]}"; do [[ ${themes[i]} == nord ]] && ex=$i; done
    local ex_name=${themes[ex]} ex_n=$((ex + 1))
    echo "    Pick one:"
    printf '      %-22s %s\n' "Enter" "keep settings.lua's choice" \
        "c" "the current theme and wallpaper" \
        "$ex_n  or  $ex_name" "a theme from the list (asks for the wallpaper next)" \
        "$ex_n,2 or $ex_name,2" "a theme and its wallpaper number in one go"
    while true; do
        read -r -p "Theme: " answer
        answer=$(tr -d '[:space:]' <<<"$answer")
        case "$answer" in
        "") THEME_CHOICE=lua; return ;;
        c | current) THEME_CHOICE=current; return ;;
        esac
        name=${answer%%,*} n=""
        [[ $answer == *,* ]] && n=${answer#*,}
        if [[ $name =~ ^[0-9]+$ ]]; then
            if ((10#$name < 1 || 10#$name > ${#themes[@]})); then echo "    No theme $name in the list."; continue; fi
            name=${themes[10#$name - 1]}
        fi
        if ! "$STAGE" --wallpapers "$name" >/dev/null 2>&1; then
            echo "    No installed theme '$name'."; continue
        fi
        count=$(wallpaper_count "$name")
        name=$(normalize "$name")
        if [[ -z $n ]] && ((count > 1)); then
            local default=1
            [[ $name == "$CURRENT_THEME" && -n $cur_index ]] && default=$cur_index
            while true; do
                read -r -p "Wallpaper for $name, 1-$count [$default]: " n
                n=$(tr -d '[:space:]' <<<"${n:-$default}")
                [[ $n =~ ^[0-9]+$ ]] && ((10#$n >= 1 && 10#$n <= count)) && break
                echo "    $name has wallpapers 1-$count."
            done
        fi
        n=${n:-1}
        if [[ ! $n =~ ^[0-9]+$ ]] || ((10#$n < 1 || (count > 0 && 10#$n > count))); then
            echo "    $name has wallpapers 1-$count."; continue
        fi
        THEME_CHOICE="$name,$((10#$n))"
        return
    done
}

# Writes a choice into settings.lua's `theme` (current as nil). Keeps the old
# file if the result doesn't load.
save_theme() {
    local value=nil backup
    [[ $1 == current ]] || value="\"$1\""
    backup=$(mktemp)
    cp "$SETTINGS_FILE" "$backup"
    if grep -qE '^[[:space:]]*theme[[:space:]]*=' "$SETTINGS_FILE"; then
        sed -i -E "0,/^([[:space:]]*)theme[[:space:]]*=[[:space:]]*(nil|\"[^\"]*\"|'[^']*')[[:space:]]*,?/s//\1theme = $value,/" "$SETTINGS_FILE"
    else
        sed -i -E "0,/^return[[:space:]]*\{/s//&\n  theme = $value,/" "$SETTINGS_FILE"
    fi
    if lua "$SRC_DIR/../senysisu.lock/settings-loader.lua" "$SETTINGS_FILE" >/dev/null 2>&1 &&
        [[ $(settings_theme) == "$([[ $1 == current ]] || echo "$1")" ]]; then
        echo "    Saved theme = $value in $SETTINGS_FILE"
    else
        cp "$backup" "$SETTINGS_FILE"
        echo "    Couldn't save the theme in $SETTINGS_FILE (left unchanged); set theme = $value there yourself." >&2
    fi
    rm -f "$backup"
}

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
CURRENT_THEME=$(cat "$CURRENT_STATE/theme.name" 2>/dev/null || true)
if [[ -z $THEME_CHOICE ]]; then
    if [[ -t 0 && -t 1 ]]; then ask_theme; else THEME_CHOICE=lua; fi
fi
case "$THEME_CHOICE" in
lua) ;;
current) export THEME_OVERRIDE=current ;;
*)
    # A typo should stop here, not fall back to the current theme in render.sh.
    THEME_CHOICE=$(normalize "$THEME_CHOICE")
    if ! "$STAGE" --wallpapers "${THEME_CHOICE%%,*}" >/dev/null; then exit 1; fi
    export THEME_OVERRIDE=$THEME_CHOICE
    ;;
esac
if [[ $THEME_CHOICE == lua ]]; then
    lua_theme=$(settings_theme)
    if [[ -n $lua_theme ]]; then
        echo "==> Theme: $(describe "$lua_theme") (settings.lua)"
    else
        echo "==> Theme: the current theme ($CURRENT_THEME) (settings.lua)"
    fi
elif [[ $THEME_CHOICE == current ]]; then
    echo "==> Theme: the current theme ($CURRENT_THEME, its current wallpaper)"
else
    echo "==> Theme: $(describe "$THEME_CHOICE")"
fi

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
