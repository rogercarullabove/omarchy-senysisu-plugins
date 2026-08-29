# Omarchy bar-widget plugins

Personal Quickshell bar-widget plugins for [Omarchy](https://omarchy.org/),
kept together here because they share the same install shape and the same
hard-won lessons about how Omarchy's plugin system actually works
(regardless of what a plugin does, that part is identical).

Machine-specific hardware bootstrapping (e.g. the Intel XMM7560 modem's SIM
slot fix and systemd unit) lives separately in `dragonfly-lte-setup`, not
here — this repo is just the portable bar widgets, installable on any
Omarchy machine.

## Quick start

```bash
git clone <this repo>
cd omarchy-bar-plugins
chmod +x install.sh
./install.sh roger.airplane-mode --after omarchy.weather
./install.sh roger.lte
```

`--after <widget-id>` is optional for any plugin — omit it to just append
the widget to its manifest's `defaultSection`.

## What's in here

| Path | Purpose |
|---|---|
| `install.sh` | Shared installer for any plugin in this repo — see Quick start |
| `roger.airplane-mode/` | One-tap toggle for WiFi + Bluetooth + LTE together |
| `roger.lte/` | Signal-bar icon + detail panel for the LTE modem (via `mmcli`), with its own enable/disable toggle |

Each plugin directory is a self-contained, installable unit:

```
roger.<name>/
  manifest.json   plugin registration
  Panel.qml       the bar icon (+ popup panel, for roger.lte) — single entry point
  Model.js        data-fetching/parsing logic used by Panel.qml
  bin/            backing shell scripts the widget shells out to, installed to ~/.local/bin
```

## roger.airplane-mode

Toggles WiFi, Bluetooth, and the LTE modem together as one action.

- Icon sits in the bar's center section, right of `omarchy.weather`.
- Click: if all three radios are currently on (or any mix), this
  **engages** — snapshots each radio's current state to
  `~/.local/state/omarchy-airplane-mode.json`, then disables all three. If
  all three are currently off, this **restores** each radio to whatever the
  snapshot says (a radio that was already off stays off), then deletes the
  snapshot.
- Direction is computed from live radio state, not an internal on/off flag
  — "airplane mode is on" means all three are currently off. This lets the
  user turn any one radio back on from its own panel while airplane mode is
  "on", without this plugin fighting that change on the next poll. One
  consequence: manually re-enabling a radio and then clicking the toggle
  again reads as "not all off" and re-engages (snapshot + disable again)
  rather than resuming a stale restore — that's intentional, not a bug.
- LTE uses `nmcli radio wwan on`/`off`, not `mmcli -e`/`-d` — see the shared
  lesson below. No sudoers rule needed.

## roger.lte

Signal-bar icon reflecting live modem state (`~/.local/bin/omarchy-lte-data`
polls `mmcli`), with a popup panel showing operator, technology, roaming,
state, and ping, plus a power toggle.

- Toggling uses `nmcli radio wwan on`/`off`, not `mmcli -e`/`-d` directly —
  see below.
- Modem index is resolved dynamically via `mmcli -L` on every poll, never
  hardcoded, since it can change across boots or after a SIM slot switch.

## Lessons learned building these (apply to any future plugin here)

**1. A plugin's bar entry point is a single `Panel.qml`, not a
`BarWidget.qml` + `Panel.qml` pair.** A published Omarchy plugin-dev
tutorial shows the two-file split; that's not how Omarchy's own built-in
widgets (or these two) are actually structured in this version.
`manifest.json`'s `entryPoints.barWidget` points straight at `Panel.qml`,
which itself extends the shared `Panel` base (from `qs.Ui`) and embeds its
own `BarIconButton` — confirmed by reading several first-party plugins
(`omarchy.weather`, `omarchy.dropbox`) before writing anything new. Getting
this wrong once caused a `TypeError: Cannot assign to read-only property
"moduleName"` that took down the whole desktop.

**2. Toggling a radio via the tool that "owns" it directly (`mmcli -e`/`-d`
for the modem) can fight NetworkManager's autoconnect.** The `telia` GSM
connection has `autoconnect=yes` with unlimited retries — disabling the
modem straight through ModemManager gets immediately reversed by NM, so the
toggle shows "enabling" and bounces back on, never actually turning off.
`nmcli radio wwan on`/`off` is the layer NetworkManager itself treats as
explicit user intent, so it doesn't fight itself, and it still cascades
down to actually power the modem off. Both plugins here use this for the
modem; it also means no sudoers rule is needed for either.

**3. `omarchy plugin list --json`'s `active` field is not a bar-widget
health signal.** It's structurally always `false` for any `kind:
"bar-widget"` plugin — the shell only computes it for `kind: "bar"`
(whole-bar replacements). Even a widget that's actually rendering fine
(confirmed via `omarchy-shell shell debugBarGeometry`) shows `active:
false`. The real signals are `enabled: true` (placed in the bar layout)
plus the widget showing up in `debugBarGeometry` and a clean `qs log`.

**4. A hot rescan is not always enough to see a change.** `omarchy-shell
shell rescanPlugins` reloads a plugin's QML component but did not reliably
pick up a `Model.js` constant change during testing (a corrected icon
codepoint kept showing the old glyph after a rescan). A full `omarchy
restart shell` was required. `install.sh` does the full restart
automatically.

**5. Don't trust a remembered Nerd Font codepoint — render it.** An
airplane glyph codepoint pulled from memory rendered as a trophy icon in
the installed `JetBrainsMono Nerd Font` (Nerd Fonts renumbers Material
Design Icons' codepoints per release). Caught by rendering the glyph with
ImageMagick against the actual installed font file before shipping it, then
cross-checking the corrected codepoint against nerd-fonts' own
`glyphnames.json`.

**6. Don't misattribute a radio flipping back on to "the shell is fighting
me" without checking who did it.** `journalctl -u NetworkManager` attributes
each radio-control change to the PID that requested it. If that PID is the
running `quickshell` process, it can just mean the bar's own WiFi/Bluetooth
switch was clicked by a person at the same machine — not a background
reconciliation loop. Confirm the actual actor before assuming a bug.

## Debugging, if something doesn't load

```bash
omarchy plugin list --json | jq '.[] | select(.id == "roger.airplane-mode" or .id == "roger.lte")'
qs log -p "$OMARCHY_PATH/shell" --tail 100
omarchy plugin validate ~/.config/omarchy/plugins/<plugin-id>
omarchy-shell shell debugBarGeometry | jq '.[] | select(.id == "<plugin-id>")'
```
