using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;
using OpenSynapse.Core;
using Controls = System.Windows.Controls;
using Forms = System.Windows.Forms;

namespace OpenSynapse.App;

public partial class MainWindow : Window
{
    private readonly AgentClient agent = new();
    private readonly Forms.NotifyIcon tray;
    private readonly System.Drawing.Icon trayIcon;
    private readonly DispatcherTimer statusTimer;
    private readonly List<ApplicationRule> applicationRules = [];
    private ModeSelection selection = ModeSelection.Auto;
    private bool statusRequestInProgress;
    private bool localAgentStartAttempted;
    private Process? localAgentProcess;
    private bool exiting;

    public MainWindow()
    {
        InitializeComponent();
        InternalScaleBox.ItemsSource = DisplayPolicySettings.AllowedDisplayScales;
        ExternalScaleBox.ItemsSource = DisplayPolicySettings.AllowedDisplayScales;
        RefreshPolicyBox.ItemsSource = Enum.GetValues<RefreshPolicy>();
        RuleProfileBox.ItemsSource = Enum.GetValues<ApplicationRuleProfile>();
        RuleScopeBox.ItemsSource = Enum.GetValues<ApplicationRuleScope>();
        RuleProfileBox.SelectedItem = ApplicationRuleProfile.Performance;
        RuleScopeBox.SelectedItem = ApplicationRuleScope.Foreground;
        var trayIconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "OpenSynapse.Tray.ico");
        trayIcon = File.Exists(trayIconPath)
            ? new System.Drawing.Icon(trayIconPath)
            : System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!)
                ?? System.Drawing.SystemIcons.Application;
        tray = new Forms.NotifyIcon
        {
            Text = "OpenSynapse",
            Icon = trayIcon,
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip()
        };
        tray.DoubleClick += (_, _) => Dispatcher.Invoke(ShowWindow);
        tray.ContextMenuStrip.Items.Add("Open", null, (_, _) => Dispatcher.Invoke(ShowWindow));
        tray.ContextMenuStrip.Items.Add("Exit and restore", null, (_, _) => Dispatcher.Invoke(async () => await ExitAsync()));
        SystemEvents.PowerModeChanged += PowerModeChanged;
        statusTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(3)
        };
        statusTimer.Tick += StatusTimer_Tick;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        UpdatePowerText();
        statusTimer.Start();
        await RefreshAgentAsync();
    }

    private async void StatusTimer_Tick(object? sender, EventArgs e)
    {
        if (statusRequestInProgress || exiting) return;
        await RefreshAsync(logConnectionFailure: false);
    }

    private void PowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode != PowerModes.StatusChange) return;
        Dispatcher.BeginInvoke(async () =>
        {
            UpdatePowerText();
            await RefreshAsync();
        });
    }

    private async void Auto_Click(object sender, RoutedEventArgs e) => await SelectAsync(ModeSelection.Auto);
    private async void Performance_Click(object sender, RoutedEventArgs e) => await SelectAsync(ModeSelection.Performance);
    private async void Balanced_Click(object sender, RoutedEventArgs e) => await SelectAsync(ModeSelection.Balanced);
    private async void Quiet_Click(object sender, RoutedEventArgs e) => await SelectAsync(ModeSelection.Quiet);
    private void DashboardNav_Click(object sender, RoutedEventArgs e) => MainTabs.SelectedIndex = 0;
    private void GameNav_Click(object sender, RoutedEventArgs e) => MainTabs.SelectedIndex = 1;
    private void SettingsNav_Click(object sender, RoutedEventArgs e) => MainTabs.SelectedIndex = 2;
    private void DiagnosticsNav_Click(object sender, RoutedEventArgs e) => MainTabs.SelectedIndex = 3;
    private void AboutNav_Click(object sender, RoutedEventArgs e) => MainTabs.SelectedIndex = 4;
    private void TitleBar_MouseLeftButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            Maximize_Click(sender, e);
            return;
        }
        if (e.LeftButton == System.Windows.Input.MouseButtonState.Pressed) DragMove();
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void Maximize_Click(object sender, RoutedEventArgs e) => WindowState =
        WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void CloseWindow_Click(object sender, RoutedEventArgs e) => Hide();
    private async void Refresh_Click(object sender, RoutedEventArgs e) => await RefreshAsync();
    private async void SelfTest_Click(object sender, RoutedEventArgs e) =>
        await SendAsync(new AgentRequest(AgentOperation.SelfTest));

    private async void ApplyDisplayNow_Click(object sender, RoutedEventArgs e) =>
        await SendAsync(new AgentRequest(AgentOperation.ApplyDisplayPolicyNow));

    private async void ExportDiagnostics_Click(object sender, RoutedEventArgs e) =>
        await SendAsync(new AgentRequest(AgentOperation.ExportDiagnostics));

    private async void TemporaryHyper_Click(object sender, RoutedEventArgs e) => await SetTemporaryAsync(OperatingMode.Performance, 30, false);
    private async void TemporaryBalance_Click(object sender, RoutedEventArgs e) => await SetTemporaryAsync(OperatingMode.Balanced, 30, false);
    private async void TemporaryQuiet_Click(object sender, RoutedEventArgs e) => await SetTemporaryAsync(OperatingMode.Quiet, 30, false);
    private async void TemporaryUntilPower_Click(object sender, RoutedEventArgs e) => await SetTemporaryAsync(OperatingMode.Balanced, null, true);
    private async void ClearTemporary_Click(object sender, RoutedEventArgs e) =>
        await SendAsync(new AgentRequest(AgentOperation.ClearTemporaryMode));

    private async Task SetTemporaryAsync(OperatingMode mode, int? minutes, bool untilPowerChange)
    {
        await SendAsync(new AgentRequest(
            AgentOperation.SetTemporaryMode,
            Mode: mode,
            TemporaryMinutes: minutes,
            TemporaryUntilPowerChange: untilPowerChange));
    }

    private async void AddRule_Click(object sender, RoutedEventArgs e)
    {
        var process = RuleProcessBox.Text.Trim();
        if (process.Length == 0) { Log("Application rule process name is required."); return; }
        if (RuleProfileBox.SelectedItem is not ApplicationRuleProfile profile
            || RuleScopeBox.SelectedItem is not ApplicationRuleScope scope)
        {
            Log("Select an application rule profile and scope.");
            return;
        }
        var rule = new ApplicationRule(process, profile, scope, RuleEnabledCheck.IsChecked == true);
        try { rule.Validate(); }
        catch (InvalidDataException ex) { Log(ex.Message); return; }
        applicationRules.RemoveAll(item => string.Equals(item.ProcessName, process, StringComparison.OrdinalIgnoreCase)
            && item.Scope == scope);
        applicationRules.Add(rule);
        await SendAsync(new AgentRequest(AgentOperation.SetApplicationRules, ApplicationRules: applicationRules));
    }

    private async void RemoveRule_Click(object sender, RoutedEventArgs e)
    {
        var process = RuleProcessBox.Text.Trim();
        applicationRules.RemoveAll(item => string.Equals(item.ProcessName, process, StringComparison.OrdinalIgnoreCase));
        await SendAsync(new AgentRequest(AgentOperation.SetApplicationRules, ApplicationRules: applicationRules));
    }

    private async void SaveDisplayPolicy_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var settings = ReadDisplayPolicy();
            settings.Validate();
            await SendAsync(new AgentRequest(AgentOperation.SetDisplayPolicy, DisplayPolicy: settings));
        }
        catch (Exception ex) when (ex is InvalidDataException or InvalidOperationException)
        {
            Log(ex.Message);
        }
    }

    private async void SaveQuietMaintenance_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var names = QuietWakeDevicesBox.Text
                .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
                .Select(name => name.Trim())
                .Where(name => name.Length > 0)
                .ToArray();
            var settings = new QuietMaintenanceSettings(ManageWakeDevicesCheck.IsChecked == true, names);
            settings.Validate();
            await SendAsync(new AgentRequest(AgentOperation.SetQuietMaintenance, QuietMaintenance: settings));
        }
        catch (InvalidDataException ex)
        {
            Log(ex.Message);
        }
    }

    private async void ApplyDpi_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(DpiBox.Text, out var dpi)) { Log("DPI must be a number."); return; }
        await SendAsync(new AgentRequest(AgentOperation.SetMouseDpi, DpiX: dpi, DpiY: dpi));
    }

    private async void ApplyPolling_Click(object sender, RoutedEventArgs e)
    {
        var value = (PollingBox.SelectedItem as System.Windows.Controls.ComboBoxItem)?.Content?.ToString();
        if (!int.TryParse(value, out var hz)) return;
        await SendAsync(new AgentRequest(AgentOperation.SetMousePollingRate, PollingRate: hz));
    }

    private async Task SelectAsync(ModeSelection value)
    {
        ModeText.Text = $"Selection: {value}";
        DashboardModeText.Text = ModeText.Text;
        if (!await SendAsync(new AgentRequest(AgentOperation.SetSelection, Selection: value)))
            await RefreshAsync();
    }

    private void UpdateModeButtons(ModeSelection activeSelection)
    {
        var buttons = new[]
        {
            (AutoModeButton, ModeSelection.Auto),
            (HyperModeButton, ModeSelection.Performance),
            (BalanceModeButton, ModeSelection.Balanced),
            (QuietModeButton, ModeSelection.Quiet)
        };
        foreach (var (button, mode) in buttons)
        {
            var selected = mode == activeSelection;
            button.Background = selected
                ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(68, 214, 44))
                : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(23, 26, 24));
            button.Foreground = selected
                ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Colors.Black)
                : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Colors.White);
        }
    }

    private async Task<bool> RefreshAsync(bool logConnectionFailure = true) =>
        await SendAsync(new AgentRequest(AgentOperation.Status), logConnectionFailure);

    private async Task RefreshAgentAsync()
    {
        if (await RefreshAsync(logConnectionFailure: false)) return;

        if (!localAgentStartAttempted && TryStartLocalAgent())
        {
            localAgentStartAttempted = true;
            for (var attempt = 0; attempt < 12; attempt++)
            {
                await Task.Delay(500);
                if (await RefreshAsync(logConnectionFailure: false)) return;
            }
        }

        Log("OpenSynapse.Agent is not connected. Start the elevated Agent or run the installed OpenSynapse task.");
    }

    private async Task<bool> SendAsync(AgentRequest request, bool logConnectionFailure = true)
    {
        if (statusRequestInProgress && request.Operation == AgentOperation.Status) return false;
        if (request.Operation == AgentOperation.Status) statusRequestInProgress = true;
        try
        {
            var response = await agent.SendAsync(request);
            SetAgentConnected();
            Log(response.Message);
            foreach (var diagnostic in response.Diagnostics ?? [])
                Log($"{diagnostic.Status}: {diagnostic.Name} — {diagnostic.Message}");
            if (response.Status is not null) UpdateStatus(response.Status);
            return response.Success;
        }
        catch (Exception ex)
        {
            SetAgentDisconnected(ex.Message);
            if (logConnectionFailure) Log(ex.Message);
            return false;
        }
        finally
        {
            if (request.Operation == AgentOperation.Status) statusRequestInProgress = false;
        }
    }

    private void SetAgentConnected()
    {
        if (HealthText.Text == "Agent offline") Log("OpenSynapse.Agent connected; live telemetry is active.");
    }

    private void SetAgentDisconnected(string error)
    {
        HealthText.Text = "Agent offline";
        HealthText.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Colors.Orange);
        DashboardPowerText.Text = "Power: Agent unavailable";
        DashboardModeText.Text = "Selection: —    Target: —    Active: —    Health: Agent offline";
        SmartReasonText.Text = "OpenSynapse Agent is not connected. Starting local Agent or waiting for the installed elevated task…";
        TelemetryText.Text = $"CPU / GPU / foreground unavailable · {error}";
        StatusProfileValue.Text = "Offline";
        StatusCpuValue.Text = "Sampling";
        StatusGpuValue.Text = "Sampling";
        StatusBatteryValue.Text = "Unavailable";
        StatusRateValue.Text = "0 W";
        StatusSupplyValue.Text = "Unavailable";
        StatusDgpuValue.Text = "Unavailable";
        StatusHealthValue.Text = "Offline";
    }

    private bool TryStartLocalAgent()
    {
        var agentPath = FindLocalAgentExecutable();
        if (agentPath is null) return false;
        try
        {
            localAgentProcess = Process.Start(new ProcessStartInfo
            {
                FileName = agentPath,
                Arguments = "serve",
                WorkingDirectory = Path.GetDirectoryName(agentPath)!,
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            });
            Log("OpenSynapse.Agent was not running; requested an elevated local Agent. If UAC was cancelled, start it manually.");
            return localAgentProcess is not null;
        }
        catch (Win32Exception ex)
        {
            Log($"Could not start the elevated Agent: {ex.Message}");
            return false;
        }
        catch (InvalidOperationException ex)
        {
            Log($"Could not start the Agent: {ex.Message}");
            return false;
        }
    }

    private static string? FindLocalAgentExecutable()
    {
        var baseDirectory = new DirectoryInfo(AppContext.BaseDirectory);
        var candidates = new[]
        {
            Path.Combine(baseDirectory.FullName, "..", "Agent", "OpenSynapse.Agent.exe"),
            Path.Combine(baseDirectory.FullName, "..", "..", "..", "..", "OpenSynapse.Agent", "bin", "Debug", "net10.0-windows", "OpenSynapse.Agent.exe"),
            Path.Combine(baseDirectory.FullName, "..", "..", "..", "..", "OpenSynapse.Agent", "bin", "Release", "net10.0-windows", "OpenSynapse.Agent.exe")
        };
        return candidates
            .Select(Path.GetFullPath)
            .FirstOrDefault(File.Exists);
    }

    private void UpdateStatus(AgentStatus status)
    {
        selection = status.Selection;
        var battery = status.BatteryPercent is int percent ? $" / {percent}%" : string.Empty;
        var adapterLimit = status.AdapterLimitWatts is double watts ? $" / {watts:0.#} W GPU limit" : string.Empty;
        var powerText = $"Power: {GetSupplyDisplayName(status.SupplyType)}{battery}{adapterLimit}";
        var modeText = $"Selection: {GetSelectionDisplayName(status.Selection)}   Target: {GetModeDisplayName(status.SmartAutomation?.CurrentMode)}   Active: {GetModeDisplayName(status.ActiveMode)}   Health: {status.Health}";
        PowerText.Text = powerText;
        ModeText.Text = modeText;
        DashboardPowerText.Text = powerText;
        DashboardModeText.Text = modeText;
        HealthText.Text = status.Health.ToString();
        HealthText.Foreground = status.Health == RuntimeHealth.Healthy
            ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(68, 214, 44))
            : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Colors.Orange);
        StatusProfileValue.Text = GetModeDisplayName(status.ActiveMode);
        StatusHealthValue.Text = status.Health.ToString();
        UpdateModeButtons(status.Selection);
        if (status.SmartAutomation is not null)
        {
            SmartReasonText.Text = status.SmartAutomation.Reason;
            if (status.SmartAutomation.CandidateMode is { } candidate)
                SmartReasonText.Text += $" · pending {GetModeDisplayName(candidate)} ({status.SmartAutomation.CandidateSamples} samples)";
        }
        if (status.Telemetry is not null)
        {
            var cpu = status.Telemetry.CpuPercent >= 0 ? $"CPU {status.Telemetry.CpuPercent:0.#}%" : "CPU unavailable";
            var gpu = status.Telemetry.GpuPercent >= 0 ? $"GPU {status.Telemetry.GpuPercent:0.#}%" : "GPU unavailable";
            var dgpu = status.Telemetry.DgpuPercent >= 0
                ? $"dGPU {status.Telemetry.DgpuPercent:0.#}% / {status.Telemetry.DgpuDedicatedMb:0.#} MB"
                : "dGPU unavailable";
            var ema = status.Telemetry.BatteryDischargeEmaWatts is double emaWatts
                ? $"battery EMA {emaWatts:0.#} W"
                : "battery trend unavailable";
            var leak = status.SmartAutomation?.DgpuActivitySuspected == true
                ? $" · dGPU activity suspected ({status.SmartAutomation.DgpuActivityConfidence})"
                : string.Empty;
            TelemetryText.Text = $"{cpu} · {gpu} · {dgpu} · {ema} · foreground {status.Telemetry.ForegroundProcess ?? "none"}{leak}";
            StatusCpuValue.Text = status.Telemetry.CpuPercent >= 0 ? $"{status.Telemetry.CpuPercent:0.#}%" : "Sampling";
            StatusGpuValue.Text = status.Telemetry.GpuPercent >= 0 ? $"{status.Telemetry.GpuPercent:0.#}%" : "Sampling";
            StatusBatteryValue.Text = status.BatteryPercent is int batteryPercent ? $"{batteryPercent}%" : "Unavailable";
            StatusRateValue.Text = status.Telemetry.BatteryDischargeWatts is double discharge && discharge > 0
                ? $"-{discharge:0.#} W"
                : status.Telemetry.BatteryChargeWatts is double charge && charge > 0
                    ? $"+{charge:0.#} W"
                    : "0 W";
            StatusSupplyValue.Text = GetSupplyDisplayName(status.SupplyType);
            StatusDgpuValue.Text = status.SmartAutomation?.DgpuActivitySuspected == true
                ? $"Active ({status.SmartAutomation.DgpuActivityConfidence})"
                : "No leak";
            StatusDgpuValue.Foreground = status.SmartAutomation?.DgpuActivitySuspected == true
                ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Colors.Orange)
                : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Colors.White);
        }
        TemporaryText.Text = status.TemporaryMode is { } temporary
            ? temporary.UntilPowerChange
                ? $"Temporary {GetModeDisplayName(temporary.Mode)} until power changes"
                : $"Temporary {GetModeDisplayName(temporary.Mode)} until {temporary.ExpiresAt?.ToLocalTime():HH:mm}"
            : "No temporary override";
        applicationRules.Clear();
        applicationRules.AddRange(status.ApplicationRules ?? []);
        RulesText.Text = applicationRules.Count == 0
            ? "No custom application rules. Built-in performance/productivity lists remain active."
            : string.Join(Environment.NewLine, applicationRules.Select(rule =>
                $"{rule.ProcessName}  →  {rule.Profile}  ·  {rule.Scope}  ·  {(rule.Enabled ? "enabled" : "disabled")}"));
        var mouse = status.RazerDevices.FirstOrDefault();
        MouseText.Text = mouse is null
            ? "No supported mouse detected. Supported PIDs: 00B6, 00B7, 00C2, 00C3."
            : $"{mouse.Name} ({mouse.Connection})  Firmware {mouse.FirmwareVersion ?? "?"}  "
              + $"DPI {mouse.DpiX?.ToString() ?? "?"}/{mouse.DpiY?.ToString() ?? "?"}  "
              + $"Polling {mouse.PollingRate?.ToString() ?? "?"} Hz  Battery {mouse.BatteryPercent?.ToString() ?? "?"}%";
        if (status.DisplayPolicy is not null) UpdateDisplayPolicy(status.DisplayPolicy);
        if (status.QuietMaintenance is not null) UpdateQuietMaintenance(status.QuietMaintenance);
        WakeArmedText.Text = status.WakeArmedDevices is { Count: > 0 }
            ? string.Join(Environment.NewLine, status.WakeArmedDevices)
            : "No wake-armed devices detected.";
    }

    private DisplayPolicySettings ReadDisplayPolicy() => new(
        ReadInteger(BalancedThresholdBox, "Balanced battery minimum"),
        ManageAdvancedColorCheck.IsChecked == true,
        ManageBrightnessCheck.IsChecked == true,
        ManageScalingCheck.IsChecked == true,
        RefreshPolicyBox.SelectedItem is RefreshPolicy refreshPolicy
            ? refreshPolicy
            : throw new InvalidOperationException("Select a refresh policy."),
        ReadScale(InternalScaleBox, "internal display scale"),
        ReadScale(ExternalScaleBox, "external display scale"),
        ReadInteger(BalancedBrightnessBox, "Balanced brightness"),
        ReadInteger(QuietBrightnessBox, "Quiet brightness"),
        ReadInteger(BalancedRefreshBox, "Balanced refresh rate"),
        ReadInteger(QuietRefreshBox, "Quiet refresh rate"));

    private void UpdateDisplayPolicy(DisplayPolicySettings settings)
    {
        ManageAdvancedColorCheck.IsChecked = settings.ManageAdvancedColor;
        ManageBrightnessCheck.IsChecked = settings.ManageBrightness;
        ManageScalingCheck.IsChecked = settings.ManageDisplayScaling;
        RefreshPolicyBox.SelectedItem = settings.RefreshPolicy;
        InternalScaleBox.SelectedItem = settings.InternalDisplayScalePercent;
        ExternalScaleBox.SelectedItem = settings.ExternalDisplayScalePercent;
        BalancedThresholdBox.Text = settings.BalancedBatteryThresholdPercent.ToString();
        BalancedBrightnessBox.Text = settings.BalancedBrightnessPercent.ToString();
        QuietBrightnessBox.Text = settings.QuietBrightnessPercent.ToString();
        BalancedRefreshBox.Text = settings.BalancedRefreshRateHz.ToString();
        QuietRefreshBox.Text = settings.QuietRefreshRateHz.ToString();
    }

    private void UpdateQuietMaintenance(QuietMaintenanceSettings settings)
    {
        ManageWakeDevicesCheck.IsChecked = settings.ManageWakeDevices;
        QuietWakeDevicesBox.Text = string.Join(Environment.NewLine, settings.WakeDeviceNames);
    }

    private static int ReadScale(Controls.ComboBox box, string name) => box.SelectedItem is int value
        ? value
        : throw new InvalidOperationException($"Select a supported {name}.");

    private static int ReadInteger(Controls.TextBox box, string name) => int.TryParse(box.Text, out var value)
        ? value
        : throw new InvalidDataException($"{name} must be a number.");

    private void UpdatePowerText()
    {
        var source = GetPowerSource() switch
        {
            PowerSource.Ac => "AC",
            PowerSource.Battery => "Battery",
            _ => "Unknown power source"
        };
        PowerText.Text = $"Power: {source}";
        DashboardPowerText.Text = PowerText.Text;
    }

    private static string GetSupplyDisplayName(SupplyType supplyType) => supplyType switch
    {
        SupplyType.HighPowerAc => "280W-class AC",
        SupplyType.LowPowerPd => "USB-C PD",
        SupplyType.UnknownAc => "unverified AC",
        SupplyType.Battery => "Battery",
        _ => "Unknown"
    };

    private static string GetModeDisplayName(OperatingMode? mode) => mode switch
    {
        OperatingMode.Performance => "Hyper",
        OperatingMode.Balanced => "Balance",
        OperatingMode.Quiet => "Quiet",
        _ => "unmanaged"
    };

    private static string GetSelectionDisplayName(ModeSelection mode) => mode switch
    {
        ModeSelection.Auto => "Smart Auto",
        ModeSelection.Performance => "Hyper",
        ModeSelection.Balanced => "Balance",
        ModeSelection.Quiet => "Quiet",
        _ => mode.ToString()
    };

    private static PowerSource GetPowerSource() => GetSystemPowerStatus(out var status)
        ? status.ACLineStatus switch { 1 => PowerSource.Ac, 0 => PowerSource.Battery, _ => PowerSource.Unknown }
        : PowerSource.Unknown;

    private void Log(string message)
    {
        LogBox.AppendText($"{DateTime.Now:HH:mm:ss}  {message}{Environment.NewLine}");
        LogBox.ScrollToEnd();
    }

    private void ShowWindow()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    internal void ActivateFromExternalRequest() => ShowWindow();

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (exiting) return;
        e.Cancel = true;
        Hide();
    }

    private async void Exit_Click(object sender, RoutedEventArgs e) => await ExitAsync();

    private async Task ExitAsync()
    {
        if (exiting) return;
        exiting = true;
        if (!await SendAsync(new AgentRequest(AgentOperation.Shutdown)))
        {
            exiting = false;
            return;
        }
        SystemEvents.PowerModeChanged -= PowerModeChanged;
        statusTimer.Stop();
        tray.Visible = false;
        tray.Dispose();
        trayIcon.Dispose();
        System.Windows.Application.Current.Shutdown();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SYSTEM_POWER_STATUS
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public uint BatteryLifeTime;
        public uint BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll")]
    private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);
}
