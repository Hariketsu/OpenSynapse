# OpenSynapse 与 PowerPilot 2.1.2 对比与验证报告

检查日期：2026-07-20（Asia/Shanghai）
检查分支：`dev-echo`  近期提交：`9dee4c0`
参考原型：`ref/PowerPilot-2.1.2`（仅作对照，不参与构建）

## 结论

OpenSynapse 已经移植了 PowerPilot 的核心 Windows 策略链路，但目前不能判定为“100% 功能移植且运行无差错”。

已完成并通过代码/自动化测试的主要能力包括：Auto 供电分类、电源方案、Balance 电量锁定、HDR/亮度/显示缩放、基础刷新率策略、状态回滚、卸载清理，以及在原型之外新增的 DeathAdder V3 Pro HID 控制和安全 IPC。

仍存在 2 个功能级缺陷和多项完成度差距：

1. 固定刷新率没有遵守原型的“所有活动显示器必须精确支持目标值”规则，会选择近似刷新率。
2. 原型的 `DynamicNative` 原生动态刷新没有移植。
3. Quiet 的高耗电进程和 ASUS/Armoury 服务维护没有移植。
4. 登录计划任务只启动 Agent，不启动原型中的托盘控制面板。
5. 2.1.2 的自定义应用/托盘图标、完整状态详情、快捷入口和旧版迁移逻辑没有全部移植。

因此当前结论是：核心策略完成度较高，但与 PowerPilot 2.1.2 的完整功能等价仍为“部分完成”；自动化测试通过不能替代目标 Windows 上的管理员策略冒烟测试和真实 Razer 硬件测试。

## 功能映射

| PowerPilot 2.1.2 能力 | OpenSynapse 当前实现 | 状态 | 说明 |
| --- | --- | --- | --- |
| Auto / Hyper / Balance / Quiet 选择 | Auto / Performance / Balanced / Quiet | 已移植 | `Performance` 是 `Hyper` 的重命名；Auto 仍只有高功率 AC 才进入高性能模式。 |
| 供电分类与 130W/100W 阈值 | `SupplyClassifier` + `nvidia-smi` 只读查询 + 5 分钟缓存 | 已移植 | 电池、低功率 PD、未知 AC 和高功率 AC 的 fail-safe 规则一致。 |
| Hyper/Balance/Quiet 13 项电源参数 | `PowerPlanManager.PolicySettings` | 已移植 | 自动化测试逐项核对了 13 项 AC/DC 值。 |
| Balance 最低电量与低电量锁回 Quiet | `ModeSelector` / `AgentController` | 已移植 | 默认阈值 50%，锁定后需要重新选择。 |
| HDR / Advanced Color | `DisplayPolicy` + Windows DisplayConfig | 基本移植 | 有持久化捕获、恢复和热插拔重新应用；尚未完成管理员实机冒烟。 |
| 内屏亮度 | WMI/CIM 读取与设置 | 基本移植 | 有捕获与恢复；尚未完成管理员实机冒烟。 |
| 内屏/外屏显示缩放修复 | DisplayConfig DPI API + 显示变化事件 | 基本移植 | 有首次捕获、热插拔追加捕获和恢复；尚未完成目标双屏/DPI 实机验证。 |
| Follow profile / Fixed 60/120/240 / Unmanaged | `RefreshPolicy` 和 `DisplayPolicy` | 部分移植 | 见 E-001；固定值行为没有实现原型的精确支持和整次预验证。 |
| Native dynamic 60↔240 Hz | 原型 `DynamicRefreshManager` | 未移植 | 见 E-002；当前枚举和 Windows native helper 中都没有该能力。 |
| Quiet 进程维护 | 原型 `Stop-TrackedProcess` / 定时维护 | 未移植 | 当前明确不停止应用，见 E-003。 |
| Quiet ASUS/Armoury 服务维护 | 原型 `Stop-QuietServices` / 恢复 | 未移植 | 当前明确不控制厂商服务，见 E-003。 |
| Quiet 唤醒设备维护 | `WakeDeviceManager` | 安全改造后的部分移植 | 当前为默认关闭、精确名称 allowlist；没有原型默认 wildcard 列表。 |
| 登录后延迟启动常驻控制器 | 计划任务启动 Agent | 部分移植 | Agent 自动应用策略，但托盘 App 不会随登录自动启动，见 E-004。 |
| 托盘、隐藏窗口、单实例 | WPF App + NotifyIcon + 单实例 | 部分移植 | 有单实例和托盘，但当前启动即显示窗口，且登录任务不启动 App。 |
| PowerPilot 2.1.2 专用应用/托盘图标 | 原型 `assets/*.ico` | 未移植 | 当前使用系统 `SystemIcons.Application`，见 E-005。 |
| 完整状态页 | Agent status + WPF 基础状态 | 部分移植 | 缺少原型的各显示器可用刷新率、动态刷新状态、NVIDIA PState/功耗/默认/最大上限等详情，见 E-006。 |
| 原型 SelfTest | Agent self-test | 部分移植 | 当前检查状态、配置、权限、电源、显示器、唤醒设备、Razer 和日志；没有原型的 DPI、图标、Advanced Color、刷新率/动态刷新只读检查，见 E-007。 |
| PowerPilot 2.0.x 升级和旧启动项迁移 | OpenSynapse 安装器 | 未移植 | 当前安装器只处理 OpenSynapse 自身目录和任务，未迁移旧 PowerPilot、旧缩放 watcher 或受限 Snipaste 重复启动项，见 E-008。 |
| 卸载恢复和删除自有电源方案 | Agent `uninstall-cleanup` + 安装器 | 基本移植 | 恢复成功、GUID/名称确认和删除后校验已实现；仍需管理员实机测试。 |
| DeathAdder V3 Pro HID | OpenSynapse 新增能力 | 超出原型 | 已有报文测试和 VID/PID/Usage Page 门控，但本机没有硬件，仍未完成实机验证。 |

## 已确认缺陷和差距

### E-001：固定刷新率会静默选择近似值，并可能部分应用

严重度：P1（功能正确性）

PowerPilot 原型在 `ref/PowerPilot-2.1.2/PowerPilot.Native.cs:642` 先检查每一块活动显示器是否在当前分辨率、色深下精确提供目标刷新率；缺少任意一块时整次操作直接失败。其 `ApplyFrequency` 还通过 `requireExact` 强制精确匹配（同文件约 `:553`、`:583`）。

OpenSynapse 的 `src/OpenSynapse.Agent/Windows/DisplayNative.cs:455` 到 `:503` 在固定刷新率模式下会选择“不高于目标值的最高刷新率”；如果没有更低值，还会选择最小的更高值。`ApplyFixedRefresh`（约 `:521`）逐屏修改，没有先对所有屏幕进行完整预验证。随后 `src/OpenSynapse.Agent/DisplayPolicy.cs:170` 到 `:202` 又把刷新异常直接 `catch` 并忽略。

影响：例如用户选择 Fixed120，但当前显示器只有 60/100Hz 时，系统可能应用 100Hz 而不是报告“不支持 120Hz”；多屏场景还可能先修改前一块屏，再在后一块失败，最终 UI 不会明确报告刷新策略没有满足目标值。

建议：先收集所有活动显示器并精确验证目标值，再执行任何修改；修改后逐屏回读验证；失败时返回可见错误并保留可恢复状态，不要静默吞掉刷新策略异常。

### E-002：`DynamicNative` 原生动态刷新未移植

严重度：P1（功能缺失）

原型配置允许 `DynamicNative`（`ref/PowerPilot-2.1.2/PowerPilot.ps1:322`、`:1592`），并在 `:656` 调用 `PowerPilotNative.DynamicRefreshManager`；原型 native helper 从约 `PowerPilot.Native.cs:726` 开始实现虚拟刷新率、Boost 路径和 `SDC_VALIDATE`。

OpenSynapse 的 `src/OpenSynapse.Core/Models.cs:34` 到 `:41` 只有 `FollowMode`、`Unmanaged`、`Maximum`、`Fixed60`、`Fixed120`、`Fixed240` 六个选项；`src/OpenSynapse.Agent/Windows/DisplayNative.cs` 没有对应动态管理器，`DisplayPolicy` 也没有动态分支。

影响：PowerPilot 2.1.2 的原生动态 60↔240Hz 功能不可配置、不可应用、不可在状态页查看。

建议：迁移原型 `DynamicRefreshManager` 前先补充 native 结构体/API 的单元级封装和回读测试；必须覆盖“内屏活动、外屏固定 120Hz、验证失败不写入、关闭动态后恢复”的路径。

### E-003：Quiet 不再维护高耗电进程和 ASUS/Armoury 服务

严重度：P1（功能缺失；当前属于有意安全取舍）

原型默认启用 `CloseHighDrainAppsInQuiet`、`ManageAsusServices` 和 30 秒周期（`ref/PowerPilot-2.1.2/PowerPilot.ps1:273`、`:275`、`:277`），并通过 `Stop-TrackedProcess`、`Stop-QuietServices`、`Restore-QuietServices` 和定时维护实现。

OpenSynapse 的当前行为在 UI 和文档中明确写成“不停止应用或厂商服务”（`src/OpenSynapse.App/MainWindow.xaml:105`、`README.md:117`）。`Quiet` 只保留了可选的精确名称唤醒设备控制。

影响：原型中 Quiet 用于释放高耗电辅助进程和 ASUS 服务的效果没有移植。当前实现更容易保证可逆性和安全边界，但不能宣称与原型功能等价。

建议：如果继续追求完整 parity，应增加显式关闭开关、受限名称列表、停止前状态记录、恢复验证和周期维护；如果坚持不实现，应在完成度说明中明确标为非目标，而不是标为完整 Quiet parity。

### E-004：登录计划任务只启动 Agent，托盘控制面板不会自动启动

严重度：P1（生命周期/用户体验）

OpenSynapse 的安装定义把计划任务参数固定为 `serve`（`scripts/OpenSynapse.Install.psm1:51` 到 `:60`），安装时只启动该任务（`scripts/Install-OpenSynapse.ps1:68`）。该任务执行 `OpenSynapse.Agent.exe serve`，不会执行 `OpenSynapse.App.exe`。

原型的计划任务执行 PowerShell `-Mode Run`（`ref/PowerPilot-2.1.2/PowerPilot.ps1:954` 到 `:969`），登录后由同一个托盘进程提供控制面板、状态菜单和显示事件处理；原型的 `Open-PowerPilot` 也会通过计划任务唤起已有控制器（约 `:1115`）。

影响：安装后策略 Agent 会自动运行，但用户登录时看不到 OpenSynapse 托盘图标和控制面板；必须另外手动启动开始菜单快捷方式。App 与 Agent 的单实例实现不能弥补“App 根本未启动”的问题。

建议：将 App 的启动纳入当前用户登录任务，或新增独立的非提权 App 登录任务，同时保留 Agent 的高权限策略任务；并增加安装后验证“Agent 和 App 均已就绪”的检查。

### E-005：2.1.2 专用图标未移植

严重度：P2（发布/界面功能缺失）

原型包含 `ref/PowerPilot-2.1.2/assets/PowerPilot.App.ico` 和 `PowerPilot.Tray.ico`，并在 `PowerPilot.ps1:26`、`:27`、`:1371` 到 `:1379` 加载和校验应用/托盘图标。

OpenSynapse 的 `src/OpenSynapse.App/MainWindow.xaml.cs:25` 到 `:30` 使用 `System.Drawing.SystemIcons.Application`；`src/OpenSynapse.App/OpenSynapse.App.csproj` 没有 `ApplicationIcon`，仓库中也没有对应 `.ico` 资源。

影响：窗口、开始菜单快捷方式和托盘图标都没有 PowerPilot 2.1.2 的专用视觉资源，2.1.2 的图标发布要求没有完成。

### E-006：状态详情和原型 UI 快捷入口不完整

严重度：P2（可观测性/界面差距）

原型的 `Get-DisplayStatusText`（`ref/PowerPilot-2.1.2/PowerPilot.ps1:1264`）会显示每块屏的分辨率、当前/可用刷新率、缩放、Advanced Color、动态刷新、亮度和 NVIDIA 状态；原型 UI 还提供打开 Razer Synapse、NVIDIA 控制面板、Windows 显示设置和日志的入口（约 `:1638` 到 `:1682`、`:1874` 到 `:1889`）。

OpenSynapse 的 `AgentStatus` 目前只返回供电和 enforced power limit（`src/OpenSynapse.Core/Models.cs:201` 到 `:215`）；WPF 窗口只有基础模式/策略、唤醒设备和鼠标区域（`src/OpenSynapse.App/MainWindow.xaml:40` 到 `:134`），没有原型的逐屏刷新率能力、动态刷新状态、NVIDIA PState/功耗/默认/最大上限、快速打开外部控制面板或打开日志按钮。窗口尺寸也为 940×900、最小 820×780（同 XAML `:4`），低于原型 1180×940（`PowerPilot.ps1:1397`）。

影响：核心策略可以调用，但用户无法像原型一样完整检查显示/NVIDIA 状态，也缺少原型中的常用入口和 2.1.1 的布局验证目标。

### E-007：SelfTest 覆盖面低于原型

严重度：P2（验证能力不足）

原型 SelfTest（`ref/PowerPilot-2.1.2/PowerPilot.ps1:1191` 到 `:1261`）覆盖 PowerShell 解析、native helper 加载、Per-Monitor DPI、无副作用缩放调用、显示/Advanced Color/动态刷新只读查询、图标加载和电源读取。

OpenSynapse 的 SelfTest 入口在 `src/OpenSynapse.Agent/AgentController.cs:306`，当前检查状态、配置、管理员权限、电源方案、供电、活动显示器、唤醒设备、Razer 设备和日志；没有对应的 DPI、图标、Advanced Color 状态、逐屏可用刷新率或动态刷新只读检查。

影响：当前 SelfTest 通过时，只能说明基础 Agent/配置/电源查询正常，不能证明原型中显示 native 和发布资源的完整功能正常。

### E-008：旧 PowerPilot/旧缩放 watcher/受限启动项迁移未移植

严重度：P2（升级兼容性）

原型包含 `Remove-LegacyAutostarts`、`Stop-LegacyScaleWatcher`、`Get-InstalledPowerPilotVersion` 和严格来源的 Snipaste 重复启动项迁移（`ref/PowerPilot-2.1.2/PowerPilot.ps1:852` 到 `:949`），安装/升级过程中执行这些迁移（约 `:999`、`:1061`）。

OpenSynapse 的源码和脚本中没有对应的 `PowerPilot`、`RazerDisplayScaleFix`、`StartupApproved`、`Snipaste` 或 `FlClash` 处理逻辑；当前安装器只管理 `%ProgramFiles%\OpenSynapse`、OpenSynapse 计划任务、快捷方式和自身用户数据。

影响：从 PowerPilot 原型或旧版缩放 watcher 升级时，旧计划任务、旧 Run 项、电源方案和旧用户数据不会被 OpenSynapse 自动识别、迁移或清理，可能造成重复控制器或遗留策略。

### E-009：中文 README 已落后于当前实现

严重度：P2（文档错误）

`README.zh-CN.md` 的当前状态表仍只列 Auto、Performance、Quiet，没有 Balanced；构建测试示例也只运行 Core 测试，未反映 Agent 测试、安装/卸载、Quiet 唤醒设备和当前配置项。英文 `README.md` 已包含这些内容。

影响：中文用户按文档无法获得当前版本的完整功能和验证范围，容易误判完成度。

## 验证结果

### 已执行并通过

- Release build：0 warning、0 error。
- `dotnet format --verify-no-changes`：通过。
- Core tests：34 passed。
- Agent tests：49 passed。
- 总测试：83 passed、0 failed。
- 21 个项目 PowerShell 脚本（当前安装脚本和原型测试/脚本）语法解析通过。
- `scripts/Test-InstallerDefinitions.ps1`：通过。
- 当前发布版只读 `status`：成功，读取到高功率 AC、约 78% 电量、约 150W GPU enforced limit、1 个活动显示器、2 个 wake-armed 设备。
- 当前发布版 `self-test`：`0 failure(s), 2 warning(s)`；警告为未提升权限和未检测到支持的 Razer 设备。

### 尚未执行、不能据此宣称“无差错”的验证

- `scripts/Test-Milestones.ps1` 管理员 Windows 冒烟：会真实切换并恢复电源方案、亮度、HDR、缩放和刷新率，本次未执行。
- Native dynamic refresh 的目标设备回读：当前功能本身尚未移植。
- DeathAdder V3 Pro 各 VID/PID、无线/有线连接的真实读写：本机未检测到支持设备。
- 安装、登录启动、托盘图标和卸载的真实目标 Windows 端到端验证。

## 建议开发顺序

1. 先修复 E-001：固定刷新率全量预验证、精确应用、回读和错误可见化。
2. 决定是否将 E-003 的进程/服务维护列为 OpenSynapse 的正式目标；若是，按可逆状态模型实现并测试。
3. 迁移 E-002 的 DynamicNative，并补充目标显示器回读测试。
4. 修复 E-004、E-005 和 E-006：登录双进程生命周期、专用图标、完整状态和 UI 快捷入口。
5. 增加 E-008 的升级迁移策略，并更新 E-009 中文文档。
6. 在目标 Windows 管理员环境执行完整冒烟，随后再做真实 DeathAdder 硬件验证。
