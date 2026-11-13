# Changelog

## 1.4

- Keep input selection directly in the main menu; put brightness and volume inside Controls ▸.
- Show slider percentages continuously while dragging and send the hardware update only on release. Do not write unchanged values or overwrite a drag with a delayed read.
- Detect ASUS PA329CV and PG42UQ using a shared monitor catalog; show the appropriate ports and numbered shortcuts.
- Keep custom port labels separate for each model, preserving older PA329CV labels.
- Add privacy-safe model discovery, a monitor request form, contribution instructions, profile validation and CI tests.
- Add a resource-usage test for the real running app, including short-lived helpers and WindowServer observations. Apply the shared MK build/measurement lock when available.
- Add a local secret-scanning commit hook and document the pinned third-party transport.

## 1.3

- Publish the PA329CV app under the MIT License, without a device serial-number restriction.
- Provide a Developer ID signed and Apple-notarized download.

## 1.2

- Translate the complete interface to English and use the name MonitorSwitch.

## 1.1

- Add editable, persistent port labels.

## 1.0

- Add direct PA329CV input switching and global keyboard shortcuts in a native menu bar app.
