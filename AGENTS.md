# MonitorSwitch

Small native macOS menu bar app. Swift/AppKit UI; a short-lived Objective-C helper performs DDC input reads and writes. No network use in the app, no continuous monitor polling, no additional runtime dependencies.

## Build and release

- `bash build.sh` writes `dist/MonitorSwitch.app`. An alternative output directory is the first argument.
- For distribution set `SIGNING_IDENTITY` to a Developer ID Application identity before building, then run `bash notarize.sh`. `NOTARY_PROFILE` selects an existing Keychain profile. Never put credentials in the repository.
- Both binaries must link against the current actual SDK. The build checks `LC_BUILD_VERSION`; do not remove this check.
- Keep the app native and small: standard menu items, standard AppKit controls, no web runtime.
- After changing settings UI verify the window actually opens. Add views to a common hierarchy before activating constraints. Set window position before showing it, and disable restoration when managing placement.

## Device and validation

- Profiles in monitors.json support ASUS PA329CV (AUS, 12846) and PG42UQ (AUS, 17120) on Apple Silicon. New ordinary MCCS models belong in that catalog, with verification evidence, rather than hardcoded UI or transport branches. Never hardcode an individual monitor serial number. Fail without sending a command if multiple supported displays are connected. Validate contributions with scripts/validate_profiles.py and the Tests suite.
- PA329CV inputs: USB-C 19, DisplayPort 15, HDMI 1 17, HDMI 2 18. PG42UQ inputs: DP 15, HDMI 1/2 17/18, HDMI 3/4 83/84 (confirmed in live capabilities). Never reuse a port mapping across models without evidence.
- A DDC write must be repeated twice with a delay on this unit. Validate read replies and checksums. Serialize requests. Preserve bounds on subprocess duration.
- USB-C ↔ HDMI 2 was tested in both directions and the user confirmed the Nintendo image. Do not claim the signal is present merely from the input register. DisplayPort and HDMI 1 have no active-source validation yet.
- Do not change brightness as part of an input-switch test. Dedicated brightness/volume tests may make one small bounded change, validate readback, and must restore the original value. PG42UQ brightness 50→49→50 and volume 19→18→19 passed. PA329CV brightness/volume still need live write validation. Never send power, firmware, factory-reset or unknown VCP writes. Restore the original input after any automated input test.
- Port aliases live in UserDefaults under sk.mk.InputSwitch. Port Names… stores them in portAliasesByModel keyed by stable profile id. Preserve legacy portAliases as the PA329CV fallback; never copy its labels onto another model.
- Inputs stay in the main menu. Brightness and volume stay in Controls ▸. Read those controls only when opening the submenu. Percent labels update continuously while dragging; commit one DDC write transaction only after mouse tracking ends. Do not add polling, debounce timers, per-drag hardware writes or extra runtime dependencies.
- Vendored m1ddc transport remains under its MIT license. Keep the license in source and app resources.
