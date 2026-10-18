# senysisu.cpu

CPU usage in the bar, one column per core, that turns red when the CPU stays
busy, plus a detail panel with load, clock speeds, temperature and the
busiest processes.

```bash
./install.sh senysisu.cpu                      # appended to the right zone
./install.sh senysisu.cpu --section left       # or any zone
./install.sh senysisu.cpu --after omarchy.clock
```

## In the bar

`[icon] [graphic] [percent]`, depending on `style`:

| `style` | Draws |
|---|---|
| `sparkline` (default) | One column per core, only a 2 px cap at each core's level |
| `columns` | One column per core, filled bottom-up |
| `ring` | Arc gauge of total usage |
| `percent` | Total usage as a number |
| `ring+percent` | Ring followed by the number |

- More cores than `maxColumns` are averaged in neighbouring groups (12 threads
  with the default 8 show as 6 columns of 2).
- The widget turns the theme's urgent color (red) when the **average of the
  last 5 samples** (about 10 s) reaches `warnAt`, and goes back below
  `warnAt − 5`. A short spike doesn't trigger it.
- On a vertical bar the icon stacks above the graphic; `columns` and
  `sparkline` fall back to the ring, and `ring+percent` shows the ring only.

| Input | Action |
|---|---|
| Left click | Open / close the panel |
| Middle click | Refresh now |
| Right click | Open `btop` |
| `omarchy-shell senysisu.cpu open\|close\|toggle\|refresh` | Same, from scripts and keybindings |

## Settings

On the widget's entry in `~/.config/omarchy/shell.json` (`bar.layout.<zone>`),
all optional:

```json
{ "id": "senysisu.cpu", "style": "columns", "warnAt": 85, "panel": "cores" }
```

| Key | Default | Meaning |
|---|---|---|
| `style` | `"sparkline"` | `sparkline`, `columns`, `ring`, `percent`, `ring+percent` |
| `showIcon` | `true` | Show the leading CPU icon |
| `icon` | `󰻠` (`nf-md-cpu_64_bit`) | Any text or emoji instead of the icon |
| `warnAt` | `90` | Percent (1–100) at which the widget turns red |
| `interval` | `2000` | Sampling interval in ms (500–60000) |
| `maxColumns` | `8` | Most columns `sparkline`/`columns` draw |
| `panel` | `"overview"` | `overview`, `cores`, `minimal` |

Or from the command line, e.g. `omarchy bar set senysisu.cpu style columns`.
Unknown values fall back to the default.

## Panel

- **overview**: usage, threads, average clock and temperature; CPU model; a
  60-second usage graph with the threshold marked; load average, frequency,
  temperature, uptime; top 5 processes.
- **cores**: one bar per thread with its usage (red past `warnAt`) and clock
  in GHz; top 3 processes.
- **minimal**: usage, load, frequency, temperature and an "Open btop" button.

Keys: `r` refresh, `b` or Enter opens btop, Esc closes, Tab moves to the
neighbouring bar panel.

Process figures are each process's share of the whole CPU (same scale as the
bar), from a 0.5 s `top` sample. `ps %cpu` would be an average over each
process's lifetime.

## How it works

- `BarWidget.qml` reads `/proc/stat` with a Quickshell `FileView` every
  `interval` and computes per-core usage from the difference between samples.
  No process is started for the bar, so the widget doesn't show up in its
  own reading.
- `bin/omarchy-cpu-data` (installed to `~/.local/bin`) prints the panel-only
  details as JSON: model, load, uptime, per-core `scaling_cur_freq`, package
  temperature from the `coretemp`/`k10temp`/`zenpower`/`cpu_thermal` hwmon,
  and the top processes. It runs every 3 s only while the panel is open.
- `Gauge.qml` draws the columns, sparkline and ring; `Model.js` holds the
  parsing, grouping, threshold and formatting logic (loadable in node).
