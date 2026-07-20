[English](README.md) | [简体中文](README.zh-CN.md)

# OpenSynapse

[![Build](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml/badge.svg)](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml)

OpenSynapse is a local-first, open-source Windows control center for supported Razer hardware and system policies. Its goal is to replace opaque background software with explicit capabilities, inspectable state changes, and reliable rollback.

> [!WARNING]
> OpenSynapse is experimental, distributed as source only, and has no stable release. The current DeathAdder implementation still requires verification on target hardware. Keep Razer Synapse closed while testing device control.

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
| Windows policies | Adapter-aware Auto, Performance, and Quiet selection; power plans; refresh rate; Advanced Color/HDR; internal brightness; display scaling | Implemented, target-Windows validation pending |
| State restoration | Atomic captured state and verified power-plan rollback | Implemented, target-Windows validation pending |
| Desktop control | Non-elevated WPF panel and tray UI connected to a per-user elevated agent | Implemented, target-Windows validation pending |
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

OpenSynapse separates the ordinary desktop UI from privileged Windows operations:

```text
OpenSynapse.App  ── current-user named pipe ──>  OpenSynapse.Agent
       │                                             │
       └──────── shared request models ──────────────┤
                                                     ├─ Windows policy APIs / powercfg
                                                     └─ capability-gated Razer HID
```

The agent owns mode selection, captured state, rollback, and hardware writes. The UI never writes privileged system or HID state directly. See [Architecture](docs/ARCHITECTURE.md) and the shared [domain language](CONTEXT.md).

## Build and test

Requirements:

- Windows 11
- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0), matching [`global.json`](global.json)
- An elevated PowerShell terminal only for system-policy and hardware smoke tests

```powershell
dotnet restore OpenSynapse.sln
dotnet build OpenSynapse.sln --configuration Release --no-restore
dotnet test OpenSynapse.sln --configuration Release --no-build --no-restore
```

Start the elevated agent, then launch the UI from a normal terminal:

```powershell
dotnet run --project src/OpenSynapse.Agent -- serve
dotnet run --project src/OpenSynapse.App
```

On a disposable or fully understood Windows configuration, run the reversible elevated smoke test:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1

# Optional: re-write the mouse's currently reported values to verify HID transport.
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1 -TestMouseWrites
```

The script verifies Performance/Quiet application, named-pipe lifecycle, agent shutdown, power-plan rollback, and captured-state cleanup. The mouse option requires a readable DeathAdder V3 Pro and does not intentionally select new values.

## Safety and privacy

- Razer writes require an exact supported VID/PID and Consumer HID usage page.
- DPI and polling inputs are validated before packet construction.
- Responses must match the request transaction, command class, command ID, and checksum.
- Privileged IPC is restricted to the current Windows user.
- Captured system state is stored atomically under `%LOCALAPPDATA%\OpenSynapse`.
- Adapter classification invokes `nvidia-smi` with a read-only query and fails safe to Quiet when the power limit cannot be verified.
- The current implementation contains no telemetry, analytics, updater, account system, or runtime network client.

Please report security issues through the private process in [SECURITY.md](SECURITY.md), not a public issue.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md), the [roadmap](ROADMAP.md), and the [Code of Conduct](CODE_OF_CONDUCT.md). Hardware contributions must include reproducible identity and verification evidence; a matching product name alone is not enough to mark a device supported.

OpenSynapse began as a migration from the PowerPilot 2.0.0 prototype. Development-only prototype and protocol references belong under the ignored `ref/` directory and are never required to build the project.

## License and trademarks

OpenSynapse is licensed under [GNU GPL v2 only (`GPL-2.0-only`)](LICENSE). Third-party provenance is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

OpenSynapse is an independent community project and is not affiliated with, endorsed by, or sponsored by Razer Inc. Razer, Razer Synapse, and related product names are trademarks of their respective owners.
