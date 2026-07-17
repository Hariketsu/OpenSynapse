# Security Policy

OpenSynapse controls privileged Windows settings and USB HID devices. Security reports are handled privately so users are not exposed before a fix is available.

## Supported versions

There is no stable release yet. Until the first release, only the latest revision of the default branch is considered for security fixes.

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private vulnerability reporting flow from the repository **Security** tab. If that flow is unavailable, contact [@Hariketsu](https://github.com/Hariketsu) through a private contact method published on the maintainer's GitHub profile.

Include, when applicable:

- the affected revision or release;
- Windows version and privilege level;
- device VID/PID, firmware, and connection type;
- reproducible steps and security impact;
- a minimal proof of concept;
- whether system state or hardware configuration was changed;
- logs with serial numbers and other personal data removed.

Reports concerning the elevated agent, current-user named pipe, state restoration, device identity checks, or HID command validation are in scope. General support requests and unsupported-device requests belong in the public issue templates.

The maintainers will coordinate disclosure after the impact is understood and a safe fix or mitigation is available. No response-time or bounty commitment is currently offered.
