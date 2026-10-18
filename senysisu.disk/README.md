# senysisu.disk

Disk usage in the bar as a ring gauge and percentage that turns red past a
threshold, plus a detail panel with every filesystem and live read/write
activity.

```bash
./install.sh senysisu.disk                      # appended to the right zone
./install.sh senysisu.disk --section left       # or any zone
./install.sh senysisu.disk --after senysisu.ram
```

## In the bar

`[icon] [ring] [percent]`, depending on `style`:

| `style` | Draws |
|---|---|
| `ring+percent` (default) | Ring gauge followed by the number |
| `ring` | Ring gauge only |
| `percent` | Number only |

- The bar shows the **fullest of the watched mounts** (`mounts`, default
  `["/"]`), so it turns red when any of them reaches `warnAt`. The tooltip
  names the mount and its free space.
- Percent is `used / (used + available)`, like `df`'s `Use%`, so space
  reserved for root counts as unavailable.
- The color goes back to normal below `warnAt − 5`.
- On a vertical bar the icon stacks above the ring; `ring+percent` shows the
  ring only, `percent` shows the number without `%`.

| Input | Action |
|---|---|
| Left click | Open / close the panel |
| Middle click | Refresh now |
| Right click | Open `btop` |
| `omarchy-shell senysisu.disk open\|close\|toggle\|refresh` | Same, from scripts and keybindings |

## Settings

On the widget's entry in `~/.config/omarchy/shell.json` (`bar.layout.<zone>`),
all optional:

```json
{ "id": "senysisu.disk", "mounts": ["/", "/run/media/roger/usb"], "panel": "combined" }
```

| Key | Default | Meaning |
|---|---|---|
| `style` | `"ring+percent"` | `ring+percent`, `ring`, `percent` |
| `showIcon` | `true` | Show the leading disk icon |
| `icon` | `󰋊` (`nf-md-harddisk`) | Any text or emoji instead of the icon |
| `warnAt` | `90` | Percent (1–100) at which the widget turns red |
| `interval` | `30000` | Poll interval in ms (1000–3600000) |
| `mounts` | `["/"]` | Mount points the bar watches, or `"auto"` for every filesystem |
| `panel` | `"mounts"` | `mounts`, `activity`, `combined` |

A watched path that isn't its own mount point (e.g. `/home` on a btrfs
subvolume) counts as the filesystem that contains it. A watched mount that
isn't mounted right now (an unplugged USB drive) is skipped.

Or from the command line, e.g. `omarchy bar set senysisu.disk style ring`.
Unknown values fall back to the default.

## Panel

- **mounts**: every real filesystem with its type, LUKS mark, used / total
  and a meter (red past `warnAt`).
- **activity**: the bar's mount, then for each physical disk its model, a
  one-minute graph (filled: read, line: write) and the current read and
  write speed.
- **combined**: filesystems grouped by physical disk, with each disk's
  read/write speed above its filesystems.

Keys: `r` refresh, `b` or Enter opens btop, Esc closes, Tab moves to the
neighbouring bar panel.

## How it works

- `bin/omarchy-disk-data` (installed to `~/.local/bin`) runs `df` without
  tmpfs, devtmpfs, efivarfs, overlay, squashfs and ramfs, lists a filesystem
  mounted more than once (btrfs subvolumes) only at its shortest mount
  point, and walks `lsblk` to find each filesystem's physical disk, model and
  whether it sits on LUKS. It takes a few milliseconds and runs every
  `interval`.
- `Panel.qml` reads `/proc/diskstats` with a Quickshell `FileView` every 2 s
  while it is open (not at all for the `mounts` layout) and computes
  throughput per physical disk.
- SMART health isn't shown: it needs root and `smartmontools`.
- `Gauge.qml` draws the ring; `Model.js` holds the parsing, mount matching,
  threshold and formatting logic (loadable in node).
