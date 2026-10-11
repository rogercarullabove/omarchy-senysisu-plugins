#!/bin/bash
#
# senysisu.plymouth/render.sh <out-dir> [width height]
#
# Renders the senysisu Plymouth theme into <out-dir> (no root needed):
#
#   <out-dir>/senysisu/   the theme folder for /usr/share/plymouth/themes
#   <out-dir>/clock.conf  date formats for the initramfs clock hook
#
# Plymouth's script engine can't draw variable fonts at a chosen weight, so
# every piece of text is pre-rendered here with ImageMagick + Pango, matching
# how senysisu.lock draws it in Qt: the same fonts, sizes and soft shadow,
# laid out from the boot screen's own settings.lua (see SETTINGS_FILE) and
# the current theme's colors.
# The wallpaper is blurred to match the lock's background.blur.
#
# Sizes are computed for one screen size (default: the focused monitor); the
# script scales everything if the boot screen turns out to be different.
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:?usage: render.sh <out-dir> [width height]}"
THEME_STATE="$HOME/.local/state/omarchy/current"
# The user's copy (seeded from $SRC_DIR/settings.lua by install.sh), separate
# from the lock screen's settings.
SETTINGS_FILE="${SETTINGS_FILE:-$HOME/.config/omarchy/plugins/senysisu.plymouth/settings.lua}"

if [[ $# -ge 3 ]]; then
    SCREEN_W=$2 SCREEN_H=$3
else
    read -r SCREEN_W SCREEN_H < <(hyprctl monitors -j | jq -r '(map(select(.focused)) + .)[0] | "\(.width / .scale | floor) \(.height / .scale | floor)"')
fi

for cmd in magick lua jq fc-match; do
    command -v "$cmd" >/dev/null || { echo "render.sh: missing $cmd" >&2; exit 1; }
done

# ---- Settings (defaults match the lock's, as in LockView.qml's opt() calls) --

settings_file=$SETTINGS_FILE
[[ -f $settings_file ]] || settings_file="$SRC_DIR/settings.lua"
echo "    settings: $settings_file"
if ! SETTINGS=$(lua "$SRC_DIR/../senysisu.lock/settings-loader.lua" "$settings_file" 2>"$OUT.settings-error"); then
    echo "    $settings_file has an error; using the defaults:" >&2
    sed 's/^/      /' "$OUT.settings-error" >&2
    SETTINGS='{}'
fi
rm -f "$OUT.settings-error"

# opt <section> <key> <default-json>: the setting if it has the default's type.
opt() {
    jq -r --arg s "$1" --arg k "$2" --argjson d "$3" \
        '(.[$s] // {})[$k] as $v | if ($v | type) == ($d | type) then $v else $d end' <<<"$SETTINGS"
}

# ---- Theme colors (mirrors Color.lock in the Omarchy shell) ------------------

colors_toml="$THEME_STATE/theme/colors.toml"
shell_toml="$THEME_STATE/theme/shell.toml"

toml() { # toml <file> <section or ""> <key>
    [[ -f $1 ]] || return 0
    awk -v want="$2" -v key="$3" '
        /^[[:space:]]*\[/ { gsub(/[][[:space:]]/, ""); section = $0; next }
        section == want && index($0, "=") {
            k = substr($0, 1, index($0, "=") - 1); gsub(/[[:space:]]/, "", k)
            if (k != key) next
            v = substr($0, index($0, "=") + 1); sub(/^[[:space:]]+/, "", v)
            if (v ~ /^"/) { v = substr(v, 2); v = substr(v, 1, index(v, "\"") - 1) }
            else sub(/[[:space:]]*(#.*)?$/, "", v)
            print v; exit
        }' "$1"
}

# A shell.toml value, following "hyprland.<key>" references to that section.
shell_color() {
    local value
    value=$(toml "$shell_toml" "$1" "$2")
    if [[ $value == hyprland.* ]]; then
        value=$(toml "$shell_toml" hyprland "${value#hyprland.}")
    fi
    [[ $value =~ ^#[0-9a-fA-F]{6}$ ]] && echo "$value"
}

BACKGROUND=$(toml "$colors_toml" "" background); BACKGROUND=${BACKGROUND:-#1a1b26}
FOREGROUND=$(toml "$colors_toml" "" foreground); FOREGROUND=${FOREGROUND:-#ffffff}
ACCENT=$(toml "$colors_toml" "" accent); ACCENT=${ACCENT:-$FOREGROUND}
URGENT=$(toml "$colors_toml" "" red); URGENT=${URGENT:-#f7768e}

LOCK_TEXT=$(shell_color lock text || true); LOCK_TEXT=${LOCK_TEXT:-$FOREGROUND}
LOCK_PLACEHOLDER=$(shell_color lock placeholder || true)
LOCK_PLACEHOLDER=${LOCK_PLACEHOLDER:-"$FOREGROUND"A8}   # foreground at 66%
LOCK_ERROR=$(shell_color lock text-error || true); LOCK_ERROR=${LOCK_ERROR:-$URGENT}
FIELD_BG=$(shell_color lock background || true); FIELD_BG=${FIELD_BG:-$BACKGROUND}
FIELD_BG_ALPHA=$(toml "$shell_toml" lock background-alpha); FIELD_BG_ALPHA=${FIELD_BG_ALPHA:-0.8}
BORDER_ACTIVE=$(shell_color lock border-active || true); BORDER_ACTIVE=${BORDER_ACTIVE:-$ACCENT}
BORDER_ERROR=$(shell_color lock border-error || true); BORDER_ERROR=${BORDER_ERROR:-$URGENT}
BORDER_ALPHA=$(toml "$shell_toml" lock border-alpha); BORDER_ALPHA=${BORDER_ALPHA:-1.0}

CLOCK_COLOR=$(opt clock color '""'); CLOCK_COLOR=${CLOCK_COLOR:-$LOCK_TEXT}
DATE_COLOR=$(opt date color '""'); DATE_COLOR=${DATE_COLOR:-$LOCK_TEXT}

# ---- Sizes (LockView.qml formulas) -------------------------------------------

BASE_SIZE=$(toml "$shell_toml" font base-size); BASE_SIZE=${BASE_SIZE:-12}
HEADING=$(toml "$shell_toml" font heading | sed 's/^#.*//')
# round/jsround <arithmetic expression>
round() { awk "BEGIN { x = $1; printf \"%d\", (x < 0 ? -int(-x + 0.5) : int(x + 0.5)) }"; }
# JS Math.round rounds halves up (-121.5 -> -121), unlike printf.
jsround() { awk "BEGIN { x = $1; r = x - (x % 1); if (x % 1 < 0) r -= 1; printf \"%d\", (x - r >= 0.5 ? r + 1 : r) }"; }
HEADING=${HEADING:-$(round "$BASE_SIZE * 1.333")}
FIELD_FONT=$(round "$HEADING * 1.125")
INFO_FONT=$(( $(round "$HEADING * 0.7") > 11 ? $(round "$HEADING * 0.7") : 11 ))
DOT_FONT=$(round "$HEADING * 1.33")
DOT_SPACING=$(round "$HEADING * 0.19")

CLOCK_FONT=$(opt clock font '"Adwaita Sans"')
CLOCK_PX=$(round "$SCREEN_H * $(opt clock size 0.19)")
CLOCK_GAP=$(jsround "$CLOCK_PX * $(opt clock line_gap -0.45)")
CLOCK_OFFSET=$(round "$SCREEN_H * $(opt clock position 0.16)")
DATE_ENABLED=$(opt date enabled true)
DATE_GAP=$(jsround "$CLOCK_PX * $(opt date gap -0.16)")
FIELD_W=$(round "$(opt password width 340)")
FIELD_H=$(round "$(opt password height 56)")
FIELD_GAP=$(round "$SCREEN_H * $(opt password gap 0.13)")
# Corner radius like LockView.qml's fieldRadius: 0 = rectangle, unset or
# >= half the height = pill.
FIELD_RADIUS=$(awk -v r="$(opt password rounding "$(( FIELD_H / 2 ))")" -v h="$FIELD_H" \
    'BEGIN { r = r < 0 ? 0 : r; if (r > h / 2) r = h / 2; printf "%g", r }')
PLACEHOLDER=$(opt password placeholder '"Enter Password"')
BLUR=$(opt background blur 1.0)
BATTERY_PERCENT=$(opt battery show_percent true)
BATTERY_LOW=$(opt battery low 15)

# Style.font.family is "monospace", so the info text, date and field use
# whatever fontconfig resolves that to (JetBrainsMono Nerd Font on Omarchy).
MONO=$(fc-match -f '%{family[0]}' monospace)

# Battery corner (empty = hidden). There's no Wi-Fi indicator: the network
# isn't up yet at boot, so it would always read disconnected.
BATTERY_CORNER=$(jq -r '(.battery // {}) | if type == "object" and has("corner") then .corner else "bottom_right" end | tostring' <<<"$SETTINGS")
[[ $BATTERY_CORNER =~ ^(top|bottom)_(left|right)$ ]] || BATTERY_CORNER=""

# ---- Rendering helpers --------------------------------------------------------

THEME="$OUT/senysisu"
rm -rf "$THEME"
mkdir -p "$THEME"

xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\&apos;/g" -e 's/"/\&quot;/g' <<<"$1"; }

# text_png <out.png> <font_desc> <color> <text>: Pango's logical box (advance
# width x line height), like Qt's implicit Text size.
text_png() {
    local markup
    markup=$(xml_escape "$4")
    markup=${markup//%/%%}   # magick expands %-escapes in the caption
    magick -background none "pango:<span font_desc=\"$2\" foreground=\"$3\">$markup</span>" -strip -depth 8 "PNG32:$1"
}

# advance <font_desc-without-size> <px> <char>: the glyph's real advance width.
# Pango rounds each glyph to whole pixels at small sizes (11 vs Qt's 10.8), so
# measure ten of them at ten times the size.
advance() {
    local w
    read -r w _ < <(size_of <(text_png - "$1 $(( $2 * 10 ))px" "#000000" "$(printf "$3%.0s" $(seq 10))"))
    awk -v w="$w" 'BEGIN { printf "%.3f", w / 100 }'
}

# The lock overlay's MultiEffect shadow (shadowBlur 0.8, opacity 0.6, theme
# background color) measured against a screenshot: a tight Gaussian edge.
SHADOW_PAD=12
add_shadow() {
    magick "$1" -bordercolor none -border $SHADOW_PAD \
        \( +clone -alpha extract -blur 0x4 -evaluate multiply 0.6 -background "$BACKGROUND" -alpha shape \) \
        +swap -background none -compose over -flatten -strip -depth 8 "PNG32:$1"
}

size_of() { magick identify -format '%w %h\n' "$1"; }

# qt_height <family> <weight> <px>: the line height Qt gives a Text in this
# font, which the lock's layout is built from. Pango's differs by a pixel or
# so, which adds up down the clock column. Prints nothing without Qt's qml.
QML_BIN=/usr/lib/qt6/bin/qml
qt_height() {
    [[ -x $QML_BIN ]] || return 0
    local probe
    probe=$(mktemp --suffix=.qml)
    cat >"$probe" <<QML
import QtQuick
Item {
  Text { id: t; text: "Ag"; font.family: "$1"; font.weight: $2; font.pixelSize: $3 }
  Component.onCompleted: { console.warn("height", t.implicitHeight); Qt.quit() }
}
QML
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen timeout 10 "$QML_BIN" "$probe" 2>&1 |
        awk '$2 == "height" { printf "%d", $3 + 0.5 }' || true
    rm -f "$probe"
}

# line_metrics <NAME> <pango image> <family> <weight> <px>: NAME_LINE_H is the
# Qt line height (Pango's without Qt), NAME_Y_ADJ moves the Pango image so its
# glyphs land where Qt draws them.
line_metrics() {
    local pango_h qt_h
    read -r _ pango_h < <(size_of "$2")
    qt_h=$(qt_height "$3" "$4" "$5")
    qt_h=${qt_h:-$pango_h}
    printf -v "$1_LINE_H" '%d' "$qt_h"
    printf -v "$1_Y_ADJ" '%d' "$(( qt_h - pango_h ))"
}

echo "    screen ${SCREEN_W}x${SCREEN_H}, clock ${CLOCK_FONT} ${CLOCK_PX}px, text font ${MONO}"

# ---- Background: the wallpaper, blurred and toned like the lock --------------

wallpaper=$(readlink -f "$THEME_STATE/background" 2>/dev/null || true)
if [[ -n $wallpaper && -f $wallpaper ]]; then
    # MultiEffect blur (blurMax 128, multiplier 1.25) matched a Gaussian of
    # sigma 76 * blur at 1080p; contrast -0.08 as in the lock. No weather
    # grading: there's no forecast at boot.
    sigma=$(awk -v b="$BLUR" -v h="$SCREEN_H" 'BEGIN { b = b < 0 ? 0 : (b > 1 ? 1 : b); printf "%.1f", 76 * b * h / 1080 }')
    magick "$wallpaper" -resize "${SCREEN_W}x${SCREEN_H}^" -gravity center -extent "${SCREEN_W}x${SCREEN_H}" \
        -blur "0x$sigma" -function polynomial 0.92,0.04 \
        -resize 50% -strip -depth 8 "PNG24:$THEME/background.png"   # blurred: half size is plenty
    HAS_BACKGROUND=1
else
    HAS_BACKGROUND=0
fi

# ---- Clock: every hour/minute string, as the lock draws them -----------------

# Qt doesn't set the optical-size axis, so variable fonts with one (Adwaita
# Sans is Inter) render at its default of 14; Pango would pick the pixel size.
clock_desc="$CLOCK_FONT Black ${CLOCK_PX}px @opsz=14"
for n in $(seq 0 59); do
    for s in "$n" "$(printf '%02d' "$n")"; do
        [[ -f $THEME/c$s.png ]] && continue
        text_png "$THEME/c$s.png" "$clock_desc" "$CLOCK_COLOR" "$s"
        add_shadow "$THEME/c$s.png"
    done
done
line_metrics CLOCK <(text_png - "$clock_desc" "$CLOCK_COLOR" 00) "$CLOCK_FONT" 900 "$CLOCK_PX"

# AM/PM for the 12-hour clock: the tops of the letters level with the tops of
# the digits (ink, not line boxes), a small gap right of the hours.
# ink_rows <image>: the first and one-past-last rows at least half covered
# (where the eye puts an antialiased edge).
ink_rows() { magick "$1" -alpha extract -threshold 50% -format '%@' info: | awk -F'[x+]' '{ print $4, $4 + $2 }'; }
AMPM=$([[ $(opt clock hours 24) == 12 && $(opt clock ampm true) == true ]] && echo 1 || echo 0)
AMPM_PX=$(round "$CLOCK_PX * $(opt clock ampm_size 0.2)"); (( AMPM_PX >= 1 )) || AMPM_PX=1
AMPM_GAP=$(round "$CLOCK_PX * 0.04")
ampm_desc="$CLOCK_FONT Black ${AMPM_PX}px @opsz=14"
# "7" and "M" have flat tops (no overshoot). Pango snaps the small letters to
# whole pixels, so measure what it draws rather than scaling the digits.
read -r DIGITS_INK_TOP _ < <(ink_rows <(text_png - "$clock_desc" "$CLOCK_COLOR" 7))
read -r AMPM_INK_TOP _ < <(ink_rows <(text_png - "$ampm_desc" "$CLOCK_COLOR" M))
for ap in am pm; do
    text_png "$THEME/$ap.png" "$ampm_desc" "$CLOCK_COLOR" "${ap^^}"
    add_shadow "$THEME/$ap.png"
done

# ---- Date: one image per character (the font is monospaced) ------------------

date_desc="$MONO Bold ${FIELD_FONT}px"
DATE_CHARS="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:-/'()"
glyph_table=""
for (( i = 0; i < ${#DATE_CHARS}; i++ )); do
    ch=${DATE_CHARS:i:1}
    code=$(printf '%d' "'$ch")
    text_png "$THEME/d$code.png" "$date_desc" "$DATE_COLOR" "$ch"
    add_shadow "$THEME/d$code.png"
    glyph_table+="date_glyph[\"$ch\"] = \"d$code.png\";"$'\n'
done
line_metrics DATE <(text_png - "$date_desc" "$DATE_COLOR" M) "$MONO" 700 "$FIELD_FONT"
DATE_ADVANCE=$(advance "$MONO Bold" "$FIELD_FONT" M)

# ---- Battery corner ------------------------------------------------------------

info_desc="$MONO Bold ${INFO_FONT}px"
BATTERY_ICONS=("󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" "󰂄")   # 0-100 by tens, then charging
for variant in n:$LOCK_TEXT e:$LOCK_ERROR; do
    tag=${variant%%:*} color=${variant#*:}
    for ch in 0 1 2 3 4 5 6 7 8 9 %; do
        name="b$tag$( [[ $ch == % ]] && echo pct || echo "$ch").png"
        text_png "$THEME/$name" "$info_desc" "$color" "$ch"
        add_shadow "$THEME/$name"
    done
    for i in "${!BATTERY_ICONS[@]}"; do
        text_png "$THEME/bi$tag$i.png" "$info_desc" "$color" "${BATTERY_ICONS[i]}"
        add_shadow "$THEME/bi$tag$i.png"
    done
done
line_metrics INFO <(text_png - "$info_desc" "$LOCK_TEXT" 0) "$MONO" 700 "$INFO_FONT"
INFO_ADVANCE=$(advance "$MONO Bold" "$INFO_FONT" 0)
CORNER_MARGIN=$(round "$HEADING * 1.2")

# ---- Password field --------------------------------------------------------------

hex_alpha() { printf '%02x' "$(round "$1 * 255")"; }
pill() { # pill <out> <border color>
    # Fill inset by 1px and the 3px stroke centered 1.5px in, radii shrunk to match.
    local fill_r stroke_r
    fill_r=$(awk -v r="$FIELD_RADIUS" 'BEGIN { printf "%.1f", (r > 1 ? r - 1 : 0) }')
    stroke_r=$(awk -v r="$FIELD_RADIUS" 'BEGIN { printf "%.1f", (r > 1.5 ? r - 1.5 : 0) }')
    magick -size "${FIELD_W}x${FIELD_H}" xc:none \
        -fill "${FIELD_BG}$(hex_alpha "$FIELD_BG_ALPHA")" -stroke none \
        -draw "roundrectangle 1,1 $((FIELD_W - 2)),$((FIELD_H - 2)) $fill_r,$fill_r" \
        -fill none -stroke "$2$(hex_alpha "$BORDER_ALPHA")" -strokewidth 3 \
        -draw "roundrectangle 1.5,1.5 $(awk -v w="$FIELD_W" -v h="$FIELD_H" 'BEGIN { printf "%.1f,%.1f", w - 2.5, h - 2.5 }') $stroke_r,$stroke_r" \
        "$1"
}
pill "$THEME/field.png" "$BORDER_ACTIVE"
pill "$THEME/field-error.png" "$BORDER_ERROR"

# Text area inside the field: border (3) + padding (18) on both sides. (The
# lock also reserves room for its show-password eye, which Plymouth can't do.)
TEXT_AREA_W=$(( FIELD_W - 2 * (3 + 18) ))

# field_text <out> <font_desc> <color> <text>: elided like Qt's ElideRight.
field_text() {
    local text=$4
    text_png "$1" "$2" "$3" "$text"
    while (( $(magick identify -format '%w' "$1") > TEXT_AREA_W )) && (( ${#text} > 1 )); do
        text=${text%…}; text="${text%?}…"
        text_png "$1" "$2" "$3" "$text"
    done
}
field_text "$THEME/placeholder.png" "$MONO ${FIELD_FONT}px" "$LOCK_PLACEHOLDER" "$PLACEHOLDER"
field_text "$THEME/checking.png" "$MONO ${FIELD_FONT}px" "$LOCK_TEXT" "Checking…"
for n in 1 2 3 4 5 6 7 8 9; do
    field_text "$THEME/failed$n.png" "$MONO Italic ${FIELD_FONT}px" "$LOCK_ERROR" "Authentication failed ($n)"
done

text_png "$THEME/dot.png" "$MONO ${DOT_FONT}px" "$LOCK_TEXT" "●"
line_metrics DOT "$THEME/dot.png" "$MONO" 400 "$DOT_FONT"
line_metrics LABEL "$THEME/placeholder.png" "$MONO" 400 "$FIELD_FONT"
DOT_W=$(advance "$MONO" "$DOT_FONT" ●)
magick -size "2x$DOT_LINE_H" "xc:$LOCK_TEXT" "$THEME/cursor.png"

# ---- Script + theme file ---------------------------------------------------------

# rgb <NAME> <#rrggbb>: NAME_R/G/B globals as 0-1 floats.
rgb() { awk -v n="$1" -v h="${2#\#}" 'BEGIN { split("R G B", c); for (i = 1; i <= 3; i++) printf "global.%s_%s = %.3f;\n", n, c[i], strtonum("0x" substr(h, 2 * i - 1, 2)) / 255 }'; }

{
    echo "# Generated by senysisu.plymouth/render.sh on $(date -I) — edit the template, not this file."
    echo "global.BUILD_H = $SCREEN_H;"
    echo "global.SHADOW_PAD = $SHADOW_PAD;"
    echo "global.HAS_BACKGROUND = $HAS_BACKGROUND;"
    echo "global.CLOCK_LINE_H = $CLOCK_LINE_H;"
    echo "global.CLOCK_Y_ADJ = $CLOCK_Y_ADJ;"
    echo "global.CLOCK_GAP = $CLOCK_GAP;"
    echo "global.CLOCK_OFFSET = $CLOCK_OFFSET;"
    echo "global.DATE_ENABLED = $([[ $DATE_ENABLED == true ]] && echo 1 || echo 0);"
    echo "global.DATE_GAP = $DATE_GAP;"
    echo "global.DATE_LINE_H = $DATE_LINE_H;"
    echo "global.DATE_Y_ADJ = $DATE_Y_ADJ;"
    echo "global.DATE_ADVANCE = $DATE_ADVANCE;"
    echo "global.HOUR_PAD = $([[ $(opt clock hour_format '"HH"') =~ ^(HH|hh)$ ]] && echo 1 || echo 0);"
    echo "global.HOUR_12 = $([[ $(opt clock hours 24) == 12 ]] && echo 1 || echo 0);"
    echo "global.AMPM = $AMPM;"
    echo "global.AMPM_GAP = $AMPM_GAP;"
    echo "global.AMPM_Y = $(( DIGITS_INK_TOP - AMPM_INK_TOP ));"
    echo "global.MINUTE_PAD = $([[ $(opt clock minute_format '"mm"') == m ]] && echo 0 || echo 1);"
    echo "global.FIELD_W = $FIELD_W;"
    echo "global.FIELD_H = $FIELD_H;"
    echo "global.FIELD_GAP = $FIELD_GAP;"
    echo "global.TEXT_AREA_W = $TEXT_AREA_W;"
    echo "global.DOT_W = $DOT_W;"
    echo "global.DOT_SPACING = $DOT_SPACING;"
    echo "global.DOT_LINE_H = $DOT_LINE_H;"
    echo "global.DOT_Y_ADJ = $DOT_Y_ADJ;"
    echo "global.LABEL_LINE_H = $LABEL_LINE_H;"
    echo "global.LABEL_Y_ADJ = $LABEL_Y_ADJ;"
    echo "global.INFO_LINE_H = $INFO_LINE_H;"
    echo "global.INFO_Y_ADJ = $INFO_Y_ADJ;"
    echo "global.INFO_ADVANCE = $INFO_ADVANCE;"
        echo "global.CORNER_MARGIN = $CORNER_MARGIN;"
    echo "global.BATTERY_CORNER = \"${BATTERY_CORNER}\";"
    echo "global.BATTERY_PERCENT = $([[ $BATTERY_PERCENT == true ]] && echo 1 || echo 0);"
    echo "global.BATTERY_LOW = $BATTERY_LOW;"
    rgb BG "$BACKGROUND"
    rgb TEXT "$LOCK_TEXT"
    echo "date_glyph = [];"
    printf '%s' "$glyph_table"
    echo
    cat "$SRC_DIR/senysisu.script.in"
} >"$THEME/senysisu.script"

cat >"$THEME/senysisu.plymouth" <<EOF
[Plymouth Theme]
Name=senysisu
Description=Boot and disk-unlock screen matching the senysisu.lock lock screen.
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/senysisu
ScriptFile=/usr/share/plymouth/themes/senysisu/senysisu.script
ConsoleLogBackgroundColor=0x${BACKGROUND#\#}
Font=$MONO Bold $INFO_FONT
MonospaceFont=$MONO $INFO_FONT
EOF

# ---- Formats for the initramfs clock (Qt date format -> date(1)) -------------

qt_to_strftime() {
    lua - "$1" <<'LUA'
local fmt, out, i = arg[1], {}, 1
local map = { dddd = "%A", ddd = "%a", dd = "%d", d = "%-d", MMMM = "%B", MMM = "%b",
              MM = "%m", M = "%-m", yyyy = "%Y", yy = "%y" }
while i <= #fmt do
  local c = fmt:sub(i, i)
  if c == "'" then
    local j = fmt:find("'", i + 1, true) or (#fmt + 1)
    out[#out + 1] = (j == i + 1) and "'" or fmt:sub(i + 1, j - 1):gsub("%%", "%%%%")
    i = j + 1
  else
    local run = fmt:match("^" .. c:gsub("%p", "%%%0") .. "+", i)
    if map[run] then out[#out + 1] = map[run]
    elseif c == "%" then out[#out + 1] = string.rep("%%", #run)
    else
      -- Split runs longer than the longest token (e.g. "ddddd").
      local token = nil
      for _, len in ipairs({ 4, 3, 2, 1 }) do
        if map[run:sub(1, len)] then token = run:sub(1, len) break end
      end
      if token then run = token; out[#out + 1] = map[token] else out[#out + 1] = run end
    end
    i = i + #run
  end
end
io.write(table.concat(out))
LUA
}

DATE_FORMAT=$(qt_to_strftime "$(opt date format '"d MMM dddd"')")
cat >"$OUT/clock.conf" <<EOF
# Read by the senysisu-plymouth initramfs hook (generated by render.sh).
DATE_FORMAT='${DATE_FORMAT//\'/\'\\\'\'}'
EOF

echo "    rendered $(ls "$THEME" | wc -l) files ($(du -sh "$THEME" | cut -f1)) into $THEME"
