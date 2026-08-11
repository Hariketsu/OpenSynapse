[English](README.md) | [简体中文](README.zh-CN.md)

# OpenSynapse

[![构建](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml/badge.svg)](https://github.com/Hariketsu/OpenSynapse/actions/workflows/build.yml)

OpenSynapse 是一个本地优先的开源 Windows 控制中心，用于管理受支持的 Razer 硬件和系统策略。项目的目标是用能力明确、状态变化可检查、可靠回滚的开放实现，替代不透明的常驻软件。

> [!WARNING]
> 电源与显示运行时现已直接建立在实机验证过的 PowerPilot 2.4.1 上。DeathAdder 写入仍受硬件白名单保护，并需要连接目标设备完成实测。测试设备控制时，请关闭 Razer Synapse。

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
| Windows 策略 | Smart Auto、Hyper、Balance、Eco 与锁定式 Experiment；电源方案、仅内屏 Windows DRR/固定刷新率、Advanced Color/HDR、逐屏亮度和显示缩放 | 0.2.0-preview.2 Windows CCD 动态刷新控制已测试 |
| Smart Auto | 供电、CPU/GPU、前台/全屏应用、应用规则、迟滞、临时模式、dGPU 连续活动诊断 | 已实现；GPU 不可用时安全回退到 CPU/窗口信号 |
| 状态恢复 | 显示模式、ICC 关联/哈希、HDR、DRR、缩放、WMI/DDC 亮度的原子捕获及回读恢复，以及旧 .NET/PowerPilot 接管 | 使用硬件身份检查拓扑，避免内外屏同名 DISPLAY1 误判 |
| 研究遥测 | Experiment 环境报告、GPU/NPU 可用性、温度/节流、屏幕和策略证据 | 已实现；缺失计数器会明确标记，不伪造 0% |
| 桌面控制 | 单个提权的 PowerShell 5.1/WinForms 托盘进程，通过延迟且最高权限的当前用户计划任务启动 | 已安装并完成现场验证 |
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

发布版现在沿用 PowerPilot 2.4.1 已验证的单进程模型：

```text
OpenSynapse 计划任务（最高权限、STA）
        │
        └─ OpenSynapse.ps1（WinForms UI、托盘、自动化、Experiment 锁）
                └─ 动态编译 OpenSynapse.Native.cs
                        ├─ 显示、电池、GPU/NPU 与温度遥测
                        ├─ Windows 策略 API / powercfg
                        └─ 受白名单保护的 DeathAdder HID 报告
```

这样移除了上一版 WPF 与 Agent 之间的启动、UAC 和命名管道故障点。详情见[架构文档](docs/ARCHITECTURE.md)。

## 构建与测试

要求：

- Windows 11
- Windows PowerShell 5.1
- 安装和系统策略变更需要管理员确认

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-InstallerDefinitions.ps1
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1
```

保留的 .NET 解决方案仍包含上一版实现的协议和单元测试代码，但不再作为发布版桌面运行时。

发布并安装：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Publish-OpenSynapse.ps1
powershell -ExecutionPolicy Bypass -File scripts\Install-OpenSynapse.ps1
```

发布结果位于 `artifacts\publish\OpenSynapse` 和 `artifacts\OpenSynapse-0.2.0-preview.2.zip`。如果旧 .NET Agent 仍存在，安装器会先调用它恢复已捕获状态；如果旧二进制已不存在，则直接恢复旧状态中的电源计划、显示、亮度和唤醒权限。如果检测到已安装且正在运行的 PowerPilot，安装器会归档它的配置和恢复状态，调用 PowerPilot 自身的卸载流程恢复 Windows，并把用户配置提升为 OpenSynapse 配置。随后才会清理旧运行时、安装 `%ProgramFiles%\OpenSynapse`、注册唯一的最高权限当前用户静默启动任务并创建开始菜单快捷方式。

在可随时恢复、配置完全明确的 Windows 环境中运行完整管理员测试：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1 -AdminRelease

# 可选：把鼠标当前报告的数值写回，用于验证 HID 传输。
powershell -ExecutionPolicy Bypass -File scripts\Test-Milestones.ps1 -TestMouseWrites
```

鼠标选项需要可读取的 DeathAdder V3 Pro，并把当前值写回，不会主动选择新的参数。

## 安全与隐私

- Razer 写入要求精确匹配受支持的 VID/PID 和 Consumer HID Usage Page。
- DPI 和轮询率在构造报文前完成验证。
- 响应必须匹配事务、命令类、命令 ID 和校验和。
- 安装版以当前用户的最高权限计划任务单进程运行，不再依赖命名管道 IPC。
- 捕获的系统状态原子保存到 `%LOCALAPPDATA%\OpenSynapse`。
- PowerPilot 兼容默认值会在 Eco 中按配置维护高耗电辅助进程、Armoury Crate/ASUS 服务和唤醒设备；兼容配置中的内部枚举仍为 `Quiet`。需要保持常驻的项目应先从 `config.json` 白名单中移除。
- 当前实现只读取本机电池、CPU、前台窗口和 Windows GPU 性能计数器遥测；不包含云分析、自动更新、账户系统或运行时网络客户端。GPU 后台采样按 280W 供电 5 秒、离电/PD 10 秒、手动 Eco 20 秒动态调整，只有带新序号和时间戳的样本才会推进 dGPU 活动判断；电池趋势写入本地 30 秒 JSONL 历史。离电主循环按负载动态使用 10 或 15 秒，外接供电保持 5 秒。
- Experiment 是持久锁定档而不是 Auto 目标：进入时使用独立且已验证的电源方案，固定目标刷新率，并捕获每块活动显示器的模式、ICC 关联与 SHA-256、HDR、DRR、缩放及可用的 WMI/DDC 亮度；运行中检测并修复漂移，退出后恢复实验前状态。报告以 JSON、HTML 和 SHA-256 文件写入 `%LOCALAPPDATA%\OpenSynapse\experiment-reports`。
- 本地 `telemetry.jsonl` 升级为 schema 6，增加缓存式 GPU/NPU 可用性、温度/节流和逐屏状态证据；离电时硬件/显示采样放宽到 60 秒，自动 Experiment 报告不会为读取 NVIDIA 数据而唤醒闲置 dGPU。
- 离电高耗电提示每 30 秒采样进程 CPU 增量，需要连续两次达到单核 15% 且平均放电不低于 14 W；默认 30 分钟冷却，只提示、不结束进程，证据写入本地 schema-6 遥测。
- 适配器只有在读数不高于 85 W 且经过启动预热、三次间隔采样后才降级为 PD；单次不低于 130 W 的读数仍会立即确认高功率 AC。OpenSynapse 不管理外屏刷新率；内屏 `Auto` 在离电、PD 和未确认 AC 下通过 Windows CCD/SetDisplayConfig 启用原生 60–240 Hz DRR，确认 280W 后固定 240 Hz。新增独立 `Windows DRR` 选项，可在任意供电下交由 Windows 动态调节内屏；手动 Eco 60 Hz/固定 240 Hz 在新接入外部供电时恢复 `Auto`。动态刷新失败时只有内屏回退到 Eco 60 Hz。所有档位的 AC 普通/锁屏显示关闭时间为 15 分钟，AC 待机为 3 小时。

安全问题请按 [SECURITY.md](SECURITY.md) 中的私密流程报告，不要创建公开 Issue。

## 参与贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)、[路线图](ROADMAP.md)和[行为准则](CODE_OF_CONDUCT.md)。硬件贡献必须提供可复现的设备身份和验证证据；只有相同产品名称不足以将设备标记为受支持。

OpenSynapse 最初由 PowerPilot 2.0.0 原型迁移而来。仅供开发使用的原型和协议参考项目应放在已忽略的 `ref/` 目录，项目构建不得依赖其中的文件。

## 许可证与商标

OpenSynapse 使用 [GNU GPL v2 only（`GPL-2.0-only`）](LICENSE)许可证。第三方来源记录在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

OpenSynapse 是独立社区项目，与 Razer Inc. 不存在附属、认可或赞助关系。Razer、Razer Synapse 及相关产品名称是其各自所有者的商标。
