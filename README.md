[English](README.md) | [简体中文](README.zh-CN.md)

# OpenSynapse

[![Build](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml/badge.svg)](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml)

OpenSynapse is a local-first, open-source Windows control center for supported Razer hardware and system policies. Its goal is to replace opaque background software with explicit capabilities, inspectable state changes, and reliable rollback.

> [!WARNING]
> The power/display runtime is now based directly on the field-tested PowerPilot 2.4.1 implementation. DeathAdder writes remain hardware-gated and still require verification on a connected target device. Keep Razer Synapse closed while testing device control.

## Principles

- **Local-first:** no account, cloud service, telemetry, or runtime network access.
- **Explicit:** every supported capability has a known identity, protocol, and safety boundary.
- **Reversible:** system state is captured before OpenSynapse changes it and retained until confirmed restoration.
- **Capability-gated:** unknown devices and unsupported commands are not treated as compatible.
- **Small:** Windows and .NET facilities are preferred over resident services and dependency-heavy frameworks.

## Project status

OpenSynapse currently implements the M0–M3 development slice. Implementation does not mean hardware verification; see the [roadmap](ROADMAP.md) for the gates between experimental and supported status.

| Area | Current capability | Maturity |
| --- | --- | --- |
| Windows policies | Adapter-aware Auto, Hyper, Balance, and Quiet selection; power plans; refresh rate; Advanced Color/HDR; internal brightness; display scaling; optional wake-device control | Live installation validated on the target RZ09-0528 |
| State restoration | Atomic captured state, legacy .NET rollback, PowerPilot takeover, and verified power-plan rollback | Migration validated on the target system |
| Desktop control | Single elevated PowerShell 5.1/WinForms tray process, installed as a delayed highest-privilege per-user task | Installed and live-validated |
| Razer mouse | Discovery, status, DPI, and standard-receiver polling control | Experimental |

### Device matrix

| Device | VID:PID | Connection | Implemented | Verified |
| --- | --- | --- | --- | --- |
| Razer DeathAdder V3 Pro | `1532:00B6` | Wired | Status, DPI, 125/500/1000 Hz | Pending |
| Razer DeathAdder V3 Pro | `1532:00B7` | Wireless receiver | Status, DPI, 125/500/1000 Hz | Pending |
| Razer DeathAdder V3 Pro (alternate IDs) | `1532:00C2`, `1532:00C3` | Wired / wireless | Status, DPI, 125/500/1000 Hz | Pending |
| Razer HyperPolling Wireless Dongle | — | Wireless | Not implemented | — |

“Pending” means the protocol path exists and is tested at the packet level, but the project does not yet claim hardware support. Firmware updates, fan curves, CPU/GPU power limits, MUX control, and undocumented EC writes are outside the current scope.

## Architecture

The release runtime intentionally follows PowerPilot 2.4.1's proven single-process model:

```text
OpenSynapse scheduled task (highest privileges, STA)
        │
        └─ OpenSynapse.ps1 (WinForms UI, tray, automation)
                └─ dynamically compiled OpenSynapse.Native.cs
                        ├─ display, battery and GPU telemetry
                        ├─ Windows policy APIs / powercfg
                        └─ capability-gated DeathAdder HID reports
```

This removes the WPF-to-Agent startup and named-pipe failure mode that made the previous migration appear online while its control backend was unavailable. See [Architecture](docs/ARCHITECTURE.md).

## Build and test

Requirements:

- Windows 11
- Windows PowerShell 5.1
- Administrator approval for installation and policy changes

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-InstallerDefinitions.ps1
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1
```

The retained .NET solution contains protocol/unit-test code from the previous implementation and can still be tested separately, but it is no longer the published desktop runtime.

### Publish and install

Create the renamed PowerPilot-compatible package, then install it:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Publish-OpenSynapse.ps1
powershell -ExecutionPolicy Bypass -File scripts\Install-OpenSynapse.ps1
```

The package is written to `artifacts\publish\OpenSynapse` and `artifacts\OpenSynapse-2.4.1.zip`. The installer first asks the obsolete .NET Agent to restore its captured state when that binary is available; otherwise it restores the legacy power, display, brightness and wake state directly. If an installed PowerPilot runtime exists, its configuration and recovery state are archived, its own verified uninstaller restores Windows, and that configuration is promoted to OpenSynapse. The installer then removes the obsolete split runtime, copies the PowerShell implementation under `%ProgramFiles%\OpenSynapse`, registers one delayed highest-privilege per-user task, and creates an OpenSynapse Start menu shortcut. To uninstall and restore the captured state:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Uninstall-OpenSynapse.ps1
```

On a disposable or fully understood Windows configuration, run the full reversible administrator suite:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1 -AdminRelease

# Optional: re-write the mouse's currently reported values to verify HID transport.
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1 -TestMouseWrites
```

The mouse option requires a readable DeathAdder V3 Pro and writes its currently reported values back without intentionally choosing new settings.

## Configuration

The tray runtime stores policy in `%LOCALAPPDATA%\OpenSynapse\config.json` and rollback state in `state.json`. It retains PowerPilot 2.4.1's Smart Auto, application rules, supply debounce, display policy, battery telemetry, health backoff, and reversible state model.

The PowerPilot-compatible defaults enable Quiet maintenance. Wake devices are matched by configured name fragments (initially MediaTek Wi-Fi, HID-compliant mouse, and USB4); tracked permissions are restored when leaving Quiet, exiting, or uninstalling. Quiet may also close configured high-drain helper processes and pause configured Armoury Crate/ASUS services. Review these lists in `config.json` if those applications or devices must remain active.

## Safety and privacy

- Razer writes require an exact supported VID/PID and Consumer HID usage page.
- DPI and polling inputs are validated before packet construction.
- Responses must match the request transaction, command class, command ID, and checksum.
- The installed runtime runs as a single per-user highest-privilege scheduled task; no named-pipe IPC is required.
- Configuration and captured system state are stored separately and atomically under `%LOCALAPPDATA%\OpenSynapse`.
- Quiet wake-device and service changes retain rollback state; configured process termination is limited to the local allowlists inherited from PowerPilot.
- Runtime events are written locally to bounded `OpenSynapse.log` and `telemetry.jsonl` files.
- Adapter classification invokes `nvidia-smi` with a read-only query and fails safe to Quiet when the power limit cannot be verified.
- The current implementation contains no telemetry, analytics, updater, account system, or runtime network client.

Please report security issues through the private process in [SECURITY.md](SECURITY.md), not a public issue.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md), the [roadmap](ROADMAP.md), and the [Code of Conduct](CODE_OF_CONDUCT.md). Hardware contributions must include reproducible identity and verification evidence; a matching product name alone is not enough to mark a device supported.

OpenSynapse began as a migration from the PowerPilot 2.0.0 prototype. Development-only prototype and protocol references belong under the ignored `ref/` directory and are never required to build the project.

## License and trademarks

OpenSynapse is licensed under [GNU GPL v2 only (`GPL-2.0-only`)](LICENSE). Third-party provenance is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

OpenSynapse is an independent community project and is not affiliated with, endorsed by, or sponsored by Razer Inc. Razer, Razer Synapse, and related product names are trademarks of their respective owners.
