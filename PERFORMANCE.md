# Resource-usage checks

The app should be idle when it has nothing to do. These checks observe the **real running AppKit process and run loop**, rather than calling its functions in a tight loop.

## Prepare

1. Run `bash scripts/build_usage_sampler.sh`. The sampler uses macOS libproc APIs, is not bundled in the app, and has no third-party dependencies.
2. Start the app normally and identify its PID with `pgrep -x InputSwitch`.
3. Place the tested window/menu on the built-in display. Set up the intended state before starting a measurement. Do not interact with other apps during an idle phase.
4. Ask the owner to close unrelated apps when practical; never stop their apps or builds automatically. Record any remaining background activity as a limitation.

When the shared MK Locks tool exists, the scripts register builds and acquire its exclusive measurement lock. The measurement waits for other registered builds and measurements. On other Macs, coordinate equivalent exclusive access manually.

The runner holds the display and machine awake with `caffeinate` only for the sampling process. It refuses to start with the lid closed or battery power below 20%.

## States to measure separately

- Port Names window visible and untouched.
- The same window hidden with Command-H.
- Window closed, leaving only the menu bar app.
- Controls submenu open with no interaction.
- A longer interaction/recovery run: use the real sliders and reopen the real menus, then leave the app idle to check memory recovery.

For each state, after the UI is prepared:

```sh
python3 scripts/measure_usage.py --pid PID --phase window-visible --seconds 15 --idle --output build/usage-visible.json
```

For an interaction/recovery phase, omit `--idle` and use a longer duration (for example 120 seconds). A phase label records the state the operator prepared; the script does not silently manipulate the UI or fabricate a state transition.

## What is recorded

- CPU time for the app and its reaped short-lived helpers, normalized to one logical CPU core.
- Physical memory footprint, with resident size recorded separately for comparison.
- Peak observed combined app/helper footprint and observed helper processes.
- Wakeups and a roughly one-second CPU/footprint trace, sampled from libproc every 50 ms.
- WindowServer CPU over the same interval. This is system-wide context and includes the effects of other open apps, so it is not attributed entirely to MonitorSwitch.

## Enforced budgets

- Idle mean app/helper CPU below 3% of one core.
- No three consecutive roughly one-second idle samples above 3%.
- App physical footprint below 128 MiB.
- End-of-phase footprint within 8 MiB of its initial baseline; assess the trace after interaction, allowing for normal AppKit caches.

`Tests/test_usage_limits.py` includes deliberate CPU, sustained-spike, unrecovered-memory and multi-gigabyte-footprint regressions to verify the checker fails. A higher workload during active dragging is not judged by the idle CPU limit.

Use `sample PID` or Instruments if a state exceeds its budget. A settled AppKit main thread should mostly be waiting for events; a timer-driven layout/redraw loop is a regression.

Results should be saved under `Tests/Results/` with the app version, machine, state preparation, durations and background-activity limitations. Never report a budget pass unless the corresponding real UI state was measured. Short checks do not establish all-day leak-free behavior.
