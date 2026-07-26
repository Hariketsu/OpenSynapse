# OpenSynapse 与 PowerPilot 2.4.1 重新移植报告

检查分支：`dev-echo`
参考原型：`ref/PowerPilot2.4.1`

## 结论

上一版 OpenSynapse 把 PowerPilot 2.4.1 的 PowerShell/WinForms 单进程架构重写成了 WPF UI + 独立提权 Agent + 命名管道。虽然核心算法被分别实现，但启动、提权、IPC、状态所有权和 UI 生命周期发生了根本变化，现场出现了 `Agent unavailable`、`Agent offline`、UAC 取消以及 IPC 访问错误，因此不能视为等价移植。

本次重新移植不再延续这条分叉：发布版直接以 PowerPilot 2.4.1 的脚本、原生助手、五页 UI、计划任务、安装/卸载、Smart Auto 和恢复模型为底座，完成全量 OpenSynapse 重命名，并合入 DeathAdder V3 Pro HID 功能。

## 当前发布架构

| 项目 | 当前实现 |
| --- | --- |
| 产品入口 | `OpenSynapse.ps1` |
| UI | PowerPilot 2.4.1 WinForms 五页深色 UI，产品名改为 OpenSynapse |
| 后台 | 与 UI 同进程的托盘和 5 秒自动化循环 |
| 提权 | 当前用户最高权限计划任务，登录延迟 30 秒 |
| IPC | 不需要；已移除 WPF/Agent 命名管道故障点 |
| 原生能力 | `OpenSynapse.Native.cs` 由 Windows PowerShell 5.1 动态编译 |
| 数据目录 | `%LOCALAPPDATA%\OpenSynapse` |
| 安装目录 | `%ProgramFiles%\OpenSynapse` |
| 任务名 | `OpenSynapse` |
| AppUserModelID | `OpenSynapse.Desktop` |

## PowerPilot 2.4.1 功能移植状态

以下能力直接来自并保留 2.4.1 的实现：

- Auto / Hyper / Balance / Quiet；
- 280W、USB-C PD、电池和未知交流供电分类及防抖；
- CPU 最小/最大状态、EPP、Boost、核心停放、PCIe、Wi-Fi、USB、睡眠和待机策略；
- Smart Auto 的 CPU/GPU、前台、全屏、应用规则、迟滞和最短驻留；
- 临时模式和供电变化结束条件；
- HDR、亮度、缩放、固定/动态刷新率；
- Quiet 进程、服务与唤醒设备维护；
- 电池 Class API、GPU/DXGI、dGPU 活动、遥测历史和诊断导出；
- 原子配置、回滚状态、运行健康、错误退避；
- 五页 UI、自定义标题栏拖动、任务栏身份、托盘和开始菜单快捷方式；
- 安装、覆盖升级、计划任务、卸载恢复和管理员发布测试。

## 合入的雷蛇鼠标功能

OpenSynapse 新增了与上述单进程运行时兼容的 `OpenSynapseNative.RazerMouse`：

- 只枚举 Razer VID `1532`；
- 只允许 DeathAdder V3 Pro PID `00B6`、`00B7`、`00C2`、`00C3`；
- 只接受 HID Usage Page `0x0C` 控制接口；
- 读取产品名、连接类型、固件、序列号、DPI、轮询率、电量和充电状态；
- 写入 100–30000 DPI；
- 写入标准接收器 125/500/1000 Hz；
- 校验响应状态、事务 ID、命令类、命令 ID 和 XOR 校验和；
- 在 Settings 页显示设备状态并提供 DPI、轮询率和刷新操作；
- 在 Diagnostics 页输出鼠标证据。

该能力使用 Windows 自带 HID 用户态 feature report，不安装或替换内核驱动，不写固件、EC、风扇、TGP 或 MUX。

## 迁移处理

安装新版时会先停止旧的 `OpenSynapse Agent` 计划任务以及 `OpenSynapse.Agent` / `OpenSynapse.App` 进程。如果旧 Agent 可执行文件仍存在，安装器先调用其 `uninstall-cleanup` 完成原实现的恢复；如果二进制已经缺失，则由新运行时直接恢复旧 schema-10 状态中的原电源计划、HDR、显示缩放、亮度和唤醒权限。随后若检测到已安装的 PowerPilot，先把其配置和恢复状态归档到 OpenSynapse 数据目录，再调用 PowerPilot 自身的恢复/卸载入口，确认旧任务和运行时消失后把兼容配置提升为 OpenSynapse 配置。最后才清理旧目录并注册唯一的单进程 `OpenSynapse` 任务，防止两个策略引擎同时控制系统。

## 验证边界

自动测试可以证明脚本可解析、原生 C# 可编译、功能定义完整，以及 Razer DPI/轮询报告构造和校验和正确。真实 DPI、轮询率、固件和电量回读仍需要连接受支持的 DeathAdder V3 Pro；未连接设备时必须显示“未检测到设备”，不能把它记为硬件通过。

2026-07-25 的真实安装验证已确认：`OpenSynapse` 是唯一运行的策略任务，状态为 Running/Highest/Interactive，运行时为 Healthy/PerMonitorV2，Auto 在 155 W HighPowerAC 下处于合法的 Balance 档位，78 个电源参数、快捷方式、图标、AppUserModelID 和发布包哈希全部通过。旧 PowerPilot 的 21 条应用规则已保留。

本机枚举到的 Razer PID `02C6` 属于 Razer Blade 16（2025）内置键盘，而不是 DeathAdder 控制接口；因此鼠标发现为 0 是正确的白名单结果。本轮未声称真实鼠标写入通过。
