# Add your monitor

Monitor support lives in [`monitors.json`](monitors.json). You can [request a profile](https://github.com/magmisko/MonitorSwitch/issues/new/choose) with hardware details, or submit a pull request that adds a tested profile. You do not need to change Swift or Objective-C code for an ordinary MCCS monitor.

## Discover the model without sharing a serial number

With MonitorSwitch installed, run:

```sh
"/Applications/MonitorSwitch.app/Contents/Resources/ddc-bridge" list
```

This prints external display names, manufacturer IDs and product IDs, without serial numbers. Include your Mac architecture, macOS version, connection type and any adapters. Enable DDC/CI in the monitor's own menu first.

## Add a profile

Copy an entry in `monitors.json`. Use a stable unique `id`, the manufacturer and decimal product ID returned by discovery, a human-readable name, and the monitor's actual input codes. The order of `ports` determines the numbered keyboard shortcuts (up to nine).

Start with `"controls": []`. Add `brightness` and/or `volume` only when their standard MCCS features (0x10 and 0x62) work on the model. Do not invent arbitrary control names; the helper deliberately supports only input selection and those two bounded controls.

Record exactly what was tested in `verification`. Distinguish a capability advertisement, a readable register, a successful write/readback, and a confirmed physical picture. A register read alone does not prove that a port has a signal or that a write will work.

Input mappings vary. For example, PA329CV uses 19 for USB-C, while PG42UQ uses 83 and 84 for HDMI 3 and HDMI 4. Do not assume standard assignments fit a different model.

## Validate and test

```sh
python3 scripts/validate_profiles.py
python3 -m unittest discover -s Tests
bash build.sh
```

The validator uses only Python's standard library. The app itself has no Python or third-party runtime dependency.

Use the built helper's `info` command for a read-only check. When testing an input change, plan a return path through the physical input button or a timed restore. Test one small brightness/volume change at a time and restore the original value. Do not test firmware, power-off, factory reset, EEPROM or unknown vendor commands.

The app currently supports one profiled external display at a time and Apple Silicon IOAVService transport. A model needing a different protocol or transport needs a code change and additional review, rather than just a JSON entry.

Please include the connection used, tested inputs, return-switch behavior, and any HDR or picture-mode restrictions in your pull request. Never include signing keys, account credentials or individual monitor serial numbers.
