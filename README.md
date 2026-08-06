# OpenSynapse

[![Build](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml/badge.svg)](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml) [简体中文](README.zh-CN.md)

OpenSynapse is a local-first Windows control center for power, display, automation, and selected Razer HID capabilities. It applies explicit policies, records inspectable local state, and keeps a rollback path for the system state it changes.

> **Version 0.2.0 is the first public release target.** It is intended to be a narrowly supported preview, not a universal gaming-laptop control utility.

## Is this for you?

OpenSynapse currently targets Windows 11 systems where power and display behavior needs to be observable and reversible. The primary validation environment is a Razer Blade 16 (2025), model `RZ09-0528`.

| Area | Available in 0.2.0 | Evidence and boundary |
| --- | --- | --- |
| Power policies | Auto, Hyper, Balance, and Quiet; power-plan and battery-aware automation | Validated on the target system; policy values are hardware and firmware dependent |
| Smart Auto | Application, fullscreen, CPU/GPU load, supply classification, and hysteresis signals | Falls back conservatively when hardware evidence is unavailable |
| Display policies | Refresh rate, HDR/Advanced Color, internal brightness, and scaling | Validated on the target system; external-display behavior is intentionally limited |
| Recovery | Captured state, atomic local files, and uninstall/exit restoration | Intended to restore tracked state; review the safety notes before installation |
| Razer mouse | DeathAdder V3 Pro discovery, status, DPI, and standard-receiver polling control | Experimental until a connected target device completes read/write verification |

### Not supported

Firmware updates, fan curves, CPU/GPU power limits, MUX switching, undocumented embedded-controller writes, kernel drivers, cloud accounts, automatic updates, and runtime network services are outside the current scope.

## Screenshots

These screenshots show a target-machine session and its instantaneous telemetry. They illustrate the UI; their power, battery, display, and GPU values are not universal defaults.

### Dashboard

![OpenSynapse dashboard](docs/screenshots/dashboard-smart-automation.png)

### Game Mode

![OpenSynapse Game Mode](docs/screenshots/game-mode-smart-auto.png)

### Settings

![OpenSynapse settings](docs/screenshots/settings-power-display-and-razer.png)

The settings screenshot shows the safe state when no supported DeathAdder V3 Pro is connected. HID writes remain disabled until an exact allowlisted device is detected.

### Diagnostics

![OpenSynapse diagnostics](docs/screenshots/diagnostics-live-telemetry.png)

### About and recovery

![OpenSynapse about page](docs/screenshots/about-version-and-safety.png)

Closing the window hides the control panel. **Exit and restore** is the operation that stops the tray runtime and restores tracked state.

## Quick start

### Requirements

- Windows 11;
- Windows PowerShell 5.1;
- administrator approval for installation and policy changes;
- a disposable or fully understood system for preview testing;
- Razer Synapse closed while testing Razer HID control.

### Preview package

The first public package will be attached to the GitHub Release for `0.2.0` together with release notes and a SHA-256 checksum. Until that Release exists, the repository is source-first and does not provide a supported download path.

### Build from source

From a Windows PowerShell 5.1 prompt:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-InstallerDefinitions.ps1
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1
powershell -ExecutionPolicy Bypass -File scripts\Publish-OpenSynapse.ps1
```

The package is generated under `artifacts\publish\OpenSynapse` and `artifacts\OpenSynapse-0.2.0.zip`.

### Install and restore

From an extracted package:

```powershell
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode Install
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode Status
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode SelfTest
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode Uninstall
```

Installation creates a delayed, highest-privilege per-user scheduled task and stores local configuration and rollback state under `%LOCALAPPDATA%\OpenSynapse`. Review the generated state before using the preview on a machine you cannot restore.

For a full reversible administrator check on a disposable system:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1 -AdminRelease
```

The optional mouse-write check requires a connected, readable DeathAdder V3 Pro and writes its currently reported values back without choosing new values:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1 -TestMouseWrites
```

## Safety and privacy

- Runtime operation is local-only; there is no account, cloud service, analytics client, updater, or required network connection.
- The installed runtime is one elevated PowerShell 5.1/WinForms tray process; it does not install a kernel driver.
- Configuration and captured state are separate atomic files under `%LOCALAPPDATA%\OpenSynapse`.
- Razer writes require VID `1532`, an exact supported PID, and the Consumer HID usage page. DPI and polling values are validated before packet construction, and responses are checked against the request and checksum.
- Quiet wake-device, service, and helper-process actions use local allowlists and retain rollback state. Review those lists before installation.
- `nvidia-smi` is used only for read-only adapter evidence. Missing or ambiguous evidence fails safe instead of promoting a performance policy.
- A matching product name does not make a device supported. The DeathAdder V3 Pro PID `02C6` found in the target laptop is an internal keyboard, not a supported mouse interface.

## Known limitations

- Hyper reaches its intended maximum-output policy only after verified high-power AC evidence. USB-C PD, battery, and ambiguous AC remain input-power limited.
- External-display refresh behavior is deliberately constrained; the project does not claim general external-monitor refresh control.
- DeathAdder V3 Pro hardware read/write verification is still pending for the allowlisted wired and receiver PIDs.
- Installation and rollback evidence currently covers the named target environment, not every Windows 11 laptop, GPU, monitor, or firmware combination.
- A display link or monitor-controller failure cannot always be repaired by user-mode software. The runtime detects missing or unstable evidence and avoids force-writing an unsafe topology.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Roadmap and maturity gates](ROADMAP.md)
- [Changelog](src/OpenSynapse.PowerShell/CHANGELOG.md)
- [Contribution guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Contributing

Hardware contributions must include reproducible device identity and verification evidence. A matching product name alone is not sufficient to mark a device supported. Start with the contribution guide and the roadmap before changing a capability boundary.

## License and trademarks

OpenSynapse is licensed under [GNU GPL v2 only (`GPL-2.0-only`)](LICENSE). It is an independent community project and is not affiliated with, endorsed by, or sponsored by Razer Inc. Razer, Razer Synapse, and related product names are trademarks of their respective owners.
