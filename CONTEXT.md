# OpenSynapse

OpenSynapse controls supported Windows system and Razer device capabilities while preserving the state it replaces.

## Language

**Operating Mode**:
A named set of desired system states. OpenSynapse currently defines Performance and Quiet.
_Avoid_: Profile, preset

**Mode Selection**:
The user's instruction for choosing an Operating Mode. It may name a mode directly or delegate the choice to Auto.
_Avoid_: Mode, profile

**Auto**:
A Mode Selection that resolves to Performance on AC power and Quiet on battery or an unknown source.
_Avoid_: Auto mode

**Capability**:
A state that OpenSynapse can read or control on a supported system or device.
_Avoid_: Feature flag

**Supported Device**:
A hardware product whose identity, protocol and safety boundaries have been explicitly verified by OpenSynapse.
_Avoid_: Compatible device

**Captured State**:
The state observed before OpenSynapse first changes it and retained for restoration.
_Avoid_: Default state, backup

**Apply Result**:
The explicit outcome of applying a requested state: applied, unsupported or failed. A skipped write is never reported as applied.
_Avoid_: Success flag
