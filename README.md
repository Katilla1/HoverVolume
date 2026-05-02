# HoverVolume

Small macOS menu bar app that lets you hover the speaker icon and scroll to change system volume.

## What It Does

HoverVolume adds its own compact speaker icon to the macOS menu bar. Move your pointer over it and scroll to raise or lower system volume. A thin animated bar under the icon shows the current level.

## Features

- Scroll on hover to change system volume
- Thin animated level bar under the icon
- Native AppKit app in a single Swift source file
- Tuned for both precision trackpads and scroll-wheel mice
- Falls back to channel volume controls on devices that do not expose virtual main volume
- No dependencies

## How To Use

1. Launch `HoverVolume.app`.
2. Find the speaker icon in the top-right menu bar.
3. Hover your mouse or trackpad pointer over the icon.
4. Scroll up to increase volume.
5. Scroll down to decrease volume.
6. Click the icon to see the current volume and quit the app.

If you do not see the icon, macOS may have placed it in the menu bar overflow area because there are too many visible menu bar items.

## Install

Download the latest `HoverVolume-macOS.zip` from the GitHub Releases page, unzip it, then drag `HoverVolume.app` into `Applications`.

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
