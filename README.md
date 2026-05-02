# HoverVolume

Small macOS menu bar app that lets you hover the speaker icon and scroll to change system volume.

## Why

macOS does not let third-party apps attach behavior to Apple's built-in Control Center or volume icon. HoverVolume adds its own compact menu bar speaker with a small animated volume bar under it.

## Features

- Scroll on hover to change system volume
- Thin animated level bar under the icon
- Native AppKit app in a single Swift source file
- Tuned for both precision trackpads and scroll-wheel mice
- Falls back to channel volume controls on devices that do not expose virtual main volume
- No dependencies

## Build

```bash
chmod +x build.sh
./build.sh
open HoverVolume.app
```

## Install

For local install:

```bash
chmod +x install.sh
./install.sh
```

This installs the app into `~/Applications/HoverVolume.app` and launches it.

## Release A Zip

```bash
chmod +x release.sh
./release.sh
```

This creates `dist/HoverVolume-macOS.zip` plus a `dist/SHA256SUMS.txt` checksum file.

## Share On GitHub

1. Push the repo to GitHub.
2. Create a release tag such as `v1.0.0`.
3. Let GitHub Actions build and attach the zip to the release.
4. Share the release URL.

People can then download the zip, drag `HoverVolume.app` into Applications, and run it.

## Gatekeeper

Because this project currently uses ad-hoc signing, some users may need to right-click the app and choose `Open` the first time.

For the smoothest public install experience, the real upgrade is:

- Apple Developer ID signing
- Apple notarization

## Files

- `main.swift`: app logic, UI, and CoreAudio integration
- `build.sh`: one-step build script
- `install.sh`: installs into `~/Applications`
- `release.sh`: builds a portable zip for sharing
- `Info.plist`: app bundle metadata

## Notes

- The built app bundle and local build cache are ignored by Git.
- Click the icon to see the current volume and quit the app.
