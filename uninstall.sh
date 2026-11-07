#!/bin/bash
# Removes Mac Dock and brings back Omarchy's stock dock.

set -euo pipefail

target="$HOME/.config/omarchy/plugins/macdock"
hypr_dir="$HOME/.config/hypr"
hypr_main="$hypr_dir/hyprland.lua"

# Disabling a plugin that replaced a built-in turns the built-in back on.
if omarchy plugin list --json | jq -e 'any(.[]; .id == "macdock")' >/dev/null; then
  omarchy plugin disable macdock >/dev/null || true
fi
rm -rf "$target"

# Belt and braces: make sure shell.json has the stock dock on and no trace of
# this plugin, whatever state the steps above left it in.
config="$HOME/.config/omarchy/shell.json"
if [[ -f $config ]]; then
  tmp=$(mktemp "$config.XXXXXX")
  jq '
    (if (.plugins | type) == "array" then .plugins |= map(select((if type == "object" then .id else . end) != "macdock")) else . end)
    | (if (.disabledPlugins | type) == "array" then .disabledPlugins |= map(select(. != "omarchy.dock")) else . end)
  ' "$config" >"$tmp" && mv "$tmp" "$config" || rm -f "$tmp"
fi
echo "Removed the plugin"

if [[ -f $hypr_dir/macdock.lua ]] || grep -qF 'require("hypr.macdock")' "$hypr_main" 2>/dev/null; then
  sed -i '/^-- Mac Dock: frosted glass behind the dock\.$/d; /^require("hypr\.macdock")$/d' "$hypr_main"
  rm -f "$hypr_dir/macdock.lua"
  hyprctl reload >/dev/null
  echo "Removed the blur rule from Hyprland"
fi

# The shell does not close the windows of a plugin it unloads (nor those left
# by earlier hot reloads), so they would stay on screen over the stock dock.
# A fresh shell starts with only the stock dock.
omarchy restart shell >/dev/null 2>&1
sleep 2
echo "Restarted the shell; the stock dock is back"
