#!/bin/bash
#
# senysisu.plymouth/preview.sh [theme-dir]
#
# Shows the boot screen in a window, without root and without touching the
# installed theme or the boot images: plymouthd runs in a user namespace
# (where it is "root"), drawing through its X11 renderer on Xwayland, with
# the theme bind-mounted over /usr/share/plymouth/themes for that namespace
# only. Sends the current time like the initramfs hook would, then asks for
# a password that is never right, so every state of the field can be seen.
#
# Without a theme dir, renders one from the current settings first.
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for cmd in unshare plymouthd plymouth hyprctl; do
    command -v "$cmd" >/dev/null || { echo "preview.sh: missing $cmd" >&2; exit 1; }
done
[[ -e /usr/lib/plymouth/renderers/x11.so ]] || { echo "preview.sh: Plymouth's X11 renderer is not installed" >&2; exit 1; }
[[ -n ${DISPLAY:-} ]] || { echo "preview.sh: needs Xwayland (DISPLAY is not set)" >&2; exit 1; }
if pgrep -x plymouthd >/dev/null; then
    echo "preview.sh: plymouthd is already running" >&2
    exit 1
fi

mkdir -p "$WORK/themes"
if [[ -n ${1:-} ]]; then
    cp -r "$1" "$WORK/themes/senysisu"
else
    echo "==> Rendering the theme"
    "$SRC_DIR/render.sh" "$WORK/build"
    cp -r "$WORK/build/senysisu" "$WORK/themes/senysisu"
    # shellcheck disable=SC1091
    . "$WORK/build/clock.conf"
fi
cp -r /usr/share/plymouth/themes/{text,details} "$WORK/themes/"

# Stands in for cryptsetup: thinks for a moment, then rejects the password.
printf '#!/bin/sh\nsleep 1.5\nexit 1\n' >"$WORK/wrong-password"
chmod +x "$WORK/wrong-password"

seconds=$(( $(date +%s) - $(date -d 'today 00:00' +%s) ))
battery=""; status=D
for supply in /sys/class/power_supply/BAT*; do
    [[ -r $supply/capacity ]] || continue
    battery=$(<"$supply/capacity")
    [[ $(<"$supply/status") =~ ^(Charging|Full)$ ]] && status=C
    break
done
message="senysisu|$seconds|$(date +"${DATE_FORMAT:-%-d %b %A}")|$battery|$status"

echo "==> Opening the preview: type into it and press Enter (it never accepts)."
echo "    Esc toggles Plymouth's text view. Closes after 3 tries or 90 seconds."
unshare -rm bash -c '
    themes=$1 message=$2 check=$3
    trap "plymouth quit 2>/dev/null; wait" EXIT
    trap "exit 1" INT TERM
    mount --bind "$themes" /usr/share/plymouth/themes
    plymouthd --no-daemon --mode=boot --pid-file="$themes/../plymouthd.pid" \
        --kernel-command-line="quiet splash plymouth.splash=senysisu" &
    for _ in $(seq 50); do plymouth --ping 2>/dev/null && break; sleep 0.1; done
    plymouth show-splash
    plymouth display-message --text="$message"
    sleep 0.5
    hyprctl dispatch "hl.dsp.focus({ window = \"class:Plymouthd\" })" >/dev/null
    hyprctl dispatch "hl.dsp.window.fullscreen({ mode = \"fullscreen\" })" >/dev/null
    timeout 90 plymouth ask-for-password --prompt=preview --command="$check" --number-of-tries=3 || true
    sleep 1
' bash "$WORK/themes" "$message" "$WORK/wrong-password"
