# OpenSynapse roadmap

The roadmap describes validation gates, not delivery dates. A capability moves forward only when current evidence supports the stronger claim.

## Maturity labels

- **Planned:** accepted direction with no complete implementation.
- **Experimental:** implemented and guarded, but missing target-system or hardware evidence.
- **Verified:** reproduced on a named Windows/device/firmware combination with rollback checked.
- **Supported:** verified combinations are documented and regressions are covered by repeatable checks.

## Foundation — M0 to M3

- [x] .NET solution, Windows CI, tests, license, and project documentation.
- [x] Non-elevated WPF control panel and per-user elevated agent.
- [x] Adapter-aware Auto, Performance, Balanced, and Quiet policy selection.
- [x] Captured state and power-plan rollback.
- [x] DeathAdder V3 Pro discovery, status, DPI, and standard polling commands.
- [ ] Run the reversible Windows policy smoke test on the target machine.
- [ ] Run read/write verification on each claimed DeathAdder V3 Pro PID and connection role.
- [ ] Publish the first compatibility record.

## First public alpha

- Windows installation, elevation, startup, single-instance, and uninstall lifecycle (implemented; live validation pending).
- Verified removal of OpenSynapse-managed power plans during uninstall (implemented; live validation pending).
- Versioned configuration/state schemas, bounded diagnostic logs, and read-only self-test (implemented; target-Windows validation ongoing).
- A documented elevated-agent threat model.
- Repeatable Windows integration tests and a maintained compatibility matrix.
- Signed or checksummed preview artifacts with a changelog.

## After the first verified device

- Promote only verified DeathAdder combinations from Experimental to Supported.
- Add devices from evidence-backed requests, not name-based guesses.
- Extract a shared device-driver boundary when a second implementation proves the common shape.
- Add higher polling modes only with the correct dongle identity, protocol, and hardware verification.
- Localize the desktop application after its workflows stabilize.

## Non-goals for the current roadmap

- cloud accounts, telemetry, or required network services;
- firmware flashing;
- undocumented embedded-controller, fan, CPU/GPU power-limit, or MUX writes;
- a plugin framework before multiple maintained drivers require one.
