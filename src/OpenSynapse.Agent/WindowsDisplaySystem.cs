using PowerPilotNative;

namespace OpenSynapse.Agent;

internal sealed record AdvancedColorSnapshot(string Key, bool Supported, bool Enabled);
internal sealed record ActiveDisplaySnapshot(string Key, int CurrentScalePercent, bool IsInternal);

internal interface IDisplaySystem
{
    IReadOnlyList<AdvancedColorSnapshot> GetAdvancedColors();
    void SetAdvancedColor(string key, bool enabled);
    int? GetBrightness();
    void SetBrightness(int percent);
    IReadOnlyList<ActiveDisplaySnapshot> GetDisplays();
    void SetDisplayScale(string key, int desiredPercent);
    void ApplyMaximumRefresh();
    void ApplyFixedRefresh(int targetHz);
    void ApplyDynamicNativeRefresh();
    void RestoreRefresh();
}

internal sealed class WindowsDisplaySystem : IDisplaySystem
{
    public IReadOnlyList<AdvancedColorSnapshot> GetAdvancedColors() => AdvancedColorManager.GetStatus()
        .Select(item => new AdvancedColorSnapshot(item.Key, item.Supported, item.Enabled))
        .ToArray();

    public void SetAdvancedColor(string key, bool enabled) =>
        _ = AdvancedColorManager.SetEnabled(key, enabled);

    public int? GetBrightness()
    {
        var output = RunPowerShell(
            "(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness | Where-Object Active | Select-Object -First 1).CurrentBrightness");
        return int.TryParse(output, out var brightness) ? brightness : null;
    }

    public void SetBrightness(int percent) => RunPowerShell(
        "$methods = @(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods | Where-Object Active); if (-not $methods) { throw 'No active brightness controller.' }; $methods | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName WmiSetBrightness -Arguments @{Timeout=1;Brightness=[byte]"
        + percent
        + "} | Out-Null }");

    public IReadOnlyList<ActiveDisplaySnapshot> GetDisplays() => DisplayScaling.GetActiveDisplays()
        .Select(display => new ActiveDisplaySnapshot(display.Key, display.CurrentPercent, display.IsInternal))
        .ToArray();

    public void SetDisplayScale(string key, int desiredPercent)
    {
        var display = DisplayScaling.GetActiveDisplays()
            .SingleOrDefault(item => string.Equals(item.Key, key, StringComparison.Ordinal));
        if (display is null) throw new InvalidOperationException($"Display {key} is no longer active.");
        _ = DisplayScaling.SetScale(display, desiredPercent);
    }

    public void ApplyMaximumRefresh() => _ = DynamicRefreshManager.ApplyInternalMaximumRefresh();

    public void ApplyFixedRefresh(int targetHz) => _ = DynamicRefreshManager.ApplyProfileRefresh(targetHz);

    public void ApplyDynamicNativeRefresh() => _ = DynamicRefreshManager.EnableWindowsDynamic();

    public void RestoreRefresh() => DynamicRefreshManager.RestoreInternalRegistryModes();

    private static string RunPowerShell(string command) => ProcessRunner.Run(
        Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        command);
}
