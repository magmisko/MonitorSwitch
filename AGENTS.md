# MonitorSwitch

Small native macOS menu bar app. Swift/AppKit UI; a short-lived Objective-C helper performs DDC input reads and writes. No network use in the app, no continuous monitor polling, no additional runtime dependencies.

## Build and release

- `bash build.sh` writes `dist/MonitorSwitch.app`. An alternative output directory is the first argument.
- For distribution set `SIGNING_IDENTITY` to a Developer ID Application identity before building, then run `bash notarize.sh`. `NOTARY_PROFILE` selects an existing Keychain profile. Never put credentials in the repository.
- Both binaries must link against the current actual SDK. The build checks `LC_BUILD_VERSION`; do not remove this check.
- Keep the app native and small: standard menu items, standard AppKit controls, no web runtime.
- After changing settings UI verify the window actually opens. Add views to a common hierarchy before activating constraints. Set window position before showing it, and disable restoration when managing placement.

## Device and validation

- This release supports the ASUS PA329CV model (vendor AUS, product 12846) over USB-C on Apple Silicon. Never hardcode an individual monitor serial number. Fail without sending a command if multiple supported displays are connected.
- Input values are USB-C 19, DisplayPort 15, HDMI 1 17, HDMI 2 18. The model uses 19 rather than the common USB-C value 27.
- A DDC write must be repeated twice with a delay on this unit. Validate read replies and checksums. Serialize requests. Preserve bounds on subprocess duration.
- USB-C ↔ HDMI 2 was tested in both directions and the user confirmed the Nintendo image. Do not claim the signal is present merely from the input register. DisplayPort and HDMI 1 have no active-source validation yet.
- Do not change monitor brightness, power, firmware, or factory settings as part of an input-switch test. Restore the original input after any automated test.
- Port aliases live in UserDefaults under `sk.mk.InputSwitch`, are editable from “Port Names…”, and must survive updates.
- Vendored m1ddc transport remains under its MIT license. Keep the license in source and app resources.
