## Summary

<!-- What changes, and why does it belong in OpenSynapse now? -->

## Verification

- [ ] `dotnet format` passes.
- [ ] Release build passes without warnings.
- [ ] Automated tests pass.
- [ ] Windows smoke test was run, or the untested Windows paths are listed below.
- [ ] Hardware writes were verified on owned or authorized hardware, or this PR makes no hardware-support claim.

Tested Windows/device/firmware combinations:

<!-- Use “Not tested” explicitly when applicable. -->

## Safety and scope

- [ ] Captured state and rollback behavior remain intact.
- [ ] New device access is gated by exact identity and capability.
- [ ] No firmware, EC, fan, power-limit, or MUX write is introduced without a reviewed safety design.
- [ ] Third-party code or protocol provenance is disclosed.
- [ ] Documentation and the device matrix match the actual maturity level.
