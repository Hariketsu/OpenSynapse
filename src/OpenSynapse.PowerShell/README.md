# OpenSynapse 2.5.0

OpenSynapse 是基于 PowerPilot 2.4.1 重新移植的 Windows 电源、显示与 Razer HID 控制程序。发布版保留原型已验证的单进程 PowerShell 5.1/WinForms 架构，并将产品名、任务、目录、快捷方式和 AppUserModelID 全部更名为 OpenSynapse。

## 功能

- Auto、Hyper、Balance、Eco 与锁定式 Experiment 电源模式（兼容配置内部仍使用 `Quiet` 枚举）；
- 280W 高功率 AC、USB-C PD、电池和未知 AC 分类；
- CPU/GPU、前台/全屏应用、应用规则与迟滞驱动的 Smart Auto；
- 临时模式、Eco 后台维护与唤醒设备管理；
- HDR、逐屏 WMI/DDC 亮度、ICC、显示缩放和供电感知内屏 Auto 刷新率（离电/PD 动态 60–240 Hz、280W 固定 240 Hz、手动 Eco 60 Hz/固定 240 Hz）；
- 电池、GPU/NPU 可用性、温度/节流、屏幕状态、dGPU 活动、离电高耗电进程提示、运行健康与诊断导出；
- Experiment 环境锁、漂移修复及 JSON/HTML/SHA-256 实验报告；
- 五页深色 UI、自绘可拖动标题栏、托盘与开始菜单快捷方式；
- DeathAdder V3 Pro 状态、DPI 与标准接收器轮询率控制。

OpenSynapse 只使用公开 Windows 接口和标准 HID feature report。它不写 Razer EC，不控制风扇、TGP 或 MUX，也不安装或替换内核驱动。

## 离电 Eco 策略

Smart Auto 在电池或 USB-C PD 下以 Eco 为低负载基线，电量不低于 Balance 安全阈值且应用、CPU 或 GPU 负载持续满足条件时可以临时升到 Balance。手动选择 Eco 后，Eco 是强制档位，不会被自动决策切换到 Balance；内屏固定 60 Hz、HDR/Advanced Color 关闭。当运行时确认 280W 级适配器刚接入时，Eco 锁定会解除并恢复 Auto 与内屏 240 Hz。已经连接 280W 适配器时再次手动选择 Eco，仍会保持手动锁定，直到下一次实际适配器接入事件。

Ryzen AI 9 365 的 Eco DC 曲线会同步应用到第 0/1/2 类处理器：电量不低于 70% 时最大状态 65%、EPP 90；30–69% 时为 60%、EPP 95；低于 30% 时为 50%、EPP 100。Boost 保持关闭，长、短线程均优先高效核心。该策略不修改 OEM 异构核心增减阈值、TGP、风扇或 EC。

Eco 关闭 NVIDIA Overlay 等高耗电辅助进程后，如果检测到它在 10 分钟内自动重启，OpenSynapse 会停止反复结束该进程，进入 30 分钟冷却并显示托盘提示。若希望它持续关闭，应在对应软件中禁用 Overlay 自动启动。

离电主循环按负载动态使用 10 或 15 秒，外接供电保持 5 秒。独立的 30 秒进程 CPU 增量采样需要连续 2 次达到单核 15% 且平均放电不低于 14 W 才提示，提示冷却 30 分钟；此路径只提供证据，不会结束任何进程。

## 安装

解压后双击 `Install-OpenSynapse.cmd`，或在 PowerShell 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode Install
```

确认 UAC 后，安装器会：

1. 恢复并清理旧的 WPF/Agent OpenSynapse；
2. 如检测到 PowerPilot，归档其配置/状态并调用原卸载入口恢复 Windows；
3. 将 PowerPilot 配置提升为 OpenSynapse 配置；
4. 安装到 `%ProgramFiles%\OpenSynapse`；
5. 注册延迟 30 秒、当前用户、最高权限的 `OpenSynapse` 计划任务；
6. 创建开始菜单快捷方式并启动托盘。

关闭窗口只会隐藏控制面板，自动化仍在托盘中运行。要完整退出并恢复状态，请在 About 页点击 `Exit and restore`，或运行 `Uninstall-OpenSynapse.cmd`。

## 命令

```powershell
# 状态
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode Status

# 不改系统的自检
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode SelfTest

# 打开已安装控制面板
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode Open
```

## Razer 鼠标边界

鼠标控制仅允许 Razer VID `1532`、DeathAdder V3 Pro PID `00B6/00B7/00C2/00C3` 和 HID Usage Page `0x0C`。DPI 范围为 100–30000；标准接收器轮询率为 125/500/1000 Hz。

未检测到白名单设备时写入按钮不会向其他 Razer 设备发送命令。Razer Blade 16（2025）的内置键盘 PID `02C6` 不属于鼠标白名单。

## 数据与恢复

- 配置：`%LOCALAPPDATA%\OpenSynapse\config.json`
- 回滚状态：`%LOCALAPPDATA%\OpenSynapse\state.json`
- 运行记录：`%LOCALAPPDATA%\OpenSynapse\runtime.json`
- 日志：`%LOCALAPPDATA%\OpenSynapse\OpenSynapse.log`
- 遥测历史：`%LOCALAPPDATA%\OpenSynapse\telemetry.jsonl`
- 实验环境报告：`%LOCALAPPDATA%\OpenSynapse\experiment-reports`

配置和状态采用原子替换并保留备份。旧 .NET schema-10 文件和 PowerPilot 接管记录会以独立迁移文件归档，避免被新运行时误读。

遥测历史 schema 6 包含实际档位 `ActiveProfile`、剩余容量 `BatteryRemainingMwh`、电池电压 `BatteryVoltageMv`、平滑续航估算 `EstimatedHours`，以及 GPU/NPU 可用性、温度/节流、逐屏模式/ICC/HDR/DRR/缩放/亮度、刷新策略、主循环周期和离电高耗电进程证据。离电硬件与显示状态最多每 60 秒采样一次，闲置 dGPU 不会被自动实验报告唤醒。

供电分类只有在读数不高于 85 W 时才视为强 PD 证据，并从任意启动档位统一经过 30 秒预热和三次间隔采样；一次不低于 130 W 的读数仍会立即确认 280W 级适配器。外屏默认保持当前分辨率支持的最高刷新率；内屏 Auto 在离电/PD/未确认 AC 使用原生 60–240 Hz 动态刷新，确认 280W 后固定 240 Hz。手动固定 60/240 Hz 在新接入外部供电时恢复 Auto；动态刷新应用或回读验证失败时，内屏安全回退到 Eco 60 Hz。

详见 `TEST-REPORT.md`。
