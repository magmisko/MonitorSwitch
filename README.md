# MonitorSwitch

A tiny native macOS menu bar app for switching inputs on an **ASUS ProArt PA329CV**. Pick USB-C, DisplayPort, HDMI 1 or HDMI 2 without reaching for the monitor's buttons.

[**Download MonitorSwitch for Apple Silicon**](https://github.com/magmisko/MonitorSwitch/releases/latest/download/MonitorSwitch.zip) · [Releases](https://github.com/magmisko/MonitorSwitch/releases)

The official release is signed with Developer ID and notarized by Apple.

## Requirements

- Apple Silicon Mac running macOS 14 or later.
- One ASUS ProArt PA329CV connected to the Mac through USB-C.
- DDC/CI enabled in the monitor's menu: **System Setup → OSD Setup → DDC/CI**.

This release supports this specific **model**, rather than a particular owner's monitor. Other monitor models and Intel Macs are not currently supported. With multiple PA329CV monitors connected, the app declines to send commands rather than choosing one arbitrarily.

## Use

1. Download the release ZIP, unzip it, and drag **MonitorSwitch.app** into **Applications**.
2. Open the app. It appears as a small display icon in the menu bar.
3. Choose **USB-C**, **DisplayPort**, **HDMI 1** or **HDMI 2**.

Choose **Port Names…** to add your own labels, such as **HDMI 2 (Switch)** or **USB-C (Mac)**. Leave a label empty to show just the port name. Labels are saved between launches and app updates.

| Shortcut | Input |
| --- | --- |
| Control + Option + Command + 1 | USB-C |
| Control + Option + Command + 2 | DisplayPort |
| Control + Option + Command + 3 | HDMI 1 |
| Control + Option + Command + 4 | HDMI 2 |

The menu checkmark shows the input reported by the monitor. It does not confirm a video signal: a console must be awake and its dock powered. MonitorSwitch does not send HDMI-CEC wake commands.

## Small by design

- Native Swift/AppKit menu and settings window.
- No network calls, telemetry, web runtime or additional runtime dependencies.
- Reads the monitor at launch, when opening the menu, and once after switching. No continuous polling.
- Uses macOS global hotkeys without Accessibility or Screen Recording permissions.
- Does not start automatically at login.

## Compatibility notes

USB-C → HDMI 2 → USB-C has been tested on a physical PA329CV with a Nintendo Switch, including confirmation of the picture. DisplayPort and HDMI 1 are available but have not yet been verified with active sources.

If switching back through USB-C fails, use the monitor's physical input button. DDC availability on an inactive input depends on the monitor and connection. This app uses Apple's private IOAVService transport, which may change in future macOS releases.

## Build from source

Requires Xcode or its Command Line Tools on an Apple Silicon Mac.

```sh
bash build.sh
```

The app is created at `dist/MonitorSwitch.app`. Pass another output directory as the first argument. Local builds are ad hoc signed. Both binaries are linked against the actual installed SDK, and the build verifies their `LC_BUILD_VERSION` values.

For your own signed and notarized distribution, use your own Developer ID identity and stored Keychain profile:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash build.sh
NOTARY_PROFILE="your-notary-profile" bash notarize.sh
```

No signing keys, Apple credentials or Keychain profiles are included.

## License and acknowledgements

[MIT License](LICENSE). DDC transport includes modified code from [waydabber/m1ddc](https://github.com/waydabber/m1ddc), also under the MIT License; its license is retained in `Vendor/m1ddc/LICENSE` and bundled in the app.

MonitorSwitch is an independent project and is not affiliated with ASUS, Apple or Nintendo.
