# Omarchy plugins

Personal Quickshell shell plugins for [Omarchy](https://omarchy.org/): bar
widgets plus a custom lock screen, kept together here because they share the
same hard-won lessons about how Omarchy's plugin system actually works
(regardless of what a plugin does, that part is identical).

Machine-specific hardware bootstrapping (e.g. the Intel XMM7560 modem's SIM
slot fix and systemd unit) lives separately in `dragonfly-lte-setup`, not
here — this repo is just the portable plugins, installable on any Omarchy
machine.

## Quick start

```bash
git clone <this repo>
cd omarchy-plugins
chmod +x install.sh
./install.sh roger.airplane-mode --after omarchy.weather
./install.sh roger.lte
./install.sh roger.lock
```

`--after <widget-id>` is optional for any bar widget — omit it to just
append the widget to its manifest's `defaultSection`. `roger.lock` isn't a
bar widget: `install.sh` hands it off to `roger.lock/install.sh` (see below).

## What's in here

| Path | Purpose |
|---|---|
| `install.sh` | Shared installer for any plugin in this repo — see Quick start |
| `roger.airplane-mode/` | One-tap toggle for WiFi + Bluetooth + LTE together |
| `roger.lte/` | Signal-bar icon + detail panel for the LTE modem (via `mmcli`), with its own enable/disable toggle |
| `roger.lock/` | Custom lock screen (replaces `omarchy.lock`), configured from a Lua file — see its own README |

Each plugin directory is a self-contained, installable unit. The bar
widgets share this shape:

```
roger.<name>/
  manifest.json   plugin registration
  BarWidget.qml   manifest entry point — bar icon/button, loads Panel.qml (roger.lte only; see below)
  Panel.qml       popup panel (roger.lte) or, for roger.airplane-mode, the bar icon itself
  Model.js        data-fetching/parsing logic used by BarWidget.qml/Panel.qml
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
- Structured per the documented `BarWidget.qml` + `Panel.qml` contract (see
  lesson 1 below): `BarWidget.qml` is the manifest entry point and owns the
  bar icon button; `Panel.qml` is loaded into it and owns the modem
  poll/toggle logic and the popup. Supports `omarchy-shell shell
  summon|hide|toggle roger.lte` via `BarWidget.qml`'s `IpcHandler`.

## roger.lock

A customized clone of Omarchy's built-in lock screen: stacked poster clock
with date, weather line, battery and Wi-Fi indicators placeable in any
corner, a show-password toggle, and a pill password field. Everything is set
from `roger.lock/settings.lua`, which applies live on save. Colors follow the
current Omarchy theme.

It's a different shape from the bar widgets — a `service` plugin with
`Service.qml` (locking + PAM, unchanged from Omarchy) and `LockView.qml` (the
UI) — so it ships its own `roger.lock/install.sh`, which the shared
`install.sh` hands off to whenever a plugin folder has one. That installer
keeps an existing `settings.lua`, swaps the plugin in for `omarchy.lock`, and
re-enables `omarchy.lock` if anything fails, so the machine is never left
without a lock screen. `./install.sh roger.lock --uninstall` switches back.

Full details (settings reference, layout, caveats):
[`roger.lock/README.md`](roger.lock/README.md).

## Lessons learned building these (apply to any future plugin here)

**1. A plugin's manifest entry point is `BarWidget.qml`, which loads a
nested `Panel.qml` via a `Loader` — per
[the official plugin-dev docs](https://plugins.omarchy.org/develop.html)
and confirmed by reading the installed first-party plugins
(`omarchy.weather`, `omarchy.clock` under `/usr/share/omarchy/shell/plugins/`).
`BarWidget.qml` extends the `BarWidget` base (from `qs.Ui`), owns the bar
button, and forwards `open()`/`close()`/`toggle()`/`opened`/
`popoutSwitchClosing`/`closeForPopoutSwitch()` to whatever `Panel.qml`
loads; `Panel.qml` extends the `Panel` base, sets `manageIpc: false` (the
`BarWidget.qml` `IpcHandler` is the one that's live), and takes
`anchorItem`/`hostWidget` from its host via the `Loader`'s `onLoaded`. Both
files share the same `moduleName`. `roger.lte` follows this split;
`roger.airplane-mode` still predates it — a single `Panel.qml` as the
entry point, which `omarchy plugin validate` accepts and which does run,
but doesn't match the documented contract (no `BarWidget.qml`, no popout
lifecycle forwarding). An earlier, wrong belief that the single-file shape
was actually correct came from an older observation of the shell that
didn't hold up on a fresh read of the current first-party sources — worth
re-checking before trusting it again. Getting the base class wrong entirely
(e.g. assigning to `moduleName` on a type that doesn't declare it) can take
down the whole desktop with a `TypeError: Cannot assign to read-only
property "moduleName"`.

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

**7. A cloned built-in keeps its privileges; that's what makes a custom lock
screen possible.** `omarchy plugin clone omarchy.lock` writes
`omarchy.clonedFrom` into the clone's manifest, and the shell copies the
source's trusted capabilities (here `authentication`, i.e. PAM access) onto
the clone and routes the built-in's IPC target (`omarchy-shell lock ...`) to
it. A from-scratch third-party plugin declaring `authentication` itself gets
nothing — keep `clonedFrom` intact when editing the manifest.

**8. Authentication plugins don't hot-reload their code.** Saving a `.qml`
file logs "Local plugin changed, reloading" but the running lock service is
kept (the shell refuses to create a second auth service), so the old UI keeps
showing. `omarchy restart shell` is required after code changes. Data the
plugin reads at runtime (like `roger.lock/settings.lua`, watched with a
`FileView`) does update live.

**9. Test the lock screen with its preview, not by locking.**
`omarchy-shell lock preview` shows the real lock UI as an overlay without
locking the session (click or `omarchy-shell lock hidePreview` to close), so
it can be screenshotted with `grim` and iterated on safely. A broken lock UI
behind a real session lock is much harder to get out of.

**10. In QML, `visible` reads the *effective* visibility, parent included.**
Binding a `Loader`'s `visible` to `item.visible` made every corner indicator
permanently invisible: hiding the Loader hides its item, which keeps the
Loader hidden. Bind to the underlying condition instead (e.g.
`modelData !== "battery" || root.batteryPresent`).

## Debugging, if something doesn't load

```bash
omarchy plugin list --json | jq '.[] | select(.id | startswith("roger."))'
journalctl --user -g roger.lock          # roger.lock settings.lua errors / warnings
qs log -p "$OMARCHY_PATH/shell" --tail 100
omarchy plugin validate ~/.config/omarchy/plugins/<plugin-id>
omarchy-shell shell debugBarGeometry | jq '.[] | select(.id == "<plugin-id>")'
```
