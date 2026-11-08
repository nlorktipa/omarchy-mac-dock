# Mac Dock for Omarchy

A macOS-style dock for [Omarchy](https://omarchy.org/): a frosted glass bar with
magnifying icons, running-app dots and launch bounce. It replaces the look of
Omarchy's built-in dock, keeps all of its behaviour, and survives
`omarchy update`.

## Screenshots

![Mac Dock on an Omarchy desktop](screenshots/hero.png)

<p align="center"><img src="screenshots/dock.png" alt="Icons magnify under the pointer" width="720"></p>

## Install

```bash
git clone https://github.com/nlorktipa/omarchy-mac-dock
cd omarchy-mac-dock
./install.sh
```

Use `./install.sh --no-blur` to skip the Hyprland blur. The dock shows on
floating workspaces, like the built-in one.

To move the dock, drag its divider toward another screen edge and let go; a
preview shows where it will land.

<p align="center">
  <img src="screenshots/move-right.png" alt="Dragging the divider toward the right edge" width="49%">
  <img src="screenshots/move-top.png" alt="Dragging the divider toward the top edge" width="49%">
</p>

## Uninstall

```bash
./uninstall.sh
```

This brings Omarchy's built-in dock back.

## Credits

Built on Omarchy's dock (MIT). Not affiliated with Apple, and uses none of
Apple's artwork.
