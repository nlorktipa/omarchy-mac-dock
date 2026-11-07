#!/bin/bash
# Installs Mac Dock: the shell plugin, and the Hyprland rule that blurs it.
#
#   ./install.sh            install (or update) everything
#   ./install.sh --no-blur  install the plugin only, without touching Hyprland

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugins_dir="$HOME/.config/omarchy/plugins"
target="$plugins_dir/macdock"
hypr_dir="$HOME/.config/hypr"
hypr_main="$hypr_dir/hyprland.lua"
require_line='require("hypr.macdock")'

blur=1
for arg in "$@"; do
  case "$arg" in
    --no-blur) blur=0 ;;
    -h | --help) sed -n 2,6p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option $arg" >&2; exit 1 ;;
  esac
done

command -v omarchy >/dev/null || { echo "install.sh: this needs Omarchy (omarchy command not found)" >&2; exit 1; }
omarchy plugin list --json | jq -e 'any(.[]; .id == "omarchy.dock")' >/dev/null \
  || { echo "install.sh: this Omarchy has no built-in dock (omarchy.dock); update Omarchy first" >&2; exit 1; }

# 1. The plugin.
mkdir -p "$plugins_dir"
if [[ -L $target ]]; then
  rm "$target"
elif [[ -d $target ]]; then
  [[ $(jq -r '.id // ""' "$target/manifest.json" 2>/dev/null) == "macdock" ]] \
    || { echo "install.sh: $target exists and is not Mac Dock; move it away first" >&2; exit 1; }
  rm -rf "$target"
fi
stage=$(mktemp -d "$plugins_dir/.macdock.XXXXXX")
cp -a "$here/plugin/." "$stage/"
mv "$stage" "$target"
echo "Installed plugin to $target"

# 2. Blur behind the dock.
if (( blur )); then
  cp "$here/hypr/macdock.lua" "$hypr_dir/macdock.lua"
  if ! grep -qF "$require_line" "$hypr_main"; then
    printf '\n-- Mac Dock: frosted glass behind the dock.\n%s\n' "$require_line" >>"$hypr_main"
  fi
  hyprctl reload >/dev/null
  errors=$(hyprctl configerrors)
  if [[ -n ${errors//[[:space:]]/} && $errors != *"no errors"* ]]; then
    echo "Hyprland reported config errors:" >&2
    echo "$errors" >&2
  else
    echo "Enabled blur behind the dock ($hypr_dir/macdock.lua)"
  fi
fi

# 3. Swap the stock dock for this one.
omarchy-shell shell rescanPlugins >/dev/null
for (( i = 0; i < 40; i++ )); do
  omarchy plugin list --json | jq -e 'any(.[]; .id == "macdock")' >/dev/null && break
  sleep 0.05
done
omarchy plugin enable macdock >/dev/null 2>&1 || true
# Start the shell fresh so the swap leaves nothing of the old dock behind.
omarchy restart shell >/dev/null 2>&1
echo "Mac Dock is on. Like the stock dock, it shows on floating workspaces."
