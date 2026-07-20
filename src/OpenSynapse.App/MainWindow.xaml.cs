using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.Win32;
using OpenSynapse.Core;
using Controls = System.Windows.Controls;
using Forms = System.Windows.Forms;

namespace OpenSynapse.App;

public partial class MainWindow : Window
{
    private readonly AgentClient agent = new();
    private readonly Forms.NotifyIcon tray;
    private ModeSelection selection = ModeSelection.Auto;
    private bool exiting;

    public MainWindow()
    {
        InitializeComponent();
        InternalScaleBox.ItemsSource = DisplayPolicySettings.AllowedDisplayScales;
        ExternalScaleBox.ItemsSource = DisplayPolicySettings.AllowedDisplayScales;
        RefreshPolicyBox.ItemsSource = Enum.GetValues<RefreshPolicy>();
        tray = new Forms.NotifyIcon
        {
            Text = "OpenSynapse",
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip()
        };
        tray.DoubleClick += (_, _) => Dispatcher.Invoke(ShowWindow);
        tray.ContextMenuStrip.Items.Add("Open", null, (_, _) => Dispatcher.Invoke(ShowWindow));
        tray.ContextMenuStrip.Items.Add("Exit and restore", null, (_, _) => Dispatcher.Invoke(async () => await ExitAsync()));
        SystemEvents.PowerModeChanged += PowerModeChanged;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        UpdatePowerText();
        await RefreshAsync();
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
    private async void Refresh_Click(object sender, RoutedEventArgs e) => await RefreshAsync();
    private async void SelfTest_Click(object sender, RoutedEventArgs e) =>
        await SendAsync(new AgentRequest(AgentOperation.SelfTest));

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
        if (!await SendAsync(new AgentRequest(AgentOperation.SetSelection, Selection: value)))
            await RefreshAsync();
    }

    private async Task RefreshAsync() => await SendAsync(new AgentRequest(AgentOperation.Status));

    private async Task<bool> SendAsync(AgentRequest request)
    {
        try
        {
            var response = await agent.SendAsync(request);
            Log(response.Message);
            foreach (var diagnostic in response.Diagnostics ?? [])
                Log($"{diagnostic.Status}: {diagnostic.Name} — {diagnostic.Message}");
            if (response.Status is not null) UpdateStatus(response.Status);
            return response.Success;
        }
        catch (Exception ex)
        {
            Log(ex.Message);
            return false;
        }
    }

    private void UpdateStatus(AgentStatus status)
    {
        selection = status.Selection;
        var battery = status.BatteryPercent is int percent ? $" / {percent}%" : string.Empty;
        var adapterLimit = status.AdapterLimitWatts is double watts ? $" / {watts:0.#} W GPU limit" : string.Empty;
        PowerText.Text = $"Power: {GetSupplyDisplayName(status.SupplyType)}{battery}{adapterLimit}";
        ModeText.Text = $"Selection: {status.Selection}   Active: {status.ActiveMode?.ToString() ?? "unmanaged"}";
        var mouse = status.RazerDevices.FirstOrDefault();
        MouseText.Text = mouse is null
            ? "No supported mouse detected. Supported PIDs: 00B6, 00B7, 00C2, 00C3."
            : $"{mouse.Name} ({mouse.Connection})  Firmware {mouse.FirmwareVersion ?? "?"}  "
              + $"DPI {mouse.DpiX?.ToString() ?? "?"}/{mouse.DpiY?.ToString() ?? "?"}  "
              + $"Polling {mouse.PollingRate?.ToString() ?? "?"} Hz  Battery {mouse.BatteryPercent?.ToString() ?? "?"}%";
        if (status.DisplayPolicy is not null) UpdateDisplayPolicy(status.DisplayPolicy);
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

    private static int ReadScale(Controls.ComboBox box, string name) => box.SelectedItem is int value
        ? value
        : throw new InvalidOperationException($"Select a supported {name}.");

    private static int ReadInteger(Controls.TextBox box, string name) => int.TryParse(box.Text, out var value)
        ? value
        : throw new InvalidDataException($"{name} must be a number.");

    private void UpdatePowerText() => PowerText.Text = $"Power: {GetPowerSource()}";

    private static string GetSupplyDisplayName(SupplyType supplyType) => supplyType switch
    {
        SupplyType.HighPowerAc => "verified high-power AC",
        SupplyType.LowPowerPd => "USB-C PD / low-power AC",
        SupplyType.UnknownAc => "AC (unverified)",
        SupplyType.Battery => "battery",
        _ => "unknown"
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
        tray.Visible = false;
        tray.Dispose();
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
