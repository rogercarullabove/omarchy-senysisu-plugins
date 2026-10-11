-- Boot screen settings for senysisu.plymouth (the disk-unlock prompt at boot).
--
-- SAVING THIS FILE DOES NOT CHANGE ANYTHING. The boot screen is pre-rendered
-- into images and baked into the boot image, so after editing, re-run:
--   @INSTALL@
-- (add --preview to look at it in a window first, without installing).
--
-- This file is separate from the lock screen's settings
-- (~/.config/omarchy/plugins/senysisu.lock/settings.lua); changing one never
-- affects the other. Any setting you delete (or set to nil) falls back to its
-- default. If this file has an error, install.sh uses the defaults and says so.
--
-- Sizes and positions given as fractions are relative to the screen height,
-- so 0.10 means 10% of the screen. Colors are "#rrggbb" hex, or nil to follow
-- the theme (see theme below).

return {
  -- Theme for the boot screen's colors and wallpaper. nil follows the current
  -- Omarchy theme (as of the last install); a theme's name pins it, e.g.
  -- theme = "nord". A pinned theme shows its first wallpaper (or the one
  -- picked now, if it is the current theme). Any installed theme works;
  -- list them with: omarchy theme list
  -- Omarchy's built-in themes:
  --   "catppuccin", "catppuccin-latte", "ethereal", "everforest",
  --   "flexoki-light", "gruvbox", "hackerman", "kanagawa", "last-horizon",
  --   "lumon", "lupine", "matte-black", "miasma", "nord", "osaka-jade",
  --   "retro-82", "ristretto", "rose-pine", "solitude", "tokyo-night",
  --   "vantablack", "white"
  theme = nil,

  clock = {
    font = "Adwaita Sans",
    size = 0.25,            -- digit height
    position = 0.16,        -- how far the clock sits above the screen center
    line_gap = -0.45,       -- gap between hours and minutes (fraction of digit size; negative pulls together)
    hours = 24,             -- 24 or 12 (no quotes)
    ampm = true,            -- 12-hour only: AM/PM to the right of the hours
    ampm_size = 0.2,        -- AM/PM height (fraction of digit size)
    hour_format = "HH",     -- "HH" = zero-padded (09), "H" = not padded (9)
    minute_format = "mm",   -- "mm" = zero-padded, "m" = not padded
    color = nil,
  },

  date = {
    enabled = true,
    format = "d MMM dddd",  -- Qt-style date format, e.g. "dddd, d MMMM" or "yyyy-MM-dd"
    gap = -0.16,            -- gap below the minutes (fraction of digit size)
    color = nil,
  },

  battery = {
    corner = "bottom_right", -- "top_left", "top_right", "bottom_left", "bottom_right", or false to hide
    show_percent = true,
    low = 15,               -- percentage at which the text turns red
  },

  password = {
    width = 340,            -- pixels
    height = 56,            -- pixels
    rounding = nil,         -- corner radius in pixels; 0 = rectangle, nil = pill
    gap = 0.13,             -- space between the date and the password field
    placeholder = "Enter Password",
  },

  background = {
    blur = 0.50,            -- 0.0 = sharp wallpaper, 1.0 = fully blurred
  },
}
