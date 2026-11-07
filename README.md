# Mac Dock for Omarchy

A macOS-style dock for [Omarchy](https://omarchy.org/). It replaces the look of
Omarchy's built-in dock and keeps everything the built-in dock does.

- **Frosted glass bar**: a rounded, see-through bar with the wallpaper blurred
  behind it.
- **Magnification**: icons grow under the pointer and push their neighbours
  aside.
- **Running dots** under every app that has a window open.
- **App names** over the icon under the pointer.
- **Bounce** while an app is starting.
- **A separator** before the "all apps" tile at the end of the dock.

The dock still works the same way: pinned apps, drag to reorder, dragging an
app in from the app grid, right-click menus, auto-hide, and every position
(top, bottom, left, right). It follows your Omarchy theme's colors.

## Requirements

- Omarchy with the built-in dock (4.5 or newer). Check with
  `omarchy plugin list | grep omarchy.dock`.
- `jq` and `inotify-tools`, both installed with Omarchy.

## How it works

Omarchy's desktop shell (the bar, the dock, notifications) is a single
Quickshell process. Its parts are QML plugins. The built-in dock is the
`omarchy.dock` plugin. Its config in `~/.config/omarchy/shell.json` only sets
position, auto-hide and pinned apps, so a config file can't restyle it.

This repo is a shell plugin (`macdock`) that declares itself a replacement for
`omarchy.dock`. Enabling it switches the built-in dock off. Disabling it turns
the built-in dock back on. That is the same mechanism `omarchy plugin clone`
uses, so the plugin lives in your config and **survives `omarchy update`**.
Nothing under `/usr/share/omarchy` is changed.

```
plugin/
  manifest.json   plugin id "macdock", replaces omarchy.dock
  DockWindow.qml  the look: bar, magnification, dots, labels, bounce  <- the rewrite
  Dock.qml        the stock dock's logic (pins, windows, launching), unchanged
  DockModel.js    stock, unchanged
  AppGrid.qml     stock "all apps" grid, unchanged
  i18n/en.json    the plugin's own strings
hypr/macdock.lua  Hyprland rule that blurs what is behind the dock
install.sh        installs both pieces and switches the dock over
uninstall.sh      removes both and brings the built-in dock back
dev.sh            live-syncs edits from this repo while you work on it
```

Omarchy gives plugins in `~/.config/omarchy/plugins` less access than the
built-in dock gets: they don't receive the shell's config or its app library.
So `Dock.qml` reads `~/.config/omarchy/shell.json` and Omarchy's default
`shell.json` from disk itself, watching both for changes. It also creates its
own instance of Omarchy's `AppLibrary.qml`, which the "all apps" grid needs.
It won't save pins until it has read your config, so a slow or failed read
can't wipe your pinned apps. Its `omarchyPath` property must stay writable:
the shell assigns it when it creates the dock, and a failed assignment leaves
a dock instance the shell can never close.

The blur comes from Hyprland, not QML, because a shell surface can't blur what
is behind it. Omarchy ships with Hyprland blur turned off, so
`hypr/macdock.lua`:

1. turns blur on,
2. blurs only the dock's layer (`omarchy-dock`),
3. adds a `no_blur` rule to every window, so your windows look the same as
   before.

If Omarchy's **Glassy windows** toggle is on, step 3 is skipped and your
windows keep the blur that toggle gives them.

## Install

```bash
git clone <this repo> ~/Projects/omarchy-mac-dock
cd ~/Projects/omarchy-mac-dock
./install.sh
```

The installer:

1. copies `plugin/` to `~/.config/omarchy/plugins/macdock/`,
2. copies `hypr/macdock.lua` to `~/.config/hypr/macdock.lua` and adds
   `require("hypr.macdock")` to the end of `~/.config/hypr/hyprland.lua`, then
   reloads Hyprland and reports any config errors,
3. runs `omarchy plugin enable macdock`. This adds `macdock` to `plugins` and
   `omarchy.dock` to `disabledPlugins` in `~/.config/omarchy/shell.json`.

To install without the blur and leave Hyprland alone, run
`./install.sh --no-blur`.

To update, pull and run `./install.sh` again.

### Seeing it

As with the built-in dock, it only appears on **floating** workspaces. It
hides on tiled workspaces and behind fullscreen windows.

```bash
omarchy hyprland workspace layout toggle             # cycle this workspace: dwindle -> scrolling -> floating
omarchy hyprland workspace layout default floating   # make floating the default for every workspace
```

## Settings

The usual dock commands still work:

```bash
omarchy dock position left        # top | bottom | left | right
omarchy dock autohide toggle
omarchy dock pin org.gnome.Nautilus
omarchy dock unpin chromium
```

You can also right-click the apps tile for position and auto-hide, or
right-click an app to keep it in the dock, remove it, open a new window, or
quit it.

The look is set in a `mac` object inside `dock` in
`~/.config/omarchy/shell.json`. Every key is optional, and changes apply as
soon as you save:

```jsonc
"dock": {
  "position": "bottom",
  "pinned": ["..."],
  "mac": {
    "iconSize": 56,        // icon size in px (default: 48 x the shell's font scale)
    "magnification": 1.7,  // how big the icon under the pointer gets; 1 turns it off (max 3)
    "opacity": 0.45,       // bar opacity: 0 is fully see-through, 1 solid
    "labels": true,        // app name over the hovered icon
    "dots": true,          // dot under running apps
    "bounce": true         // bounce while an app starts
  }
}
```

The blur strength is in `~/.config/hypr/macdock.lua` (`size`, `passes`,
`brightness`, `vibrancy`). Hyprland reloads it when you save.

**macOS-style icons.** The dock doesn't use your GTK icon theme setting.
Omarchy's app library picks the first icon file it finds for each app, and it
looks in your own icon folders (`~/.local/share/icons`, `~/.icons`) before the
system ones. To get icons that look like macOS, install an icon theme into
your home folder. For example, WhiteSur's installer puts it in
`~/.local/share/icons` when run without sudo:

```bash
git clone --depth 1 https://github.com/vinceliuice/WhiteSur-icon-theme /tmp/whitesur
/tmp/whitesur/install.sh
omarchy restart shell
```

To undo this, delete the `WhiteSur*` folders from `~/.local/share/icons` and
restart the shell.

**Animations.** If you turn animations off with `omarchy toggle animations`,
the dock stops magnifying smoothly and bouncing. A starting app is dimmed
instead.

## Uninstall

```bash
./uninstall.sh
```

This disables `macdock`, which turns `omarchy.dock` back on. It then deletes
`~/.config/omarchy/plugins/macdock`, removes `~/.config/hypr/macdock.lua` and
its `require` line, and reloads Hyprland.

To switch back temporarily without uninstalling:

```bash
omarchy plugin disable macdock    # built-in dock again
omarchy plugin enable macdock     # Mac Dock again
```

## Developing

The shell reloads a plugin when a file under `~/.config/omarchy/plugins/`
changes. Its watcher does not follow symlinks, so symlinking this repo there
won't reload anything. Use `dev.sh` instead, which copies `plugin/` over every
time you save:

```bash
./install.sh      # once
./dev.sh          # leave running while you edit plugin/*.qml
```

Shell logs, including QML errors from the dock:

```bash
journalctl --user -f | grep -i -E 'macdock|qml'
```

If the dock disappears after an edit, there is a QML error. Check the log, fix
the error and save again. `omarchy plugin disable macdock` always brings the
built-in dock back.

### Keeping up with Omarchy

`Dock.qml`, `DockModel.js` and `AppGrid.qml` are copies of the stock files in
`/usr/share/omarchy/shell/plugins/dock/`, and only `DockWindow.qml` is
rewritten. When an Omarchy update changes the built-in dock, compare against
the stock files and carry over what changed:

```bash
diff -u /usr/share/omarchy/shell/plugins/dock/Dock.qml plugin/Dock.qml
diff -u /usr/share/omarchy/shell/plugins/dock/DockModel.js plugin/DockModel.js
diff -u /usr/share/omarchy/shell/plugins/dock/AppGrid.qml plugin/AppGrid.qml
diff -u /usr/share/omarchy/shell/plugins/dock/DockWindow.qml plugin/DockWindow.qml  # behaviour changes to port
```

## Credits

Built on Omarchy's dock (MIT). This project is not affiliated with Apple. It
imitates the style of the macOS dock and uses none of Apple's artwork.
