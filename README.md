# senysisu Omarchy plugins

My customizations for [Omarchy](https://omarchy.org/), in two families:

- **Password screens.** The lock screen and the boot-time disk-unlock
  screen share one look: the blurred wallpaper, a stacked poster clock, the
  date and a pill password field, in the current Omarchy theme's colors.
  Whether the laptop is booting or waking up, the password prompt looks the
  same.
- **Bar widgets.** Small, quiet additions to the Omarchy bar. Three system
  monitors (CPU, memory, disk) show a minimal gauge that turns red when
  something needs attention, and open a detail panel on click. Two radio
  controls handle the LTE modem and airplane mode.

Everything here is portable and installs on any Omarchy machine with one
script. Machine-specific hardware setup (e.g. the Intel XMM7560 modem's SIM
slot fix and systemd unit) lives separately in `dragonfly-lte-setup`.

## Quick start

```bash
git clone git@github.com:rogercarullabove/omarchy-senysisu-plugins.git
cd omarchy-senysisu-plugins

# Password screens
./install.sh senysisu.lock                  # asks for the theme and wallpaper; --theme skips that
./install.sh senysisu.plymouth --preview    # look first, then without --preview

# Bar widgets: system monitors
./install.sh senysisu.cpu  --section left --after omarchy.workspaces
./install.sh senysisu.ram  --after senysisu.cpu
./install.sh senysisu.disk --after senysisu.ram

# Bar widgets: radios
./install.sh senysisu.lte
./install.sh senysisu.airplane-mode --after omarchy.weather
```

`install.sh` copies a bar widget into `~/.config/omarchy/plugins/` and its
scripts into `~/.local/bin`, validates it, places it in the bar and restarts
the shell. Placement is optional: `--section left|center|right` picks the bar
zone, and `--before`/`--after <widget-id>` puts it next to another widget.
Without them a widget goes to the end of its default zone. Move it later by
dragging it or with `omarchy bar move`.

The password screens aren't bar widgets, so `install.sh` hands them to their
own installers (`senysisu.lock/install.sh`, `senysisu.plymouth/install.sh`),
which also take `--uninstall` to go back to Omarchy's originals.

## Password screens

| Plugin | What it replaces | Settings |
|---|---|---|
| [`senysisu.lock`](senysisu.lock/README.md) | Omarchy's lock screen (`omarchy.lock`) | `~/.config/omarchy/plugins/senysisu.lock/settings.lua`, applied live on save |
| [`senysisu.plymouth`](senysisu.plymouth/README.md) | Omarchy's boot / disk-unlock screen (Plymouth) | `~/.config/omarchy/plugins/senysisu.plymouth/settings.lua`, applied by re-running its installer |

Both can be pinned to any installed Omarchy theme and wallpaper
(`theme = "name"` or `"name,N"` for its Nth wallpaper) instead of following
the current one.

### senysisu.lock

A clone of Omarchy's lock screen with a stacked poster clock and date, a
weather line, battery and Wi-Fi indicators in any corner, a show-password
toggle, a pill password field, and weather effects that follow the real
weather or can be set by hand: color grading for weather and time of day,
layered rain whose nearest layer passes in front of the clock, storms with
lightning, and snow.

- It's a `service` plugin. `Service.qml` (locking, PAM password and
  fingerprint) is unchanged from Omarchy; `LockView.qml` is the UI and
  `WeatherBackdrop.qml` the effects, with textures in `assets/`.
- Its installer keeps an existing `settings.lua`, swaps the plugin in for
  `omarchy.lock`, and re-enables `omarchy.lock` if anything fails, so the
  machine is never left without a lock screen. It refuses to run while the
  session is locked.
- Like the boot screen's, it asks which theme and wallpaper to use, listing
  the installed themes with their wallpaper counts. `--theme lua`,
  `--theme current` or `--theme <name>[,<n>]` answers without asking; the
  choice is written to its `settings.lua`, which the lock reads live.
- Try changes with `omarchy-shell lock preview`, not by locking (see the
  lessons below).

### senysisu.plymouth

A Plymouth theme that draws the disk-unlock prompt at boot like the lock
screen: blurred wallpaper, stacked clock, date, password field, battery
corner, and a caption under the password field ("LUKS disk password" by
default). Plymouth has no clock of its own, so an initramfs hook hands it
the local time, and a pacman hook selects the theme again after an Omarchy
update resets the boot theme to its own.

- It isn't a shell plugin: there is no manifest, and the Omarchy shell
  ignores its settings folder. The installer renders the theme, installs it
  with sudo, test-builds it and rebuilds the boot images.
- `--preview` shows it in a window without root and without installing
  anything.
- Its settings hold only what a boot screen can show (`clock`, `date`,
  `battery`, `password`, `background.blur`, `theme`, `hint`), with the same
  meaning and defaults as the lock screen's.

## Bar widgets

| Plugin | In the bar | Click for |
|---|---|---|
| [`senysisu.cpu`](senysisu.cpu/README.md) | Per-core sparkline (or columns, ring, percent) | Load, clocks, temperature, 60-second graph, top processes |
| [`senysisu.ram`](senysisu.ram/README.md) | Ring gauge and/or percent | Used / cache / free, swap, memory pressure, top processes |
| [`senysisu.disk`](senysisu.disk/README.md) | Ring gauge and/or percent for the fullest watched mount | Every filesystem, read/write activity per disk |
| `senysisu.lte` | Signal bars for the LTE modem | Operator, technology, roaming, state, ping, power toggle |
| `senysisu.airplane-mode` | Airplane icon | Toggles Wi-Fi, Bluetooth and LTE together |

### System monitors: cpu, ram, disk

Three independent plugins that look like one family. Each draws
`[icon] [gauge] [percent]` in the theme's bar color and turns the theme's
urgent color (red) at a threshold, 90% by default. They only return to
normal 5 points below it, so a value sitting on the line doesn't flicker,
and CPU averages the last 10 seconds so a short spike doesn't trigger it.

- **Clicks:** left opens the panel, middle refreshes, right opens `btop`.
- **Settings** live on the widget's own entry in `~/.config/omarchy/shell.json`
  and are easiest to change from the terminal:

  ```bash
  omarchy bar set senysisu.cpu  style columns      # sparkline, columns, ring, percent, ring+percent
  omarchy bar set senysisu.ram  style ring         # ring+percent, ring, percent
  omarchy bar set senysisu.disk mounts '["/", "/run/media/roger/usb"]' --json
  omarchy bar set senysisu.ram  warnAt 80
  omarchy bar set senysisu.cpu  panel cores        # each plugin has three panel layouts
  ```

  Every widget also takes `icon` (any text or emoji), `showIcon` and
  `interval`. Each plugin's README lists its options.
- **Cost:** CPU and memory read `/proc` directly, so the bar starts no
  process to update them. Disk runs a few-millisecond `df` every 30 seconds.
  Panel-only details (processes, temperature, throughput) are only fetched
  while a panel is open.
- **Vertical bars:** the icon stacks above the gauge, and wide styles fall
  back to the ring.

### Radios: lte, airplane-mode

**senysisu.lte** shows the modem's signal (polled from `mmcli` by
`~/.local/bin/omarchy-lte-data`), and its panel shows operator, technology,
roaming, state and ping, with a power toggle. The modem index is looked up
with `mmcli -L` on every poll, since it can change across boots or after a
SIM slot switch.

**senysisu.airplane-mode** turns Wi-Fi, Bluetooth and the LTE modem off and
back on as one action.

- With any radio on, a click **engages**: it saves each radio's state to
  `~/.local/state/omarchy-airplane-mode.json` and turns all three off. With
  all three off, a click **restores** each radio as saved (one that was
  already off stays off) and deletes the file.
- The direction comes from the radios' live state, not a stored flag, so
  you can turn one radio back on from its own panel without this plugin
  fighting you. Clicking again after that engages again rather than
  restoring a stale snapshot. That's intended.

Both switch the modem with `nmcli radio wwan on|off`, never `mmcli -e|-d`
(see the lessons below), so neither needs a sudoers rule.

### How a bar widget is built

```
senysisu.<name>/
  manifest.json   plugin registration: id, "kinds": ["bar-widget"], default zone
  BarWidget.qml   entry point: the bar button, settings, IPC; hosts Panel.qml
  Panel.qml       the detail popup
  Gauge.qml       custom bar graphics (cpu, ram, disk)
  Model.js        parsing, thresholds and formatting; loadable in node for quick checks
  bin/            helper scripts, installed to ~/.local/bin
  README.md       settings reference
```

`senysisu.airplane-mode` predates this shape: its `Panel.qml` is the entry
point and draws the bar icon itself (see lesson 1).

## Repository

- `install.sh`: the shared installer described above.
- `docs/cpu-ram-disk-plan.md`: the plan the system monitors were built
  from, with the decisions behind them.
- `dev/senysisu.cpu`, `dev/senysisu.ram`, `dev/senysisu.disk`: development
  branches for the system monitors, kept for further tweaks. Each is merged
  into `master` on its own when ready.

## Lessons learned

These apply to any plugin added here.

### Bar widgets and the shell

**1. A bar widget's entry point is `BarWidget.qml`, which loads a nested
`Panel.qml` with a `Loader`.** That's what
[the official plugin docs](https://plugins.omarchy.org/develop.html) describe
and what the first-party plugins under `/usr/share/omarchy/shell/plugins/`
do. `BarWidget.qml` extends `BarWidget` (from `qs.Ui`), owns the bar button
and forwards `open()`/`close()`/`toggle()`/`opened`/`popoutSwitchClosing`/
`closeForPopoutSwitch()` to the panel. `Panel.qml` extends `Panel`, sets
`manageIpc: false` (the widget's `IpcHandler` is the live one) and gets
`bar`/`settings`/`anchorItem`/`hostWidget` from the widget when it loads.
Both share one `moduleName`. A single `Panel.qml` entry point (as in
`senysisu.airplane-mode`) validates and runs, but misses the popout
lifecycle. Getting the base class wrong (e.g. setting `moduleName` on a type
that doesn't declare it) can take down the whole desktop with `TypeError:
Cannot assign to read-only property "moduleName"`.

**2. Keep "poll for data" separate from "refresh everything".** When a
widget's `refresh()` refreshes its panel, the panel must not call the
widget's `refresh()` back: `senysisu.disk` briefly did, and recursed until
QML threw `RangeError: Maximum call stack size exceeded`. The widget now has
`poll()` for its own data, and the panel calls that.

**3. Widget settings belong to the running shell.** A widget's settings are
the extra keys on its entry in `~/.config/omarchy/shell.json`, read with
`setting(name, fallback)`. The shell keeps that file in memory and writes it
itself, so editing it by hand while the shell runs has no effect and can be
overwritten. Use `omarchy bar set <id> <key> <value>`. There is no command
to remove a key; `omarchy plugin disable` then `enable` (with placement)
re-adds the widget with an `{id}`-only entry.

**4. A new plugin has to be rescanned before it can be enabled.**
`omarchy plugin enable` refuses an id the running shell hasn't seen yet;
`omarchy-shell shell rescanPlugins` makes it known. `install.sh` does this.

**5. Hot reloads are not enough; restart the shell.** Saving a plugin file
logs "Local plugin changed, reloading", but a reloaded `Model.js` constant
kept showing the old value, and the old instance keeps its IPC target
("Handler was registered but will not be used because another handler is
registered"), so `omarchy-shell <id> ...` calls reach stale code. After a code
change, run `omarchy restart shell` (`install.sh` does). The restart is
refused while the session is locked, because the lock screen runs inside the
shell.

**6. `active: false` in `omarchy plugin list --json` is normal for a bar
widget.** The shell only computes `active` for `kind: "bar"` (whole-bar
replacements). The real signals are `enabled: true`, the widget appearing
in `omarchy-shell shell debugBarGeometry`, and a clean `qs log`.

**7. `FileView` reads `/proc` files.** With `blockLoading: true`, calling
`reload()` then `text()` returns fresh `/proc/stat`, `/proc/meminfo`,
`/proc/swaps` and `/proc/diskstats` contents, even though they report a size
of 0. Reading them this way avoids starting a process on every poll, which
for a CPU meter would show up in its own reading.

**8. Don't trust a remembered Nerd Font codepoint: render it.** An airplane
codepoint from memory rendered as a trophy (Nerd Fonts renumbers Material
Design Icons between releases), and `nf-md-memory` turned out to be a chip
that looks like the CPU icon. Render candidates against the installed font
file with ImageMagick and cross-check `glyphnames.json`. Then check the
character actually landed in the source file: a private-use character
(U+E000–U+F8FF, like `nf-fa-memory`'s U+EFC5) was silently dropped by an
editor once, leaving an empty string.

### Radios

**9. Toggle the modem through NetworkManager, not ModemManager.** The
`telia` GSM connection has `autoconnect=yes` with unlimited retries, so
disabling the modem with `mmcli -d` is immediately undone by NetworkManager
and the switch bounces back on. `nmcli radio wwan on|off` is the layer
NetworkManager treats as user intent; it doesn't fight itself and still
powers the modem off.

**10. Check who flipped a radio before blaming the shell.**
`journalctl -u NetworkManager` names the PID behind each radio change. If
it's the `quickshell` process, someone may simply have clicked the bar's own
Wi-Fi or Bluetooth switch; it isn't necessarily a background loop.

### Password screens

**11. A cloned built-in keeps its privileges, which is what makes a custom
lock screen possible.** `omarchy plugin clone omarchy.lock` writes
`omarchy.clonedFrom` into the manifest; the shell then gives the clone the
original's trusted `authentication` capability (PAM) and routes
`omarchy-shell lock ...` to it. A plugin that declares `authentication` on
its own gets nothing, so keep `clonedFrom` intact.

**12. Authentication plugins don't hot-reload code.** The shell refuses to
create a second auth service, so the old lock UI keeps running after a
`.qml` change until `omarchy restart shell`. Data read at runtime, like
`settings.lua` watched with a `FileView`, does update live.

**13. Test the lock screen with its preview, not by locking.**
`omarchy-shell lock preview` shows the real lock UI as an overlay without
locking (click or `omarchy-shell lock hidePreview` to close), so it can be
screenshotted with `grim`. A broken UI behind a real lock is much harder to
get out of. The preview closes on any click, so confirm it is open
(`hyprctl layers -j | grep omarchy-lock-preview`) before measuring anything.

### QML

**14. `visible` reads the effective visibility, parent included.** Binding a
`Loader`'s `visible` to `item.visible` hid every corner indicator for good:
hiding the Loader hides its item, which keeps the Loader hidden. Bind to the
underlying condition instead (e.g. `modelData !== "battery" ||
root.batteryPresent`).

**15. `ImageParticle` ignores `alpha` for color.** Particles blend
premultiplied, and in Qt 6.11 neither `alpha` nor a translucent `color`
reduces the RGB a particle adds: "faint" white puffs at `alpha: 0.07`
rendered solid white. Premultiply yourself (`Qt.rgba(r*a, g*a, b*a, a)`, see
`tint()` in `WeatherBackdrop.qml`), or use item `opacity`.

**16. Animation targets in a running group are read once, at start.** In a
`SequentialAnimation`, a child's `to:` is evaluated when the sequence
starts, not when that step runs. That made raindrops slide up the screen and
kept a looping wind animation on rain's values after switching to storm.
Compute targets before starting, and `restart()` loops when their inputs
change.

**17. A running `ParticleSystem` redraws every frame even with nothing to
draw,** and a stopped one freezes its particles on screen. Run it only when
an emitter can be active, and hide the layer (or `reset()` it) when turning
effects off.

**18. Iterate on visuals outside the live shell.**
- Plain components: `/usr/lib/qt6/bin/qml test.qml` with a `Timer` calling
  `grabToImage(... saveToFile ...)` renders to a PNG in seconds, e.g.
  `WeatherBackdrop.qml` with each weather kind side by side.
- Components that import `qs.Ui`/`qs.Commons`: make a folder that symlinks
  everything in `/usr/share/omarchy/shell` except `shell.qml`, add your own
  `shell.qml` with a plain `QtQuick.Window` and a stand-in `bar` object, and
  run it with `QT_QPA_PLATFORM=offscreen qs -p <folder>/shell.qml`. To
  render a panel's contents, replace `Ui/KeyboardPanel.qml` in that folder
  with a plain `Rectangle` that has the same properties; the real one needs
  a Wayland layer-shell window.
- This also works while the session is locked or the screen is off, when
  `grim` hangs. Do the final check in the real shell.

## Debugging

```bash
omarchy plugin list --json | jq '.[] | select(.id | startswith("senysisu."))'
omarchy plugin validate ~/.config/omarchy/plugins/<plugin-id>
omarchy-shell shell debugBarGeometry | jq '.[] | select(.id == "<plugin-id>")'
qs log -p "$OMARCHY_PATH/shell" --tail 100
journalctl --user -g senysisu.lock          # senysisu.lock settings.lua errors and warnings
```
