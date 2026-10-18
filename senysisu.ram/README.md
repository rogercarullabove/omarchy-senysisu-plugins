# senysisu.ram

Memory usage in the bar as a ring gauge and percentage that turns red past a
threshold, plus a detail panel with the used/cache/free split, swap, memory
pressure and the processes using the most memory.

```bash
./install.sh senysisu.ram                      # appended to the right zone
./install.sh senysisu.ram --section center     # or any zone
./install.sh senysisu.ram --after senysisu.cpu
```

## In the bar

`[icon] [ring] [percent]`, depending on `style`:

| `style` | Draws |
|---|---|
| `ring+percent` (default) | Ring gauge followed by the number |
| `ring` | Ring gauge only |
| `percent` | Number only |

- Used memory is `MemTotal − MemAvailable`. `MemFree` would count
  reclaimable cache as used and turn the widget red on a healthy machine.
- The widget turns the theme's urgent color (red) at `warnAt` and goes back
  below `warnAt − 5`.
- On a vertical bar the icon stacks above the ring; `ring+percent` shows the
  ring only, `percent` shows the number without `%`.

| Input | Action |
|---|---|
| Left click | Open / close the panel |
| Middle click | Refresh now |
| Right click | Open `btop` |
| `omarchy-shell senysisu.ram open\|close\|toggle\|refresh` | Same, from scripts and keybindings |

## Settings

On the widget's entry in `~/.config/omarchy/shell.json` (`bar.layout.<zone>`),
all optional:

```json
{ "id": "senysisu.ram", "style": "ring", "icon": "🧠", "panel": "history" }
```

| Key | Default | Meaning |
|---|---|---|
| `style` | `"ring+percent"` | `ring+percent`, `ring`, `percent` |
| `showIcon` | `true` | Show the leading memory icon |
| `icon` | `` (`nf-fa-memory`) | Any text or emoji instead of the icon |
| `warnAt` | `90` | Percent (1–100) at which the widget turns red |
| `interval` | `3000` | Sampling interval in ms (500–60000) |
| `includeSwap` | `false` | Count swap in the bar figure: (used + swap used) / (RAM + swap) |
| `panel` | `"breakdown"` | `breakdown`, `history`, `minimal` |

Or from the command line, e.g. `omarchy bar set senysisu.ram style ring`.
Unknown values fall back to the default.

## Panel

- **breakdown**: used / total; a bar split into used, cache and free;
  available, cache/buffers, swap (and whether it is zram, a file or a
  partition), memory pressure (the 10-second `some` average from
  `/proc/pressure/memory`, red from 10 %); top 5 processes.
- **history**: memory and swap use over the last 5 minutes with the threshold
  marked, then used, available and swap.
- **minimal**: used, available, swap and an "Open btop" button.

Keys: `r` refresh, `b` or Enter opens btop, Esc closes, Tab moves to the
neighbouring bar panel.

Process memory is PSS (proportional set size) summed over every process with
the same name, so a browser shows as one line with what it really uses: a
page shared by several processes is split between them instead of counted
once per process, as summed RSS would. PSS is only readable for your own
processes; other users' (root daemons) are counted by RSS.

## How it works

- `BarWidget.qml` reads `/proc/meminfo` with a Quickshell `FileView` every
  `interval`; no process is started for the bar. It also keeps the 5-minute
  history, so the graph starts empty after a shell restart.
- `Panel.qml` reads `/proc/swaps` and `/proc/pressure/memory` the same way,
  and runs `bin/omarchy-ram-data` (installed to `~/.local/bin`) for the top
  processes (PSS from `/proc/<pid>/smaps_rollup`, about 50 ms), every 3 s
  and only while it is open.
- `Gauge.qml` draws the ring; `Model.js` holds the parsing, threshold and
  formatting logic (loadable in node).
