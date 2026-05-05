# HoverVolume

Small macOS menu bar app that lets you hover the speaker icon and scroll to change system volume, then click for quick mute and media controls.

## What It Does

HoverVolume adds its own compact speaker icon to the macOS menu bar. Move your pointer over it and scroll to raise or lower system volume. Click the icon to open a small control popover with mute, play or pause, previous, and next buttons. A thin animated bar under the icon shows the current level.

## Features

- Scroll on hover to change system volume
- Supports both vertical and horizontal trackpad scrolling
- Click the icon for mute or unmute and media transport controls
- Manual `Check for Updates` button that opens the latest GitHub release
- Keep scrolling to change volume even while the control popover is open
- Thin animated level bar under the icon
- Native AppKit app in a single Swift source file
- Tuned for both precision trackpads and scroll-wheel mice
- Falls back to channel volume controls on devices that do not expose virtual main volume
- No dependencies

## How To Use

1. Launch `HoverVolume.app`.
2. Find the speaker icon in the top-right menu bar.
3. Hover your mouse or trackpad pointer over the icon.
4. Scroll up, down, left, or right to change volume.
5. Click the icon to open the control popover.
6. Use the mute button, media buttons, or `Check for Updates`, or keep scrolling while the popover is open.
7. Use the quit button in the popover when you want to exit the app.

If you do not see the icon, macOS may have placed it in the menu bar overflow area because there are too many visible menu bar items.

## Install

Download the latest `HoverVolume-macOS.dmg` from the GitHub Releases page, open it, then drag `HoverVolume.app` into `Applications`.

If you prefer, you can also download `HoverVolume-macOS.zip`, unzip it, and move the app manually.

Use the Releases page here:

`https://github.com/Katilla1/HoverVolume/releases/latest`

Do not use the green `Code` button if you want the app itself. That download is only the source code.

On first launch, macOS may ask you to confirm that you want to open it.

## Compatibility

- macOS 13 or later
- MacBook trackpads
- Standard scroll-wheel mice
- Built-in speakers, many Bluetooth outputs, and many external audio devices

## Build From Source

```bash
chmod +x build.sh
./build.sh
open HoverVolume.app
```

Run the lightweight logic tests with:

```bash
chmod +x test.sh
./test.sh
```

Or install it into `~/Applications` with:

```bash
chmod +x install.sh
./install.sh
```

## Gatekeeper

Because this project currently uses ad-hoc signing, some users may need to right-click the app and choose `Open` the first time.

## Notes

- HoverVolume uses its own menu bar icon. It cannot attach this behavior to Apple's built-in Control Center volume control.
- The built app bundle and local build cache are ignored by Git.
