#!/bin/bash
# Copies plugin/ into ~/.config/omarchy/plugins/macdock every time a file in it
# is saved, so edits made in this repo hot-reload in the running shell.
# (A symlink would not: the shell's file watcher does not follow symlinks.)
# Run ./install.sh once first. Stop with Ctrl+C.

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
target="$HOME/.config/omarchy/plugins/macdock"
[[ -d $target && ! -L $target ]] || { echo "dev.sh: run ./install.sh first" >&2; exit 1; }
command -v inotifywait >/dev/null || { echo "dev.sh: needs inotifywait (inotify-tools)" >&2; exit 1; }

sync() { cp -a "$here/plugin/." "$target/"; echo "$(date +%T) synced"; }
sync
inotifywait -m -r -q -e close_write,create,delete,move --format '%w%f' "$here/plugin" | while read -r _; do
  sync
done
