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
git clone <this repo> ~/Projects/omarchy-mac-dock
cd ~/Projects/omarchy-mac-dock
./install.sh
```

Use `./install.sh --no-blur` to skip the Hyprland blur. The dock shows on
floating workspaces, like the built-in one.

## Uninstall

```bash
./uninstall.sh
```

This brings Omarchy's built-in dock back.

## Credits

Built on Omarchy's dock (MIT). Not affiliated with Apple, and uses none of
Apple's artwork.
