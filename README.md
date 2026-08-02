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
| Windows policies | Adapter-aware Auto, Hyper, Balance, Eco, and locked Experiment selection; power plans; refresh rate; Advanced Color/HDR; per-display brightness; display scaling; optional wake-device control | 2.5.0 installed and live-validated on the target system |
| State restoration | Atomic capture and read-back restoration of display modes, ICC association/hash, HDR, DRR, scaling, WMI/DDC brightness, legacy .NET rollback, PowerPilot takeover, and power plans | 2.5.0 non-destructive round trip validated on the target system |
| Research telemetry | Experiment environment reports; GPU/NPU availability, thermal/throttle, screen and policy evidence | Implemented; unavailable counters are reported explicitly rather than synthesized |
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
        └─ OpenSynapse.ps1 (WinForms UI, tray, automation, Experiment lock)
                └─ dynamically compiled OpenSynapse.Native.cs
                        ├─ display, battery, GPU/NPU and thermal telemetry
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

The package is written to `artifacts\publish\OpenSynapse` and `artifacts\OpenSynapse-2.5.0.zip`. The installer first asks the obsolete .NET Agent to restore its captured state when that binary is available; otherwise it restores the legacy power, display, brightness and wake state directly. If an installed PowerPilot runtime exists, its configuration and recovery state are archived, its own verified uninstaller restores Windows, and that configuration is promoted to OpenSynapse. The installer then removes the obsolete split runtime, copies the PowerShell implementation under `%ProgramFiles%\OpenSynapse`, registers one delayed highest-privilege per-user task, and creates an OpenSynapse Start menu shortcut. To uninstall and restore the captured state:

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

The tray runtime stores policy in `%LOCALAPPDATA%\OpenSynapse\config.json` and rollback state in `state.json`. It retains PowerPilot 2.4.1's Smart Auto, application rules, supply debounce, display policy, battery telemetry, health backoff, and reversible state model. Adapter classification treats only readings at or below 85 W as strong PD evidence and requires a 30-second startup warm-up plus three spaced samples before a downgrade; one reading at or above 130 W still confirms high-power AC immediately. GPU sampling adapts to 5 seconds on verified high-power AC, 10 seconds on portable power, and 20 seconds in manual Eco; only unique timestamped GPU samples advance dGPU activity detection. The main policy loop remains at 5 seconds on external power and expands to 10 seconds under battery activity or 15 seconds while battery load is light/manual Eco. A separate 30-second process CPU delta sampler can notify about sustained high-drain applications only when battery discharge is at least 14 W; it never closes a process and rate-limits alerts for 30 minutes.

Display policy keeps every active external display at the highest refresh rate exposed for its current resolution and color depth. The internal-panel `Auto` policy uses native 60–240 Hz dynamic refresh on battery, USB-C PD, and unverified AC, then returns to fixed 240 Hz after high-power AC is verified. Manual Eco 60 Hz and fixed 240 Hz remain available and return to `Auto` when external power is newly connected. When the internal panel is inactive, dynamic refresh is deferred without repeatedly producing monitor errors. If Windows accepts neither the dynamic request nor its verification, OpenSynapse falls back to internal Eco 60 Hz while keeping external displays at their maximum refresh rate.

Experiment is a persistent lock, not an Auto target. Entering it creates a dedicated verified power plan, fixes the requested refresh rate, captures every active display's mode, ICC profile association and SHA-256, HDR/Advanced Color, DRR, scale and available WMI/DDC brightness endpoints, then periodically detects and repairs drift. Leaving Experiment creates end/restored reports and restores the pre-experiment state. Each report is emitted as JSON, readable HTML and a SHA-256 sidecar under `%LOCALAPPDATA%\OpenSynapse\experiment-reports`.

The PowerPilot-compatible defaults enable Eco maintenance. Wake devices are matched by configured name fragments (initially MediaTek Wi-Fi, HID-compliant mouse, and USB4); tracked permissions are restored when leaving Eco, exiting, or uninstalling. Eco may also close configured high-drain helper processes and pause configured Armoury Crate/ASUS services. The compatible internal configuration value remains `Quiet`. Review these lists in `config.json` if those applications or devices must remain active.

## Safety and privacy

- Razer writes require an exact supported VID/PID and Consumer HID usage page.
- DPI and polling inputs are validated before packet construction.
- Responses must match the request transaction, command class, command ID, and checksum.
- The installed runtime runs as a single per-user highest-privilege scheduled task; no named-pipe IPC is required.
- Configuration and captured system state are stored separately and atomically under `%LOCALAPPDATA%\OpenSynapse`.
- Eco wake-device and service changes retain rollback state; configured process termination is limited to the local allowlists inherited from PowerPilot.
- Runtime events are written locally to bounded `OpenSynapse.log` and schema-6 `telemetry.jsonl` files. Schema 6 adds cached GPU/NPU availability, thermal/throttle and per-display screen evidence; battery hardware/display polling is relaxed to 60 seconds and an inactive dGPU is not woken for automatic Experiment reports. Process evidence is sampled at a separate 30-second cadence; only names, CPU deltas, working set, confidence and alert state are stored locally.
- Adapter classification invokes `nvidia-smi` with a read-only query. Ambiguous readings retain the last trusted AC class; an untrusted cold start remains `UnknownAC` and never promotes itself to high-power mode.
- The current implementation contains no telemetry, analytics, updater, account system, or runtime network client.

Please report security issues through the private process in [SECURITY.md](SECURITY.md), not a public issue.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md), the [roadmap](ROADMAP.md), and the [Code of Conduct](CODE_OF_CONDUCT.md). Hardware contributions must include reproducible identity and verification evidence; a matching product name alone is not enough to mark a device supported.

OpenSynapse began as a migration from the PowerPilot 2.0.0 prototype. Development-only prototype and protocol references belong under the ignored `ref/` directory and are never required to build the project.

## License and trademarks

OpenSynapse is licensed under [GNU GPL v2 only (`GPL-2.0-only`)](LICENSE). Third-party provenance is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

OpenSynapse is an independent community project and is not affiliated with, endorsed by, or sponsored by Razer Inc. Razer, Razer Synapse, and related product names are trademarks of their respective owners.
