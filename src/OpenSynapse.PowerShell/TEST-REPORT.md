# OpenSynapse 验证报告

## 2026-08-03 2.5.1 外屏 Modern Standby 唤醒修复

- 故障证据：20:07:26 系统进入 Modern Standby，2.5.0 在锁屏期间于 20:07:53、20:08:08 执行 `Fixed240`；20:08:30 唤醒后又在不稳定拓扑上重复执行。20:09:28 只剩内屏 2560×1600/150%，外屏 DDC 端点消失；重新插线后 20:10:03 恢复外屏 2560×1440/125%/DDC 70%。
- 排除项：供电始终为 `HighPowerAC`，外屏连接 AMD Radeon 880M，Windows 没有记录 AMD/NVIDIA 显示驱动崩溃，因此不是 280W→PD 误判或 NVIDIA TGP/Hyper 切换故障。
- 修复验证：锁屏和挂起均阻断显示写入；相同 `DISPLAY1` 下不同 `MonitorDeviceKey` 会被判定为不同拓扑；预期外屏缺失会等待，拓扑连续两次稳定后才允许应用。
- 安装回读：2.5.1 计划任务 `Running/Highest`，运行时 `Healthy/PerMonitorV2`，配置 v14、状态 v11，78 项电源参数、安装文件、快捷方式和图标全部通过，启动后策略失败为 0；启动日志正确记录 `external=1; responsive=1`。
- 当前真实三星外屏只读验证通过：首次采样 `TopologyStabilizing`、第二次采样 `Stable`。未主动触发一次完整 Modern Standby 物理复现，以免在本轮安装期间再次中断用户显示连接。
- 版本 2.5.1；未更改 OEM 异构核心阈值、EC、风扇、TGP 或 MUX。

## 2026-08-02 2.5.0 Experiment、逐屏恢复与硬件遥测

验证日期：2026-08-03
分支：`dev-echo`
参考：`ref/PowerPilot2.4.1`

## 2026-08-03 Experiment 与逐屏状态验证

- 新增独立且锁定的 Experiment 档位；Auto、临时档和供电切换不能覆盖，退出时恢复实验前状态。报告失败不会阻断恢复，退出目标应用失败会回落 Auto，不留下无会话的幽灵 Experiment 状态。
- 完整快照覆盖活动显示器模式/色深/位置/方向、ICC 关联与 SHA-256、HDR/Advanced Color、DRR、缩放、WMI 亮度和 DDC/CI 物理显示器亮度；所有写入路径带回读验证。
- 本机非破坏性“当前状态→同值恢复→逐项比较”通过：`Verified=True`、`Changes=0`、`Differences=0`。当前活动外屏 `DISPLAY1` 的 DDC/CI 亮度端点可读，测试时为 70/100。
- 实验报告同时生成 JSON、HTML 与 SHA-256；记录 OpenSynapse/遥测 schema、Windows/BIOS/EC、显示/ICC、GPU、温区、节流与 NPU 计数器可用性。
- 本机读取到 2 个 ACPI 温区；Windows 当前未暴露 NPU 性能计数器，界面和报告明确显示 `Not exposed`，没有伪造 0% 利用率。外屏活动时内屏 DRR 不可实机切换，因此未声称完成内屏动态刷新写入验证。
- PowerShell 23/23 项定义/运行时测试通过（Snipaste 项在专用 HKCU 临时键中单独通过）；Experiment 专项包含逐屏采集、漂移检测、报告及原生接口检查。
- .NET Core 39/39、Agent 53/53、安装器定义、PowerShell 解析/原生 C# 编译、`git diff --check` 均通过。
- Dashboard、Diagnostics、Settings 在 1440×900、96 DPI 下完成实际捕获，所有可见控件均位于父容器范围内。
- 2.5.0 已在目标机完成管理员安装与现场回读：计划任务为 `Running/Highest`，运行时 `Healthy/PerMonitorV2`，配置 v14、状态 v11，78 项电源参数、快捷方式、图标和安装文件哈希全部通过，启动后的策略应用失败为 0。当前活动档位为 Hyper，供电分类为 `HighPowerAC`。
- 本轮未连接白名单 DeathAdder V3 Pro，且外屏活动时内屏未激活，因此不宣称鼠标 HID 写入或内屏 DRR 60–240 Hz 切换已在 2.5.0 完成硬件闭环。

## 2026-08-02 Eco 模式、280W 恢复与界面命名验证

- 页面、托盘、状态提示、临时模式和应用规则只显示 `Eco` 作为节能模式名称；兼容配置、遥测和回滚数据仍使用内部 `Quiet` 枚举。
- 手动 Eco 强制内屏固定 60 Hz，并在进入时关闭 HDR/Advanced Color；即使用户此前选择“不管理刷新率”，Eco 仍执行 60 Hz 安全边界。
- Eco 保持 Ryzen AI 9 365 现有 CPU 65/60/50%、EPP 90/95/100 与 Boost 关闭策略；Smart Auto 决策及决策日志在手动 Eco 中暂停。
- 电池、PD 或持续 280W 供电不会自行解除手动 Eco；只有新接入并确认的 280W 级适配器会恢复 Auto、内屏 240 Hz 与进入 Eco 前捕获的 HDR 状态。程序冷启动时已确认 280W 执行相同恢复。
- OEM 异构核心增减阈值、TGP、风扇、EC 与 DeathAdder V3 Pro HID 路径保持不变。
- PowerShell 定义/运行时回归 22/22 通过；其中 Snipaste 迁移测试仅写入并清理专用 HKCU 临时键，其余测试均不改变系统设置。
- .NET Core 39/39、Agent 53/53、`dotnet format --verify-no-changes` 与安装器定义检查通过。
- Dashboard 与 Settings 在 1440×900、96 DPI 下完成实际 WinForms 捕获；所有控件位于父容器边界内，Eco 名称和 CPU/提示/显示按钮文案均完整显示。
- 当前内屏未激活，`DynamicRefreshSupported=False`；本轮没有改变显示拓扑，动态 60–240 Hz 与 Eco 60 Hz 路径通过原生 API 编译、状态解析和非破坏性策略回归验证。
- 发布包为 `OpenSynapse-2.4.6.zip`；发布脚本已重新解析 PowerShell 并动态编译原生 C# 辅助代码。
- 2.4.6 已实际安装到本机：任务 `Running/Highest/Interactive`，运行时 `Healthy/PerMonitorV2`，首个成功心跳存在，78 项电源参数回读通过，开始菜单快捷方式、图标、AppUserModelID 与发布包一致，启动后的 Apply 失败数为 0。
- 安装时发现旧启动流程只验证 runtime 文件存在，无法拦截托盘卡在 `Starting` 的情况；现已改为等待 `Healthy + LastSuccessfulTickUtc`，重新安装后验证通过。管理员安装态测试同时修复为读取真实安装目录和 v13 配置。

## 2.4.5 历史验证

## 2026-08-02 离电高耗电提示、动态循环与刷新率回退验证

- 离电高耗电检测采用独立的 30 秒原生进程 CPU 增量采样；连续 2 次达到单核 15% 且 10 分钟平均/EMA/即时放电证据不低于 14 W 才提示；
- 系统进程、PowerShell 与 OpenSynapse 自身默认排除；提示默认冷却 30 分钟，只记录候选名称、CPU、放电和置信度，不调用 `Stop-Process`；AC 接入、禁用开关或锁屏时清除检测状态；
- 健康主循环在外接供电维持 5 秒；真正离电时，有明显 CPU/GPU/全屏活动采用 10 秒，低负载、锁屏或手动 Quiet 采用 15 秒；故障退避继续独立使用 10/20/40/60 秒；
- 内屏 `Auto`：Battery/LowPowerPD/UnknownAC 解析为 `DynamicNative`（Windows 60–240 Hz），HighPowerAC 解析为固定 240 Hz；外屏两条路径均保持当前分辨率最大刷新率；
- 动态刷新率应用或回读验证失败后，独立关闭失败的 DRR 状态并把内屏回退到 Eco 60 Hz；即使外屏最大刷新调用失败，也不会阻断内屏兜底；
- 手动 Eco 60 Hz/固定 240 Hz：电池→AC 或 PD→已确认 280W 时恢复 `Auto`；AC 状态内普通刷新不会误重置；
- 自动刷新只在启动、供电变化和显示拓扑修复时执行，不会因 Smart Auto 在 Quiet/Balance/Hyper 间切换而反复改显示链路；HDR、缩放仍需显式应用；
- GPU 遥测采样映射为 HighPowerAC 5 秒、离电/PD 10 秒、手动 Quiet 20 秒；重复读取同一 GPU 样本不会推进 6 样本 dGPU 活动门槛；
- GPU 遥测同进程停止/重启及运行中采样周期唤醒回归通过，供电状态切换后无需等待旧周期结束；
- Chrome 等浏览器全屏轻载 18% CPU/8% GPU 不升 Hyper；达到 50% CPU 并持续 3 个样本后正常升 Hyper；显式应用规则不受影响；
- PowerShell 定义/运行时自检 22/22 通过，其中 21 项在受限环境直接通过，Snipaste 迁移项仅写入并清理专用 HKCU 临时键后通过；
- .NET Core 39/39、Agent 53/53、`dotnet format --verify-no-changes`、`git diff --check` 和安装器定义检查通过；
- 1440×900、96 DPI Settings 截图验证通过，新增高 CPU 提示开关及所有控件均位于父容器边界内；发布包 `OpenSynapse-2.4.5.zip` 已通过 PowerShell 解析和原生 C# 动态编译；
- 当前内屏仍未激活，未改变显示拓扑，因此本轮只完成原生 API 编译、状态解析与非破坏性能力回读；安装态仍为 2.4.3，2.4.5 尚未覆盖安装。

## 2026-08-01 供电防误判、遥测与刷新率增量验证

- 复现 280W 瞬态序列 `91.86 → 105 → 105 → 105W`：从 Balance/未知档位冷启动时不再进入 `LowPowerPD`；
- 真实 PD 序列 `78.74 → 76.09 → 79.32W`：30 秒预热后按 3 次、跨度 14 秒确认；
- 手动 Quiet 不再预置为 PD，单次 `151.62W` 高功率证据仍立即确认并恢复 Auto：通过；
- telemetry schema 3：适配器限值、原始/稳定供电类型、待确认状态、分类器与应用版本字段：通过；新增字段复用既有快照，无额外硬件轮询；
- 本机 1000 次遥测写入基准：834 字节/条、1.156ms CPU/条；按 30 秒一次折算约 0.00385% CPU duty、97.7KiB/小时；
- 刷新率设备映射：当前外屏识别为 `\\.\DISPLAY1` 且运行在 2560×1440 240Hz；固定策略只作用于内屏，外屏取当前分辨率最高刷新率；
- 当前内屏未激活，无法执行会改变显示拓扑的 60→240Hz 实机回读；历史日志曾在内屏活动时成功应用 `DynamicNative changed=2`，本轮非破坏性检查确认代码路径、Windows 验证 API 与外/内屏映射正常；
- 内屏未激活时动态刷新改为延迟，不再反复产生失败，提示限制为每 30 分钟一次；
- 非管理员定义/运行时里程碑测试 21/21、管理员可逆发布测试 24/24、.NET Core 39/39、Agent 52/52：通过；
- 上一安装态回读：版本 2.4.3、任务 Running/Highest、运行时 Healthy/PerMonitorV2、78 个电源参数、快捷方式和图标均通过，启动后 Apply 失败为 0；该条为 2.4.3 历史安装证据；
- 安装后 telemetry schema 3 实际落盘回读：`SupplyType=HighPowerAC`、`RawSupplyType=UnknownAC`、`AdapterLimitW=105`，证明稳定分类与原始证据可以同时追踪；
- 外屏实机策略回归：用内屏 60Hz 策略路径执行后，活动外屏仍由 2560×1440 240Hz 保持为 240Hz，变更计数为 0。

## 2026-07-27 Quiet 2.4.2 发布与本机安装验证

- Ryzen AI 9 365 Quiet DC 曲线：`>=70%` 为 CPU 65% / EPP 90，`30–69%` 为 CPU 60% / EPP 95，`<30%` 为 CPU 50% / EPP 100：通过；
- 手动 Quiet 在电池、PD 和持续 280W 供电期间保持锁定，不推进 Smart Auto；仅检测到新的 280W 级 `HighPowerAC` 接入时解除锁定并恢复 Auto：通过；
- OEM 异构核心增减阈值、TGP、风扇和 EC 不写入检查：通过；
- 非管理员定义/运行时里程碑测试：21/21 通过；
- 管理员发布测试：24/24 通过，包含临时计划任务与电源方案回读/恢复；
- .NET Core 38/38、Agent 52/52，Release 构建 0 警告/0 错误，格式检查：通过；
- 本机安装态回验：版本 2.4.2、运行健康 Healthy、任务 Running/Highest、78 个电源参数、快捷方式、图标与包哈希全部通过；
- 本机供电识别为 HighPowerAC，安装后配置为 Auto，当前活动档位 Hyper，启动后 Apply 失败数为 0；
- 发布包：`OpenSynapse-2.4.2.zip` 已生成并通过原生 C# 编译检查。

## 2026-07-26 Quiet v11 增量验证

- PowerShell 解析、自检和 21 项定义/运行时里程碑测试：通过；
- Quiet 专项：65/60/50% 三段 CPU 上限、95/95/100 EPP、三类处理器同步和高效核心调度：通过；
- 控制语义：Auto 离电可升 Balance、手动 Quiet 锁定、手动决策日志暂停：通过；
- NVIDIA Overlay 快速重启检测、30 分钟冷却和提示路径：通过；
- telemetry schema 2 的 `ActiveProfile`、`BatteryRemainingMwh`、`BatteryVoltageMv`、`EstimatedHours`：通过；
- OEM 异构核心增减阈值、TGP、风扇和 EC 不写入检查：通过；
- .NET Core 38/38、Agent 52/52，Release 构建 0 警告/0 错误，格式检查：通过；
- 发布目录与 `OpenSynapse-2.4.1.zip` 重新生成并通过原生 C# 编译检查；
- 管理员电源计划回读套件因本轮 UAC 被取消而未执行；本轮没有安装，也没有修改本机现有电源计划。

## 结论

发布运行时已重新建立在 PowerPilot 2.4.1 的单进程 PowerShell 5.1/WinForms 实现上，不再依赖 WPF、独立 Agent 或命名管道。PowerPilot 配置和系统状态已安全接管，OpenSynapse 计划任务、托盘进程、电源计划、快捷方式和 UI 均可正常运行。

## 自动测试

- PowerShell 文件解析：通过；
- 非破坏性脚本/定义测试：22/22 通过；
- 配置迁移：PowerPilot 旧配置、旧 .NET schema 10、中断接管文档及当前配置 v13 均通过；
- Razer HID：4 个白名单 PID、DPI/轮询率报告构造、事务和校验和通过；
- .NET 历史回归：Core 39/39、Agent 53/53；
- Release 构建：0 警告、0 错误；
- `dotnet format --verify-no-changes`：通过；
- 发布包自检与原生 C# 动态编译：通过。

## 真实安装验证

安装态测试 `Test-LiveInstallation.ps1` 已通过：

- 版本：2.4.2；
- 任务：Running、Highest、Interactive、登录延迟 PT30S；
- 运行时：PerMonitorV2、`OpenSynapse.Desktop`、Healthy；
- 当前设备：Razer Blade 16 RZ09-0528；
- 当前供电：HighPowerAC，NVIDIA enforced limit 155 W；
- Auto 当前合法档位：Balance；
- Hyper/Balance/Quiet 共 78 个电源参数回读正确；
- 开始菜单快捷方式、应用图标、托盘图标和发布包哈希一致；
- 启动后的 Apply 失败数：0；
- PowerPilot 与旧 `OpenSynapse Agent` 任务已移除，仅保留一个 OpenSynapse 策略引擎。

PowerPilot 的 21 条应用规则已保留。旧 .NET 状态、配置和 PowerPilot 接管记录均已归档。

## UI 验证

- 1440×900、96 DPI 捕获通过；
- Dashboard 与 Settings 所有控件均在父容器边界内；
- 五页导航、深色控件、自绘标题栏、最小化/最大化/隐藏关闭正常；
- 标题栏、品牌图标和品牌文字均连接 `BeginDrag`，拖动定义测试通过；
- Settings 已包含离电高 CPU 提示开关与 DeathAdder V3 Pro HID 控制区。

## 硬件验证边界

当前机器没有连接受支持的 DeathAdder V3 Pro 控制接口，因此设备发现结果为 0。系统中的 Razer PID `02C6` 是 Razer Blade 16（2025）内置键盘，不会加入鼠标白名单。

因此本轮可以确认：

- HID 枚举过滤不会误操作内置键盘或其他设备；
- DPI/轮询率请求格式和响应校验正确；
- 未连接白名单鼠标时 UI 安全禁用写入。

仍需连接 PID `00B6/00B7/00C2/00C3` 的 DeathAdder V3 Pro 后，完成真实 DPI、轮询率、固件、电量与充电状态回读闭环。测试鼠标写入时应先退出 Razer Synapse，避免两个用户态控制程序竞争同一接口。
