# Airplane Mode bar widget — VERIFIED, WORKING

A one-tap toggle for WiFi + Bluetooth + LTE, built as a real Omarchy
Quickshell bar-widget plugin (`roger.airplane-mode`), confirmed working
end-to-end on 2026-08-29.

## Quick start

```bash
chmod +x install-airplane-mode-plugin.sh
./install-airplane-mode-plugin.sh
```

## What's in here

| File | Purpose |
|---|---|
| `install-airplane-mode-plugin.sh` | Installs scripts + plugin, enables it, restarts the shell |
| `omarchy-airplane-mode-data` | Backing script the widget polls for live WiFi/WWAN/Bluetooth state |
| `omarchy-airplane-mode-toggle` | Backing script the widget runs on click — engage/restore logic |
| `roger.airplane-mode/manifest.json` | Plugin registration |
| `roger.airplane-mode/Panel.qml` | The actual bar icon (single file — see below) |
| `roger.airplane-mode/Model.js` | Icon/tooltip parsing logic used by Panel.qml |

## Behavior

- Icon sits in the bar's center section, immediately right of `omarchy.weather`.
- Click: if WiFi, Bluetooth, and the LTE modem are all currently on (or any
  mix), this **engages** airplane mode — snapshots each radio's current
  state to `~/.local/state/omarchy-airplane-mode.json`, then disables all
  three. If all three are currently off, this **restores** each radio to
  whatever the snapshot says it was before (a radio that was already off
  stays off), then deletes the snapshot.
- Direction is computed from live radio state, not an internal on/off flag
  — "airplane mode is on" means all three are currently off. This is
  intentional: it's what lets the user turn any one radio back on from its
  own panel (WiFi/Bluetooth/LTE) while airplane mode is "on", without this
  plugin fighting that change on the next poll. One consequence: if you
  manually re-enable a radio and then click the toggle again, it reads as
  "not all off" and re-engages (snapshot + disable again) rather than
  resuming a stale restore — that's the spec this was built against, not a
  bug.
- The icon polls continuously (every 5s) and colors itself via
  `BarIconButton`'s `active` state, computed fresh each poll — so it never
  drifts from actual hardware state.

## Real bugs found & fixed while building this

**1. Single `Panel.qml`, not a `BarWidget.qml` + `Panel.qml` pair.**
Same lesson already learned building `roger.lte`: a published Omarchy
plugin-dev tutorial shows the two-file split, but that's not how Omarchy's
own built-in widgets (or `roger.lte`) are actually structured in this
version. `manifest.json` here points `entryPoints.barWidget` straight at
`Panel.qml`, confirmed by reading `roger.lte`'s manifest and comparing
against several first-party plugins (`omarchy.weather`, `omarchy.dropbox`)
before writing anything.

**2. `mmcli -e`/`-d` for the LTE leg would have refought the same NetworkManager
autoconnect battle already fixed once in `roger.lte`.** Caught this before
writing any code (from `roger.lte`'s own Panel.qml comment) and used
`nmcli radio wwan on`/`off` instead — same mechanism `roger.lte` already
uses. Side benefit: no sudoers rule needed for this plugin at all, since
`nmcli radio` commands don't require root.

**3. Wrong glyph codepoint.** The airplane Nerd Font codepoint from memory
(`U+F0538`) actually renders as a trophy icon in the installed
`JetBrainsMono Nerd Font` — Nerd Fonts renumbers Material Design Icons'
codepoints per release, so a remembered hex value from an older version is
not reliable. Caught by literally rendering the glyph with ImageMagick
against the installed font file before shipping it, then cross-checked the
correct codepoint (`U+F001D`, `md-airplane`) against nerd-fonts' own
`glyphnames.json` and re-rendered to confirm the shape.

**4. `omarchy plugin list --json`'s `active` field is not a bar-widget
health signal.** It's structurally always `false` for any `kind:
"bar-widget"` plugin — the shell only computes it for `kind: "bar"`
(whole-bar replacements). Even the already-working `roger.lte` and the
first-party `omarchy.weather` show `active: false`. The real signals are
`enabled: true` (placed in the bar layout) plus the widget actually showing
up in `omarchy-shell shell debugBarGeometry` and a clean `qs log`.

## Known gotcha: don't misread live radio-state changes during testing

While testing, WiFi flipping back on a few seconds after being disabled
looked at first exactly like the NetworkManager-autoconnect fight already
seen with the LTE modem. It wasn't: it was the bar's own WiFi switch being
clicked by a human on the same machine mid-test, to keep that session's own
network access alive. `journalctl -u NetworkManager` attributes a
radio-control change to the PID that requested it — if that PID is the
running `quickshell` process, it can mean the bar's own toggle was used,
not a background reconciliation service. Don't assume the plugin is being
fought without checking who actually issued the change.

## Debugging, if something doesn't load

```bash
omarchy plugin list --json | jq '.[] | select(.id == "roger.airplane-mode")'
qs log -p "$OMARCHY_PATH/shell" --tail 100
omarchy plugin validate ~/.config/omarchy/plugins/roger.airplane-mode
omarchy-shell shell debugBarGeometry | jq '.[] | select(.id == "roger.airplane-mode")'
```

A hot rescan (`omarchy-shell shell rescanPlugins`) reloads the plugin's QML
component but did NOT reliably pick up a `Model.js` change during testing —
a full `omarchy restart shell` was required to see the corrected icon.
`install-airplane-mode-plugin.sh` does the full restart automatically.
