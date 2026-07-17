# Third-party references

OpenSynapse's initial Razer HID report implementation was developed with reference to:

- [ClickSync](https://github.com/1sm23/ClickSync), GNU GPL v2.0 (`GPL-2.0-only`), for the DeathAdder V3 Pro PID matrix, 90-byte report layout and command semantics.
- [OpenRazer](https://github.com/openrazer/openrazer), GPL-2.0-or-later, for independent confirmation of Razer report framing and checksums.

The reference checkouts under `ref/` are development-only and are excluded from this repository.

OpenSynapse as a whole is distributed under `GPL-2.0-only`. No dependency on the reference repositories is downloaded or loaded at runtime.
