# MonitorSwitch

A small native macOS menu bar app for switching monitor inputs. Inputs stay one click away in the main menu. **Controls ▸** keeps brightness and volume out of the way until you need them.

[**Download for Apple Silicon**](https://github.com/magmisko/MonitorSwitch/releases/latest/download/MonitorSwitch.zip) · [Releases](https://github.com/magmisko/MonitorSwitch/releases) · [Add your monitor](CONTRIBUTING.md)

The official release is signed with Developer ID and notarized by Apple. Requires an Apple Silicon Mac running macOS 14 or later and DDC/CI enabled on the monitor. One supported external monitor at a time.

## Supported models

| Monitor | Main-menu inputs | Connection tested | Verification |
| --- | --- | --- | --- |
| ASUS ProArt PA329CV | USB-C, DisplayPort, HDMI 1, HDMI 2 | USB-C | USB-C ↔ HDMI 2 switching and the physical picture confirmed. Brightness/volume need live write validation on this model. |
| ASUS ROG Swift OLED PG42UQ | DisplayPort, HDMI 1, HDMI 2, HDMI 3, HDMI 4 | USB-C to DisplayPort | All five input values confirmed in the capabilities reply; active DisplayPort read confirmed. Brightness/volume writes and readbacks verified, with original settings restored. Active HDMI signals have not been checked. |

PG42UQ HDMI 3/4 names follow the [firmware mapping](https://github.com/schlarpc/asus-pg42uq-firmware-re/blob/main/ddc_surface.md#22-vcp-60--input-source-c); the capabilities reply confirms values 83 and 84 but not the printed connector labels. Report any mismatch in an issue.

Other models can be added through a profile contribution. Intel Macs and monitors requiring another transport are not currently supported.

## Use

1. Download the ZIP, unzip it, and drag **MonitorSwitch.app** into **Applications**.
2. Open the app and click its small display icon in the menu bar.
3. Choose an input directly, or open **Controls ▸** for brightness and volume.

Percentages update while you drag a slider. The hardware update is sent once when you release it, followed by a readback. Releasing at the original value sends no setting command. The helper repeats the one setting request twice for reliability on these displays; it does not send per-drag writes. Controls the monitor does not answer are disabled. HDR or picture modes may lock brightness; the app reports an unapplied setting instead of changing the picture mode itself.

Choose **Port Names…** to add labels such as **HDMI 2 (Switch)**. Labels are saved separately for each monitor model. Existing PA329CV labels are preserved when upgrading.

Global shortcuts are **Control + Option + Command + 1–9**, in the displayed port order. PA329CV keeps its original four assignments: USB-C, DisplayPort, HDMI 1, HDMI 2. PG42UQ uses DisplayPort followed by HDMI 1–4.

The checkmark shows the input reported by the monitor, rather than confirming an active video signal. A console must be awake and its dock powered. MonitorSwitch does not send HDMI-CEC wake commands. If switching back fails, use the monitor's physical input button.

## Small by design

- Native Swift/AppKit controls; no web runtime or extra runtime dependencies.
- No network requests, telemetry or continuous polling.
- Reads the input at launch, when opening the main menu and after switching.
- Reads brightness and volume only when opening Controls or verifying a requested change.
- No Accessibility or Screen Recording permission needed for the global shortcuts.
- Does not start automatically at login.

The app uses Apple's private IOAVService transport, which may change in future macOS releases. Connections, adapters and inactive-input DDC availability affect compatibility.

## Help add monitors

Use **About MonitorSwitch… → Monitor Support…**, or [open a monitor support request](https://github.com/magmisko/MonitorSwitch/issues/new/choose). The issue form asks for the model, connection and verified behavior, without serial numbers.

Profiles live in [`monitors.json`](monitors.json). [CONTRIBUTING.md](CONTRIBUTING.md) explains privacy-safe discovery, adding a JSON profile and testing it. Pull requests run automatic profile validation. A model using ordinary MCCS input/brightness/volume codes usually needs only a profile entry, rather than a UI or transport code change.

## Build from source

Requires Xcode or its Command Line Tools and Python 3 for build-time profile validation. Python is not used by the app.

```sh
python3 -m unittest discover -s Tests
bash build.sh
```

The app is created at `dist/MonitorSwitch.app`. Pass another output directory as the first argument. Local builds are ad hoc signed. Both binaries link against the actual installed SDK; the build verifies their `LC_BUILD_VERSION` values.

For your own signed and notarized distribution, use your own Developer ID identity and stored Keychain profile:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash build.sh
NOTARY_PROFILE="your-notary-profile" bash notarize.sh
```

No signing keys, Apple credentials or Keychain profiles are included.

## License and acknowledgements

[MIT License](LICENSE). DDC transport includes modified code from [waydabber/m1ddc](https://github.com/waydabber/m1ddc), also under the MIT License; its license is retained in `Vendor/m1ddc/LICENSE` and bundled in the app.

MonitorSwitch is independent and not affiliated with ASUS, Apple or Nintendo.
