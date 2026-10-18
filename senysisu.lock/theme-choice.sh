#!/bin/bash
# senysisu.lock/theme-choice.sh: sourced by the senysisu.lock and
# senysisu.plymouth installers, so both pick a theme and wallpaper the same
# way. Needs SETTINGS_FILE (the settings.lua to read and write) and,
# optionally, SCREEN_NAME ("Lock screen", for the prompt's heading) and
# CURRENT_NOTE (how that screen treats "the current theme").
#
#   choose_theme <choice>   choice is "", "lua", "current" or "<theme>[,<n>]";
#                           "" asks from a terminal (settings.lua without
#                           one). Sets THEME_CHOICE to lua, current or
#                           "<theme>,<n>" and prints it; fails on an unknown
#                           theme.
#   save_theme <choice>     writes current or "<theme>,<n>" into the settings
#                           file's `theme` (current as nil).

THEME_TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE="$THEME_TOOLS/theme-stage.sh"
CURRENT_STATE="$HOME/.local/state/omarchy/current"
CURRENT_THEME=$(cat "$CURRENT_STATE/theme.name" 2>/dev/null || true)
CURRENT_NOTE=${CURRENT_NOTE:-its current wallpaper}

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
    lua "$THEME_TOOLS/settings-loader.lua" "$SETTINGS_FILE" 2>/dev/null |
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

    echo "==> ${SCREEN_NAME:-Screen} theme"
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
    if lua "$THEME_TOOLS/settings-loader.lua" "$SETTINGS_FILE" >/dev/null 2>&1 &&
        [[ $(settings_theme) == "$([[ $1 == current ]] || echo "$1")" ]]; then
        echo "    Saved theme = $value in $SETTINGS_FILE"
    else
        cp "$backup" "$SETTINGS_FILE"
        echo "    Couldn't save the theme in $SETTINGS_FILE (left unchanged); set theme = $value there yourself." >&2
    fi
    rm -f "$backup"
}

choose_theme() {
    THEME_CHOICE=${1:-}
    if [[ -z $THEME_CHOICE ]]; then
        if [[ -t 0 && -t 1 ]]; then ask_theme; else THEME_CHOICE=lua; fi
    fi
    case "$THEME_CHOICE" in
    lua | current) ;;
    *)
        # A typo stops here instead of silently falling back to the current theme.
        THEME_CHOICE=$(normalize "$THEME_CHOICE")
        "$STAGE" --wallpapers "${THEME_CHOICE%%,*}" >/dev/null || return 1
        ;;
    esac
    if [[ $THEME_CHOICE == lua ]]; then
        local lua_theme
        lua_theme=$(settings_theme)
        if [[ -n $lua_theme ]]; then
            echo "==> Theme: $(describe "$lua_theme") (settings.lua)"
        else
            echo "==> Theme: the current theme ($CURRENT_THEME, $CURRENT_NOTE) (settings.lua)"
        fi
    elif [[ $THEME_CHOICE == current ]]; then
        echo "==> Theme: the current theme ($CURRENT_THEME, $CURRENT_NOTE)"
    else
        echo "==> Theme: $(describe "$THEME_CHOICE")"
    fi
}
