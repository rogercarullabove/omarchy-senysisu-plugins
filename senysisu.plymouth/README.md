# senysisu boot screen (`senysisu.plymouth`)

A Plymouth theme that draws the disk-unlock prompt at boot like the
`senysisu.lock` lock screen: the blurred wallpaper, the stacked poster clock,
the date, the password field (pill or `password.rounding` corners) and the battery corner, in the
current Omarchy theme's colors and wallpaper (or another installed theme's,
with the `theme` setting).

```bash
./install.sh --preview     # look at it in a window first (no root, nothing installed)
./install.sh               # render, install (sudo), test-build, rebuild boot images
./install.sh --uninstall   # back to Omarchy's boot screen
```

## Settings

The boot screen has its own settings, separate from the lock screen's:

```
~/.config/omarchy/plugins/senysisu.plymouth/settings.lua
```

The first `./install.sh` (or `--preview`) creates it from this folder's
`settings.lua` and never overwrites it afterwards. It holds only what the boot
screen can show: `clock`, `date`, `battery` (`corner = false` hides it),
`password`, `background.blur` and `theme` (`nil` = the current theme, or an
installed theme's name to pin it, `"last-horizon,2"` for its 2nd wallpaper), with the same meaning and defaults as the
lock's. There's no `plugins/` manifest in that folder, so the Omarchy shell
ignores it.

The boot screen is a **snapshot**: saving `settings.lua` changes nothing.
Re-run `./install.sh` (optionally `--preview` first) after changing it, the
wallpaper or the Omarchy theme. `--uninstall` keeps the settings file.

## How it works

Plymouth runs inside the initramfs, before the disk is unlocked. Its script
engine can draw images but has no clock, no network and no way to pick a
weight of a variable font. So:

- **`render.sh`** reads the settings above (falling back to this folder's
  `settings.lua`, or `SETTINGS_FILE=…` to try another) and pre-renders everything with ImageMagick + Pango, matching
  how Qt draws the lock: every clock number `0`–`59` / `00`–`59` in
  Adwaita Sans Black (at Qt's default optical size), the date font as one
  image per character, the battery digits and icons, the field, placeholder,
  "Checking…" and "Authentication failed (n)" labels, and the wallpaper
  blurred to the lock's `background.blur` (half size; it is blurred anyway).
  Layout numbers follow `LockView.qml`'s formulas. Line heights come from Qt
  itself (`qml` probe) because Pango's differ by a pixel. It writes
  `senysisu.script` (constants + `senysisu.script.in`) and `clock.conf`.
  Positions were checked against a lock-screen screenshot to the pixel.
- **`initcpio/hooks/senysisu-plymouth`** runs right after the `plymouth` hook
  and sends `senysisu|<seconds since midnight>|<date>|<battery %>|<C/D>`
  through `plymouth display-message` whenever the minute or battery changes.
  The install hook adds coreutils `date`/`tr`, `/etc/localtime` (so it is
  local time, DST included) and `clock.conf` (the date format, translated
  from the lock's Qt format) — only while senysisu is the selected theme.
  It is killed by its cleanup hook before switch-root; from then on the
  script keeps the clock running from its 50 Hz refresh.
- **`senysisu.script.in`** lays it out and handles the prompt: dots centered
  and shrinking like the lock's, a blinking cursor, "Checking…" after Enter,
  the red border and "Authentication failed (n)" when the passphrase is asked
  again, and the field disappears once the root filesystem is mounted. Other
  messages (fsck, systemd) show where the lock has its weather line.
- **`mkinitcpio/zz-senysisu-plymouth.conf`** inserts the hook after
  `plymouth` in Omarchy's `HOOKS`, without editing Omarchy's own drop-ins.
- **`pacman/95-senysisu-plymouth.hook`** + `reapply`: every `omarchy-settings`
  install/upgrade resets `/etc/plymouth/plymouthd.conf` to `Theme=omarchy`;
  this selects senysisu again and rebuilds afterwards.

Nothing Omarchy ships is modified. `omarchy plymouth set …` still works and
switches back to Omarchy's theme (the clock hook then turns itself off);
re-run `./install.sh` to come back.

## What the lock has that the boot screen can't

- **Weather line and rain/snow effects** — no network before the disk opens.
- **Wi-Fi indicator** — NetworkManager isn't up; it would always say disconnected.
- **Show-password eye / Ctrl+R** — Plymouth only tells the theme how many
  characters were typed. Ctrl+R would become part of the passphrase, so the
  eye is left out rather than shown and broken (and no room is kept for it).
- **Weather color grading** of the wallpaper — no forecast, so it's neutral.
- **Esc** clears the field on the lock; at boot it toggles Plymouth's text view
  (press it again to come back).

## Safety

- `install.sh` builds a throwaway initramfs first and checks the hook, theme
  and clock files are in it; if anything fails it restores the previous
  theme and never touches the real boot images.
- The clock hook only starts a background loop; it can't block or delay the
  password prompt. If the theme ever misbehaves, **Esc** gives Plymouth's
  plain text prompt, and typing the passphrase blind + Enter always works.
- Limine's fallback and snapshot entries remain available.

## Testing without rebooting

`preview.sh` (`install.sh --preview`) runs `plymouthd` in a user namespace —
where it is "root" — with its X11 renderer on Xwayland, bind-mounting the
rendered theme over `/usr/share/plymouth/themes` for that namespace only.
It sends the current time like the hook would and asks for a password that is
never accepted. Hyprland's `send_shortcut` dispatcher can type into the window
by class (`wtype` doesn't work: Plymouth's X11 renderer reads its keys as Esc).

Needs: `magick` with Pango, `lua`, `jq`, `unshare`, and Plymouth's
`x11.so` renderer for the preview. Busybox-based initramfs only (Omarchy's
default `plymouth … encrypt` hooks), not systemd hooks.
