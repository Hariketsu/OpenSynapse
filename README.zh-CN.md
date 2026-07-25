[English](README.md) | [简体中文](README.zh-CN.md)

# OpenSynapse

[![构建](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml/badge.svg)](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml)

OpenSynapse 是一个本地优先的开源 Windows 控制中心，用于管理受支持的 Razer 硬件和系统策略。项目的目标是用能力明确、状态变化可检查、可靠回滚的开放实现，替代不透明的常驻软件。

> [!WARNING]
> OpenSynapse 仍处于实验阶段，目前只提供源码，没有稳定版本。现有 DeathAdder 实现仍需在目标硬件上完成验证。测试设备控制时，请关闭 Razer Synapse。

## 项目原则

- **本地优先：** 不需要账户、云服务或遥测，运行时不访问网络。
- **能力明确：** 每项受支持能力都有明确的设备身份、协议和安全边界。
- **可恢复：** OpenSynapse 修改系统前会捕获原始状态，并保留到确认恢复成功为止。
- **能力门控：** 未知设备和未支持命令不会被模糊地视为“兼容”。
- **保持精简：** 优先使用 Windows 和 .NET 原生能力，避免臃肿的常驻服务和依赖框架。

## 当前状态

OpenSynapse 已实现 M0–M3 开发切片。完成代码实现不等于通过硬件验证；实验能力升级为正式支持所需的门槛见[路线图](ROADMAP.md)。

| 领域 | 当前能力 | 成熟度 |
| --- | --- | --- |
| Windows 策略 | Smart Auto、Hyper、Balance、Quiet；电源方案、刷新率、Advanced Color/HDR、内屏亮度和显示缩放 | 已实现，等待目标 Windows 验证 |
| Smart Auto | 供电、CPU、前台/全屏应用、应用规则、迟滞、临时模式 | 已实现；GPU 负载与独显泄漏诊断待补齐 |
| 状态恢复 | 原始状态原子保存与电源方案恢复验证 | 已实现，等待目标 Windows 验证 |
| 桌面控制 | 五页深色 WPF 面板和托盘 UI，通过当前用户专用管道连接提权 Agent | 已实现，等待目标 Windows 验证 |
| Razer 鼠标 | 设备发现、状态、DPI 和标准接收器轮询率控制 | 实验性 |

### 设备矩阵

| 设备 | VID:PID | 连接方式 | 已实现 | 已验证 |
| --- | --- | --- | --- | --- |
| Razer DeathAdder V3 Pro | `1532:00B6` | 有线 | 状态、DPI、125/500/1000 Hz | 待验证 |
| Razer DeathAdder V3 Pro | `1532:00B7` | 无线接收器 | 状态、DPI、125/500/1000 Hz | 待验证 |
| Razer DeathAdder V3 Pro（备用 ID） | `1532:00C2`、`1532:00C3` | 有线 / 无线 | 状态、DPI、125/500/1000 Hz | 待验证 |
| Razer HyperPolling Wireless Dongle | — | 无线 | 未实现 | — |

“待验证”表示协议路径已经实现并通过报文级测试，但项目尚不宣称硬件支持。固件更新、风扇曲线、CPU/GPU 功耗限制、MUX 控制和未公开 EC 写入不在当前范围内。

## 架构

OpenSynapse 将普通权限桌面 UI 与高权限 Windows 操作分离：

```text
OpenSynapse.App  ── 当前用户专用命名管道 ──>  OpenSynapse.Agent
       │                                               │
       └────────── 共享请求模型 ───────────────────────┤
                                                       ├─ Windows 策略 API / powercfg
                                                       └─ 能力门控的 Razer HID
```

Agent 负责模式选择、状态捕获、回滚和硬件写入；UI 不直接写入高权限系统状态或 HID。详情见[架构文档](docs/ARCHITECTURE.md)和共享[领域语言](CONTEXT.md)。

## 构建与测试

要求：

- Windows 11
- 与 [`global.json`](global.json) 匹配的 [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- 仅系统策略和硬件冒烟测试需要管理员 PowerShell

```powershell
dotnet restore OpenSynapse.sln
dotnet build OpenSynapse.sln --no-restore
dotnet test OpenSynapse.sln --no-build
```

先在管理员终端启动 Agent，再从普通终端启动 UI：

```powershell
dotnet run --project src/OpenSynapse.Agent -- serve
dotnet run --project src/OpenSynapse.App
```

在可随时恢复、配置完全明确的 Windows 环境中运行可逆冒烟测试：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1

# 可选：把鼠标当前报告的数值写回，用于验证 HID 传输。
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1 -TestMouseWrites
```

脚本会验证 Performance/Quiet 应用、命名管道生命周期、Agent 关闭、电源方案回滚和状态快照清理。鼠标选项需要可读取的 DeathAdder V3 Pro，并且不会主动选择新的参数。

## 安全与隐私

- Razer 写入要求精确匹配受支持的 VID/PID 和 Consumer HID Usage Page。
- DPI 和轮询率在构造报文前完成验证。
- 响应必须匹配事务、命令类、命令 ID 和校验和。
- 高权限 IPC 只允许当前 Windows 用户访问。
- 捕获的系统状态原子保存到 `%LOCALAPPDATA%\OpenSynapse`。
- 当前实现只读取本机电池状态和 CPU/前台窗口遥测；不包含云分析、自动更新、账户系统或运行时网络客户端。GPU 利用率和独显泄漏诊断尚未启用。

安全问题请按 [SECURITY.md](SECURITY.md) 中的私密流程报告，不要创建公开 Issue。

## 参与贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)、[路线图](ROADMAP.md)和[行为准则](CODE_OF_CONDUCT.md)。硬件贡献必须提供可复现的设备身份和验证证据；只有相同产品名称不足以将设备标记为受支持。

OpenSynapse 最初由 PowerPilot 2.0.0 原型迁移而来。仅供开发使用的原型和协议参考项目应放在已忽略的 `ref/` 目录，项目构建不得依赖其中的文件。

## 许可证与商标

OpenSynapse 使用 [GNU GPL v2 only（`GPL-2.0-only`）](LICENSE)许可证。第三方来源记录在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

OpenSynapse 是独立社区项目，与 Razer Inc. 不存在附属、认可或赞助关系。Razer、Razer Synapse 及相关产品名称是其各自所有者的商标。
