# OpenSynapse 2.4.1 重新移植验证报告

验证日期：2026-07-25
分支：`dev-echo`
参考：`ref/PowerPilot2.4.1`

## 结论

发布运行时已重新建立在 PowerPilot 2.4.1 的单进程 PowerShell 5.1/WinForms 实现上，不再依赖 WPF、独立 Agent 或命名管道。PowerPilot 配置和系统状态已安全接管，OpenSynapse 计划任务、托盘进程、电源计划、快捷方式和 UI 均可正常运行。

## 自动测试

- PowerShell 文件解析：通过；
- 非破坏性脚本/定义测试：20/20 通过；
- 配置迁移：PowerPilot v1–v10、旧 .NET schema 10、中断接管文档均通过；
- Razer HID：4 个白名单 PID、DPI/轮询率报告构造、事务和校验和通过；
- .NET 历史回归：Core 38/38、Agent 52/52；
- Release 构建：0 警告、0 错误；
- `dotnet format --verify-no-changes`：通过；
- 发布包自检与原生 C# 动态编译：通过。

## 真实安装验证

安装态测试 `Test-LiveInstallation.ps1` 已通过：

- 版本：2.4.1；
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
- Settings 已包含 DeathAdder V3 Pro HID 控制区。

## 硬件验证边界

当前机器没有连接受支持的 DeathAdder V3 Pro 控制接口，因此设备发现结果为 0。系统中的 Razer PID `02C6` 是 Razer Blade 16（2025）内置键盘，不会加入鼠标白名单。

因此本轮可以确认：

- HID 枚举过滤不会误操作内置键盘或其他设备；
- DPI/轮询率请求格式和响应校验正确；
- 未连接白名单鼠标时 UI 安全禁用写入。

仍需连接 PID `00B6/00B7/00C2/00C3` 的 DeathAdder V3 Pro 后，完成真实 DPI、轮询率、固件、电量与充电状态回读闭环。测试鼠标写入时应先退出 Razer Synapse，避免两个用户态控制程序竞争同一接口。
