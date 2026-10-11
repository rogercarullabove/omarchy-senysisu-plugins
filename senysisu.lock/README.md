# My Lock Screen (`senysisu.lock`)

A customized copy of Omarchy's built-in lock screen (`omarchy.lock`), created
with `omarchy plugin clone omarchy.lock` on 2026-10-10.

## Install

From a clone of this repo:

```bash
./install.sh senysisu.lock          # or: ./senysisu.lock/install.sh
```

The installer checks requirements (`lua`, `curl`, `jq`, the Adwaita Sans
font), copies the plugin to `~/.config/omarchy/plugins/senysisu.lock/` (keeping
an existing `settings.lua`), swaps it in for `omarchy.lock`, and restarts the
shell. If anything fails after the built-in lock was disabled, it re-enables
it, so you're never left without a lock screen. Re-run it to update.

## What's different from the original

Changes are in `LockView.qml` and `WeatherBackdrop.qml` (weather effects,
with textures in `assets/`), plus `settings.lua` / `settings-loader.lua` for
configuration. `Service.qml` (locking, PAM password and fingerprint
authentication) is untouched from the original.

- **Stacked clock** — hours over minutes in a heavy font (`Adwaita Sans`,
  Black weight), with the date below as `d MMM dddd` (e.g. `10 Oct Saturday`).
- **Weather line** — small text at the top: `IN, Delhi ☀  Clear +12°C`.
  Fetched from wttr.in with `curl` when the screen locks and every 15 minutes.
  Uses the location configured for the bar's weather widget
  (`~/.local/state/omarchy/settings/weather.json`) or IP auto-detect if unset.
  Hidden if the fetch fails (e.g. offline).
- **Corner indicators** — battery (percentage + icon via UPower; charging icon
  when plugged in, red at 15% or below, hidden without a battery) and Wi-Fi
  (signal-strength icon from NetworkManager; Ethernet icon when wired, crossed
  out when disconnected or Wi-Fi is off). Bottom-right by default.
- **Show password** — eye icon inside the left edge of the password field.
  Click it or press `Ctrl+R` to toggle. Resets to hidden after each submit.
- **Password field** — pill-shaped by default (`rounding` sets the corner
  radius; `0` makes it a rectangle), placed a fixed gap below the clock so it
  never overlaps it.
- **Weather effects** — the wallpaper is color graded and animated to match
  the weather, either automatically (from the same wttr.in fetch) or set by
  hand. See [Weather effects](#weather-effects).

Colors still follow the current theme (`[lock]` section of the theme's
`shell.toml`, overridable in `~/.config/omarchy/shell.toml`).

## Settings (`settings.lua`)

Everything you'd normally want to tweak lives in `settings.lua` in this folder,
in the same spirit as the Hyprland `.lua` configs. It returns a Lua table with
these sections:

| Section | Options |
|---|---|
| `clock` | `font`, `size`, `position`, `line_gap`, `hour_format` (`"HH"`/`"hh"`), `minute_format`, `color` |
| `date` | `enabled`, `format`, `gap`, `color` |
| `weather` | `enabled`, `location`, `refresh_minutes` |
| `corners` | `top_left`, `top_right`, `bottom_left`, `bottom_right`: list of indicators (`"battery"`, `"wifi"`) |
| `indicators` | `spacing` |
| `battery` | `show_percent`, `low` |
| `wifi` | `show_name` |
| `password` | `width`, `height`, `rounding`, `gap`, `placeholder`, `reveal_toggle` |
| `effects` | `mode` (`"off"`/`"auto"`/`"manual"`), `weather`, `night` (`"auto"`/`true`/`false`), `intensity` |
| `background` | `blur` |

Corner indicators: each corner takes a list, shown left to right in the order
listed, e.g. `bottom_right = { "wifi", "battery" }`. Move a name to another
corner's list to move it; leave it out of every list to hide it. Unknown names
are skipped with a warning in the journal.

Each option is commented in the file. Fractions (`size`, `position`, `gap`)
are relative to the screen height; colors are `"#rrggbb"` or `nil` to follow
the theme.

- **Changes apply live** when you save — no restart needed. Check them with
  `omarchy-shell lock preview` (click to close).
- **Deleting an option** (or setting it to `nil`) uses its default.
- **A wrongly typed option** (e.g. `size = "big"`) uses that option's default.
- **A broken file** (Lua syntax or runtime error) makes the lock screen use
  all defaults; it keeps working. See the error with
  `journalctl --user -g senysisu.lock`.
- Being Lua, the file can compute values (e.g. `size = 0.19 * 1.1`).

How it works: `LockView.qml` watches `settings.lua`, runs it through
`settings-loader.lua` (converts the returned table to JSON with the system
`lua`), and reads each option with a built-in default as fallback.

## Weather effects

| Weather | Moving elements | Color grading of the wallpaper |
|---|---|---|
| `sunny` (day) | faint breathing sun glow, a few warm motes | a bit warmer |
| `cloudy` | — | a bit desaturated |
| `rain` | fine streaks in three depth layers (the nearest passes in front of the clock and password box), gently gusting wind | desaturated, slightly darker |
| `storm` | ~4× denser, wind-driven rain that surges in sheets, lightning | desaturated, darker |
| `snow` | drifting, wobbling flakes, plus a few big soft near flakes in front of the clock | a bit desaturated, slightly cool |
| `snowstorm` | dense wind-driven snow, frosty edges | desaturated, cooler |
| night (any weather) | nothing extra; `sunny` at night is a clear night with no sun elements | cooler, a bit desaturated, a bit darker |

- **`mode = "auto"`** maps wttr.in's condition text: thunder → `storm`,
  blizzard / heavy or blowing snow → `snowstorm`, snow / sleet → `snow`,
  rain / drizzle / showers → `rain`, cloud / overcast / fog / mist → `cloudy`,
  sunny / clear → `sunny`. Anything else shows no effect.
- **`mode = "manual"`** always uses `weather`; **`"off"`** disables effects
  and grading entirely.
- **`night = "auto"`** compares the current time with sunrise/sunset from the
  same fetch (falls back to 19:00–07:00 when offline). `true`/`false` force it
  — without quotes; `"false"` is a string and counts as `"auto"`. The times
  are in the weather location's time zone, so a `weather.location` in another
  time zone shifts day/night by the difference.
- **`intensity`** scales how much rain/snow falls (0.1–2.0).
- **Depth:** `WeatherBackdrop.qml` is used twice — behind the clock (far and
  mid rain, regular snow, sun glow, frost, lightning) and in front of
  everything (only the nearest rain streaks and snowflakes, no input). The
  front copy follows the back copy's wind and gusts so both slant alike. It's
  deliberately subtle: pale near particles almost vanish over the light
  clock digits, as real rain does in front of something bright.
- Changes to `effects` apply live like every other setting.

Cost: moving effects make the shell redraw continuously while the lock
screen is shown. Measured with the preview open (share of one core):
`off` / `cloudy` / clear night ~1–2%, `sunny` day ~24%, `rain` ~25%,
`snow` ~26%, `storm` ~29%, `snowstorm` ~34%.

## Applying code changes

Edits to the `.qml` files (not `settings.lua`) need a shell restart, because
the lock screen does not hot-reload its code:

```bash
omarchy restart shell
```

Preview without actually locking (closes on click):

```bash
omarchy-shell lock preview
omarchy-shell lock hidePreview
```

Lock for real: `Super+Ctrl+L` or `omarchy system lock`.

## Disable this lock and go back to the original

```bash
./install.sh senysisu.lock --uninstall
```

or by hand:

```bash
omarchy plugin disable senysisu.lock
omarchy plugin enable omarchy.lock
omarchy restart shell
```

Check which one is active:

```bash
omarchy plugin list | grep -i lock
```

To switch back to this custom lock later:

```bash
omarchy plugin disable omarchy.lock
omarchy plugin enable senysisu.lock
omarchy restart shell
```

To delete it entirely (after disabling it as above):

```bash
omarchy plugin remove senysisu.lock
```

## Caveat: Omarchy updates

This is a copy, so it does **not** receive updates Omarchy makes to the
built-in lock screen. If an update changes or fixes the original, either switch
back to it, or re-clone (`omarchy plugin clone omarchy.lock` after removing or
renaming this folder) and re-apply the changes above. The original source is in
`/usr/share/omarchy/shell/plugins/lock/` for comparison:

```bash
diff /usr/share/omarchy/shell/plugins/lock/LockView.qml ~/.config/omarchy/plugins/senysisu.lock/LockView.qml
```
