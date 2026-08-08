# OpenSynapse 0.2.0-preview.1

OpenSynapse 是 Windows 电源、显示与 Razer HID 控制程序。发布版使用单进程 PowerShell 5.1/WinForms 架构，并将产品名、任务、目录、快捷方式和 AppUserModelID 统一为 OpenSynapse。

## 功能

- Auto、Hyper、Balance、Quiet 电源模式；
- 280W 高功率 AC、USB-C PD、电池和未知 AC 分类；
- CPU/GPU、前台/全屏应用、应用规则与迟滞驱动的 Smart Auto；
- 临时模式、Quiet 后台维护与唤醒设备管理；
- HDR、亮度、显示缩放和刷新率策略；
- 电池、GPU、dGPU 活动、运行健康与诊断导出；
- 五页深色 UI、自绘可拖动标题栏、托盘与开始菜单快捷方式；
- DeathAdder V3 Pro 状态、DPI 与标准接收器轮询率控制。

OpenSynapse 只使用公开 Windows 接口和标准 HID feature report。它不写 Razer EC，不控制风扇、TGP 或 MUX，也不安装或替换内核驱动。

## 离电 Quiet 策略

Smart Auto 在电池或 USB-C PD 下以 Quiet 为低负载基线，电量不低于 Balance 安全阈值且应用、CPU 或 GPU 负载持续满足条件时可以临时升到 Balance。手动选择 Quiet 后，Quiet 是强制档位，不会被自动决策切换到 Balance；当运行时确认 280W 级适配器刚接入时，手动 Quiet 锁定会解除并恢复 Auto。已经连接 280W 适配器时再次手动选择 Quiet，仍会保持手动锁定，直到下一次实际适配器接入事件。

Ryzen AI 9 365 的 Quiet DC 曲线会同步应用到第 0/1/2 类处理器：电量不低于 70% 时最大状态 65%、EPP 90；30–69% 时为 60%、EPP 95；低于 30% 时为 50%、EPP 100。长、短线程均优先高效核心。该策略不修改 OEM 异构核心增减阈值、TGP、风扇或 EC。

Quiet 关闭 NVIDIA Overlay 等高耗电辅助进程后，如果检测到它在 10 分钟内自动重启，OpenSynapse 会停止反复结束该进程，进入 30 分钟冷却并显示托盘提示。若希望它持续关闭，应在对应软件中禁用 Overlay 自动启动。

## 安装

解压后双击 `Install-OpenSynapse.cmd`，或在 PowerShell 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\OpenSynapse.ps1 -Mode Install
```

确认 UAC 后，安装器会：

1. 清理旧的 OpenSynapse 运行时并保留可恢复状态；
2. 将已有的本地配置迁移到当前格式；
3. 安装到 `%ProgramFiles%\OpenSynapse`；
4. 注册延迟 30 秒、当前用户、最高权限的 `OpenSynapse` 计划任务；
5. 创建开始菜单快捷方式并启动托盘。

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

配置和状态采用原子替换并保留备份。旧格式文件和迁移记录会以独立文件归档，避免被新运行时误读。

遥测历史 schema 2 包含实际档位 `ActiveProfile`、剩余容量 `BatteryRemainingMwh`、电池电压 `BatteryVoltageMv` 和平滑续航估算 `EstimatedHours`。

详见 `TEST-REPORT.md`。
