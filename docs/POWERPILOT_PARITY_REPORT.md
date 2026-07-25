# OpenSynapse 与 PowerPilot 2.4.1 功能/UI 移植检查报告

检查日期：2026-07-25（Asia/Shanghai）
检查分支：`dev-echo`
参考原型：`ref/PowerPilot2.4.1`
参考版本：目录内容、README 与 CHANGELOG 标识为 PowerPilot 2.4.1；目录名本身无歧义地按 2.4.1 处理。

## 当前结论

OpenSynapse 已完成核心电源策略、Smart Auto、临时模式、应用规则、显示策略、五页 UI、诊断导出、安装启动和原有 DeathAdder V3 Pro HID 路径的主要移植，并将产品名、任务栏 AppUserModelID、界面文案和发布图标改为 OpenSynapse。

目前不能宣称“所有功能在目标机器上无差错”。原因是部分功能必须在管理员权限、目标显示器和真实雷蛇鼠标上实测；另外 2.4.1 的 GPU 利用率/独显泄漏诊断、Quiet 进程/厂商服务维护和 30 秒 JSONL 遥测历史仍未完全移植。

## 功能映射

| 2.4.1 能力 | OpenSynapse 状态 | 备注 |
| --- | --- | --- |
| Auto / Hyper / Balance / Quiet | 已移植 | 内部保留 `Performance/Balanced` 兼容名，UI/CLI 显示 Hyper/Balance。 |
| 130W/100W 适配器分类 | 已移植 | 只读 `nvidia-smi enforced.power.limit`，保留缓存和 fail-safe。 |
| 25 项电源策略及 Hyper/Quiet 专属项 | 已移植 | 包含效率类核心、Boost、EPP、核心停放、唤醒计时器和待机网络策略。 |
| Quiet 动态 CPU 上限 | 已移植 | 电池按 75/65/60% 区间写入 Quiet DC 最大状态。 |
| Smart Auto 应用/CPU/全屏防抖 | 已移植 | Core 纯逻辑引擎；支持性能/生产力名单、全屏保护、最短驻留和退出迟滞。 |
| Smart Auto GPU 负载判定 | 部分移植 | 接口字段和决策路径已存在，但当前 GPU 利用率提供程序返回不可用，不能据此进行 GPU 升档。 |
| 应用规则 Foreground/Fullscreen/Running | 已移植 | 本地配置、边界校验、UI 增删改；Running 规则才枚举进程。 |
| 临时模式 30/60/120 分钟/直到供电变化 | 已移植 | 到期或供电分类变化后恢复持久选择；Balance 仍受电量锁定。 |
| HDR、亮度、缩放 | 已移植 | 有捕获、热插拔追加捕获和恢复；Quiet 电池亮度上限为 35/30/20%。 |
| Follow / Fixed60/120/240 / Unmanaged | 已移植 | 固定值先验证所有活动显示器的当前分辨率和色深下的精确支持，失败可见。 |
| Native dynamic 60↔240Hz | 已移植 | 使用 DisplayConfig/SetDisplayConfig；需要目标内屏支持虚拟刷新率才能现场确认。 |
| Quiet 唤醒设备 | 已移植 | 默认关闭、精确名称 allowlist；不使用 wildcard 误伤设备。 |
| Quiet 高耗电进程维护 | 未完成 | 当前仍不主动停止用户进程。 |
| Quiet ASUS/Armoury 服务维护 | 未完成 | 当前仍不控制厂商服务，避免无明确授权造成系统影响。 |
| 电池 Class API 瞬时功率/容量/估算 | 部分移植 | 已接入 Windows `SystemBatteryState`，提供瞬时放电/充电和剩余容量；尚未实现原型的 EMA/10 分钟历史。 |
| GPU Performance Counter/dGPU 泄漏诊断 | 未完成 | 当前状态显示 GPU unavailable，不会用 `nvidia-smi` 高频唤醒独显。 |
| 30 秒 telemetry.jsonl 轮转历史 | 未完成 | 诊断 ZIP 已包含配置、状态、电源快照、powercfg 和日志，但没有原型完整的遥测历史。 |
| 健康状态、失败退避、runtime.json | 已移植 | Agent 5 秒轮询，失败按 10/20/40/60 秒退避，并写入运行时健康记录。 |
| 深色五页“雷云”式 UI | 已移植 | Control panel、Game mode、Settings、Diagnostics、About；产品名已改 OpenSynapse。 |
| 自定义应用/托盘图标 | 已移植 | 使用参考资产复制后的 OpenSynapse 命名 ICO；任务栏使用应用图标，托盘使用独立 ICO。 |
| PerMonitorV2 / AppUserModelID | 已移植 | AppUserModelID 改为 `OpenSynapse.Desktop`。 |
| 登录自动启动 Agent + App | 已移植 | Agent 使用高权限计划任务，App 使用当前用户 Run 项自动启动。 |
| PowerPilot 配置迁移 | 已移植 | 首次启动在 OpenSynapse 配置不存在时读取旧 `%LOCALAPPDATA%\PowerPilot\config.json`，只迁移安全配置，不删除旧数据。 |
| DeathAdder V3 Pro HID | 已保留并验证代码 | VID 1532、PID 00B6/00B7/00C2/00C3、Usage Page 门控、DPI/轮询/固件/序列号/电量查询和写入路径均保留。 |

## 已发现并处理的缺陷

### 固定刷新率近似匹配

原实现会在目标刷新率不存在时选择“低于目标的最近值”，且多屏可能部分应用。现在 `ApplyFixedRefresh` 会先对全部活动显示器做精确预验证，再执行任何变更；没有目标值时明确返回失败，避免静默降级。

### 电源档位切换误改显示链路

2.4.1 的无感切档语义已接入：默认模式切换只应用电源方案和 Quiet 唤醒/CPU维护，不自动改刷新率、HDR、缩放或亮度。Settings 页提供明确的“Apply display now · may blink”按钮；真实显示拓扑变化仍会触发重新应用。

### PowerPilot 命名残留

应用标题、托盘文本、配置/状态目录、AppUserModelID、CLI usage、安装快捷方式和自启动项均使用 OpenSynapse。旧 PowerPilot 配置只作为一次性来源读取，不会删除，避免升级过程中丢失用户数据。

## 雷蛇鼠标检查结论

代码层面：DeathAdder V3 Pro 仍使用 HID feature report，先校验 VID/PID/控制 Usage Page，再执行协议查询或写入；未检测到受支持接口时会返回明确错误，不会向任意 HID 设备发送报文。

现场层面：当前机器此前的只读自测未发现支持的 DeathAdder 设备，因此无法完成有线/无线四个 PID 的真实 DPI、轮询率、固件、电量和写入回读验证。这个限制不是“通过测试”的证据，必须连接真实设备后再执行管理员硬件冒烟。

## 验证结果

- Core tests：38 passed。
- Agent tests：51 passed。
- OpenSynapse.Agent Release/Debug build：0 warning、0 error。
- OpenSynapse.App build：0 warning、0 error。
- `dotnet format --verify-no-changes --no-restore`：通过。
- `scripts/Test-InstallerDefinitions.ps1`：通过。
- 未创建 PR、未推送、未合并 `main`。

最新发布版只读现场检查：HighPowerAc、约 78% 电量、160 W adapter limit、1 个活动显示器、2 个 wake-armed 设备；配置已从 schema 3 升级到 schema 10。SelfTest 为 0 failure、3 warning：当前进程非管理员、没有活动内屏动态刷新路径、未检测到支持的 Razer 设备。

## 尚未能据此宣称的项目

1. 目标 Windows 管理员实机的完整电源/显示/恢复/卸载冒烟；这些操作会真实修改系统设置，本轮只完成代码和自动化验证。
2. Native dynamic refresh 的目标内屏/外屏回读和失败后恢复。
3. DeathAdder V3 Pro 真实设备读写。
4. GPU 负载、独显泄漏、EMA/10 分钟 telemetry 历史。
5. Quiet 进程/厂商服务维护是否作为 OpenSynapse 的正式目标；当前刻意保持不主动停止。
