# Contributing to OpenSynapse

Thank you for helping build a smaller, transparent alternative to proprietary device software. By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- Use a public issue for reproducible bugs and device proposals.
- Use the private process in [SECURITY.md](SECURITY.md) for vulnerabilities.
- Keep changes focused. Do not add a framework or abstraction for a single implementation.
- Put temporary protocol references under ignored `ref/`, never in a pull request.

## Development setup

OpenSynapse targets Windows 11 and the .NET SDK pinned by [`global.json`](global.json).

```powershell
dotnet restore OpenSynapse.sln
dotnet format OpenSynapse.sln --verify-no-changes --no-restore
dotnet build OpenSynapse.sln --configuration Release --no-restore
dotnet test tests/OpenSynapse.Core.Tests/OpenSynapse.Core.Tests.csproj --configuration Release --no-build
```

Changes to Windows policies, IPC lifecycle, or HID transport also require the reversible smoke test documented in the [README](README.md). Run hardware writes only on hardware you own or are authorized to test.

## Device support evidence

A device is not considered supported because its product name resembles an existing model. Device pull requests must include:

- exact VID/PID and connection path;
- wired, receiver, or dongle role;
- firmware version when readable;
- protocol source or captured evidence that may legally be shared;
- read and write results for every claimed capability;
- rollback or failure behavior;
- the Windows version used for verification.

Unknown devices must remain read-only until their command path and safety boundary are verified. Never add firmware, EC, fan, power-limit, or MUX writes without a separately reviewed safety design and reproducible hardware evidence.

## Pull requests

1. Add the smallest check that fails without the change.
2. Implement the smallest complete change.
3. Run formatting, Release build, and tests.
4. Update the device matrix or architecture documentation only when behavior changes.
5. Complete the pull-request checklist and disclose which hardware paths were not tested.

Use Conventional Commits with a concise Chinese summary:

```text
feat(device): 增加 DeathAdder 状态读取
fix(agent): 修复恢复失败后错误退出
docs(readme): 补充设备验证状态
```

## Licensing

Unless stated otherwise, contributions are accepted under [`GPL-2.0-only`](LICENSE). By submitting a contribution, you confirm that you have the right to license it to the project under those terms and that third-party provenance is disclosed.
