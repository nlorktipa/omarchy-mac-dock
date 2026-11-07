-- Frosted glass behind Mac Dock (omarchy-mac-dock).
--
-- Hyprland can only blur a layer surface while blur is on, and Omarchy ships
-- with it off. This turns it on, blurs the dock, and keeps ordinary windows
-- unblurred so nothing else changes -- unless Omarchy's "Glassy windows"
-- toggle is on, in which case windows keep the blur that toggle gives them.

local paths = require("default.hypr.paths")

local function exists(path)
  local file = io.open(path, "r")
  if file then file:close() return true end
  return false
end

local glassy_windows = exists(paths.state_home .. "/omarchy/toggles/hypr/window-glassy.lua")

-- Omarchy's Glassy toggles load after this file and set their own blur
-- values, so these only apply while those toggles are off.
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 8,
      passes = 3,
      new_optimizations = true,
      xray = false,
      contrast = 1.0,
      brightness = 0.9,
      noise = 0.01,
      vibrancy = 0.25,
      vibrancy_darkness = 0.25,
      popups = false,
      special = false,
    },
  },
})

if not glassy_windows then
  o.window({ class = ".*" }, { no_blur = true })
end

-- Pixels more see-through than ignore_alpha are left alone, so only the bar,
-- its menu and the labels get frosted, not the empty room around them.
hl.layer_rule({
  match = { namespace = "^omarchy-dock$" },
  blur = true,
  ignore_alpha = 0.1,
})
