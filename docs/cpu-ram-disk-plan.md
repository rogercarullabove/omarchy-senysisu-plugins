# Plan: senysisu.cpu, senysisu.ram, senysisu.disk

Status: implemented on `dev/senysisu.cpu`, `dev/senysisu.ram` and `dev/senysisu.disk`, not merged (2026-10-18).

Three new bar widgets for this repo: CPU, memory and disk usage. Each one is
a small graphic in the bar that turns red past a threshold, and opens a
detail panel when clicked. They are separate plugins with no shared code, each
developed on its own branch and merged to `master` on its own.

## Decisions

| | Decision |
|---|---|
| Plugin ids | `senysisu.cpu`, `senysisu.ram`, `senysisu.disk` |
| Backing scripts | `omarchy-cpu-data`, `omarchy-ram-data`, `omarchy-disk-data` (same pattern as `omarchy-lte-data`) |
| Branches | `dev/senysisu.cpu`, `dev/senysisu.ram`, `dev/senysisu.disk`, each from `master`, merged independently with `--no-ff` |
| Bar placement | Any zone: `left`, `center` or `right`, chosen at install time and movable later |
| Default bar style | CPU: sparkline (per-core caps). RAM: ring gauge + percent. Disk: ring gauge + percent |
| Leading icon | Each widget starts with an icon (CPU chip, memory module, hard disk); can be replaced with any text or emoji, or hidden |
| Default panels | CPU: Overview. RAM: Breakdown. Disk: Mounts list. The other layouts are selectable in settings |
| Warning | Default color is the theme foreground (white); at or above `warnAt` (default 90%) the whole widget turns the theme's urgent color (red) |
| Shared installer change | Done once on `master` before branching (step 0) |

## Bar widget

### Layout

```
[icon] [graphic] [percent]
 󰻠     ▃▁▅▂▇▁▂▃
 󰍛     ◔        71%
 󰋊     ◕        82%
```

- `icon` comes first and is optional (`showIcon`, default `true`).
- `graphic` and `percent` depend on `style`.
- The widget is 26 px tall like every bar widget; width depends on the style.

### Styles

| `style` | What it draws | CPU | RAM | Disk |
|---|---|---|---|---|
| `columns` | One thin column per core, filled bottom-up to that core's usage | yes | – | – |
| `sparkline` | The same per-core columns, but only the top 2 px of each column is drawn: a cap at each core's level | default | – | – |
| `ring` | An 18 px arc gauge, filled clockwise from 12 o'clock | yes | yes | yes |
| `percent` | The number only, e.g. `42%` | yes | yes | yes |
| `ring+percent` | Ring followed by the number | yes | default | default |

CPU columns and sparkline: one column per core, up to `maxColumns` (default 8). On CPUs with
more cores, neighbouring cores are averaged into groups, so a 16-thread CPU
shows 8 columns of 2 threads each.

### Icons

| Plugin | Default icon | Nerd Font name |
|---|---|---|
| CPU | `󰻠` | `nf-md-cpu_64_bit` |
| RAM | `` | `nf-fa-memory` (a RAM stick; `nf-md-memory` renders as a chip, too close to the CPU icon) |
| Disk | `󰋊` | `nf-md-harddisk` |

The codepoints are verified against the installed `JetBrainsMono Nerd Font`
(render it, then check `glyphnames.json`) before shipping, per lesson 5 in
the README. `icon` accepts any string, so `"🧠"`, `"💾"` or `"CPU"` work too.

### Warning color

- Normal: `bar.foreground` (white on the default theme).
- Warning: `bar.urgent` (the theme's red). Icon, graphic and number all switch together.
- On at `value >= warnAt`, off again only below `warnAt - 5`, so the color doesn't flicker at the boundary.
- CPU compares the average of the last 5 samples (about 10 s at the default interval), so short spikes don't turn it red.
- Disk compares the fullest of the watched mounts, and that mount is the one the bar shows.

### Vertical bars

On a left or right bar (28 px wide) the widget stacks: icon above the graphic.
`columns` and `sparkline` fall back to `ring`, and `ring+percent` drops the
number (it stays in the tooltip and the panel).

### Clicks and IPC

| Input | Action |
|---|---|
| Left click | Open / close the detail panel |
| Middle click | Refresh now |
| Right click | Open `btop` (`omarchy-launch-or-focus-tui btop`) |
| Hover | Tooltip with the exact value |
| `omarchy-shell shell summon\|hide\|toggle senysisu.<x>` | Panel control from scripts and keybindings |

## Settings

Settings live on the widget's own entry in `~/.config/omarchy/shell.json`
under `bar.layout.<section>`. The bar already passes that entry to the widget
as `settings` (`Ui/BarWidget.qml`), the same way `omarchy.clock` gets its
`format`. Everything is optional; an invalid value falls back to the default
and logs a warning.

```json
{ "id": "senysisu.cpu",  "style": "columns", "warnAt": 85 },
{ "id": "senysisu.ram",  "style": "ring+percent", "icon": "🧠" },
{ "id": "senysisu.disk", "style": "ring", "mounts": ["/", "/run/media/roger/usb"] }
```

### All plugins

| Key | Type | Default | Meaning |
|---|---|---|---|
| `style` | string | see per-plugin table | Bar graphic, see Styles |
| `showIcon` | bool | `true` | Show the leading icon |
| `icon` | string | Nerd Font glyph | Replace the icon with any text or emoji |
| `warnAt` | number 1–100 | `90` | Percent at which the widget turns red |
| `interval` | ms | CPU 2000, RAM 3000, Disk 30000 | Poll interval for the bar value |
| `panel` | string | see per-plugin table | Detail panel layout |

### Per plugin

| Plugin | `style` values (default first) | `panel` values (default first) | Extra keys |
|---|---|---|---|
| `senysisu.cpu` | `sparkline`, `columns`, `ring`, `percent`, `ring+percent` | `overview`, `cores`, `minimal` | `maxColumns` (default 8) |
| `senysisu.ram` | `ring+percent`, `ring`, `percent` | `breakdown`, `history`, `minimal` | `includeSwap` (default `false`): count swap in the bar value |
| `senysisu.disk` | `ring+percent`, `ring`, `percent` | `mounts`, `activity`, `combined` | `mounts` (default `["/"]`, or `"auto"` for every real filesystem) |

## Detail panels

The default layout for each plugin is listed first.

### CPU

**`overview` (default)**

```
 󰻠  23%                          8 cores · 3.4 GHz · 54 °C
 ─────────────────────────────────────────────────────────
 [ 60-second usage graph ................................ ]
 Load avg      0.82  0.95  1.10
 Frequency     3.4 GHz (max 4.7)
 Temperature   54 °C
 Uptime        3 d 4 h
 ─────────────────────────────────────────────────────────
 Top processes   firefox 18%  ·  qs 4%  ·  hyprland 2% …
```

**`cores`**: a grid with one bar, percent and current clock speed per core,
plus the top 3 processes.

**`minimal`**: usage, load, temperature and frequency, plus an "Open btop" button.

Data: usage from `/proc/stat` differences between polls; load from
`/proc/loadavg`; frequency from `/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq`;
temperature from `/sys/class/hwmon` (`coretemp` or `k10temp`). Top processes
come from `top -b -n2 -d0.5`, not `ps %cpu`, which is a lifetime average.
Process and temperature reads run only while the panel is open.

### RAM

**`breakdown` (default)**

```
 󰍛  71%                               11.2 / 15.6 GiB
 [███████████████▓▓▓▓▓░░░░░░]   used · cache · free
 Available     4.4 GiB
 Cache/buffers 2.9 GiB
 Swap / zram   0.3 / 8 GiB
 Pressure      0.0 % (10 s avg)
 Top processes   firefox 2.1G · code 1.4G · qs 310M …
```

**`history`**: a 5-minute graph of used percent and swap, plus the totals.

**`minimal`**: used, available and swap, plus an "Open btop" button.

Data: used = `MemTotal − MemAvailable` from `/proc/meminfo`, never `MemFree`
(which counts reclaimable cache as used). Pressure from `/proc/pressure/memory`,
swap and zram from `/proc/swaps`, top processes from `ps -eo rss,comm --sort=-rss`.

### Disk

**`mounts` (default)**

```
 󰋊  /  82%                              3 filesystems
 /               btrfs  [████████████████░░░░] 380 / 465 GiB
 /boot           vfat   [██░░░░░░░░░░░░░░░░░░] 0.2 / 2 GiB
 /run/media/usb  exfat  [██████████████████▓▓] 59 / 62 GiB   (red)
```

**`activity`**: the main mount, live read/write speed and a throughput graph,
and the drive model.

**`combined`**: the mounts list, with a read/write line under each physical disk.

Data: `df -B1 --output=source,fstype,size,used,avail,target`, excluding
tmpfs, devtmpfs, efivarfs and overlay. Btrfs subvolumes (`/`, `/home`, …) are
merged by device so one disk isn't listed twice. A lock icon marks
filesystems on `/dev/mapper` (LUKS). Throughput from `/proc/diskstats`
differences, drive model from `/sys/block/*/device/model`. SMART health is
left out: it needs root and `smartmontools`.

## Repository and branches

### Step 0, on `master`

One commit before any branch, so the three branches never edit the same code:

- `install.sh` passes `--section`, `--before` and `--after` through to
  `omarchy plugin enable`.
- `install.sh` copies every `*.qml` and `*.js` file in the plugin folder
  instead of a fixed list, so extra files like a gauge component are installed.
- The usage text stops listing plugin names.

### Branches

```bash
git switch -c dev/senysisu.cpu  master
git switch -c dev/senysisu.ram  master
git switch -c dev/senysisu.disk master
```

Each branch touches only its own `senysisu.<x>/` folder, its own
`senysisu.<x>/README.md`, and one row in the root README's plugin table.
Merging the second and third branch will conflict on neighbouring table rows,
which takes seconds to resolve. A branch that isn't wanted is simply never
merged.

### Plugin layout

```
senysisu.<x>/
  manifest.json   id, "kinds": ["bar-widget"], defaultSection "right", category "System"
  BarWidget.qml   entry point: icon + gauge, warning color, IPC, hosts Panel.qml
  Panel.qml       detail popup (layout picked by the `panel` setting)
  Model.js        parsing, percent math, threshold + hysteresis, formatting
  Gauge.qml       ring / columns / sparkline drawing (each plugin has its own copy)
  bin/            omarchy-<x>-data, if the data isn't read directly (see below)
  README.md       settings reference and screenshots
```

### Install

```bash
./install.sh senysisu.cpu  --section left
./install.sh senysisu.ram  --after senysisu.cpu
./install.sh senysisu.disk --section right --before omarchy.power
```

Move later with `omarchy bar move`, or by dragging the widget in the bar.

## Work on each branch

1. Scaffold `manifest.json` and `BarWidget.qml` from `senysisu.lte`'s
   structure (documented `BarWidget.qml` + nested `Panel.qml` contract).
2. Data layer.
   - CPU branch first tests whether Quickshell's `FileView` reads
     `/proc/stat` and `/proc/meminfo` correctly (they report size 0). If it
     does, CPU and RAM read `/proc` directly and skip the bash process every
     poll; if not, they use a `bin/` script like the others.
   - `Model.js` holds parsing and threshold logic and exports for node, so
     it can be checked with `node -e`.
3. Bar graphic: every `style`, the leading icon, the red warning state and
   the vertical fallback. Render outside the shell with `qml` +
   `grabToImage` (lesson 14), and check the glyphs against the font (lesson 5).
4. Detail panel: the default layout first, then the alternatives.
5. Verify in the real shell:
   - Install into each zone and confirm with `omarchy-shell shell debugBarGeometry` and a clean `qs log`.
   - Set `warnAt: 1` to force the red state.
   - Switch every `style` and `panel` value in `shell.json`.
   - Measure the widget's own CPU cost.
6. Write `senysisu.<x>/README.md`, add the root README row, commit on the
   branch. Merge to `master` when you decide to.

## Resolved during implementation

- `FileView` reads `/proc/stat`, `/proc/meminfo`, `/proc/swaps`,
  `/proc/pressure/memory` and `/proc/diskstats` correctly after `reload()`,
  so CPU and RAM start no process for the bar. The bin scripts only supply
  panel extras (CPU, RAM) or the `df` poll (disk).
- Glyphs checked against the installed font and `glyphnames.json`:
  `md-cpu_64_bit` U+F0EE0, `fa-memory` U+EFC5, `md-harddisk` U+F02CA.
- `install.sh` now rescans plugins before enabling, since a first install
  is otherwise unknown to the running shell.
- The CPU 60-second graph and the RAM 5-minute history live in memory, so
  they start empty after a shell restart.
