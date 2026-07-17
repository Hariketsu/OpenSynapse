using OpenSynapse.Core;
using PowerPilotNative;

namespace OpenSynapse.Agent;

internal sealed class DisplayPolicy
{
    public void CaptureForQuiet(OpenSynapseState state)
    {
        if (state.AdvancedColors.Count == 0)
        {
            try
            {
                state.AdvancedColors = AdvancedColorManager.GetStatus()
                    .Where(item => item.Supported)
                    .Select(item => new AdvancedColorState(item.Key, item.Enabled))
                    .ToList();
            }
            catch { }
        }
        state.OriginalBrightness ??= GetBrightness();
    }

    public void Apply(OperatingMode mode, OpenSynapseState state)
    {
        if (mode == OperatingMode.Quiet)
        {
            CaptureForQuiet(state);
            foreach (var color in state.AdvancedColors)
                try { AdvancedColorManager.SetEnabled(color.Key, false); } catch { }
            _ = SetBrightness(40);
            try { DisplayModeManager.ApplyQuietRefresh(60); } catch { }
        }
        else
        {
            RestoreCapturedDisplayState(state);
            try { DisplayModeManager.ApplyMaximumRefresh(); } catch { }
        }

        try
        {
            foreach (var display in DisplayScaling.GetActiveDisplays())
                try { DisplayScaling.SetScale(display, display.IsInternal ? 150 : 125); } catch { }
        }
        catch { }
    }

    public void Restore(OpenSynapseState state)
    {
        RestoreCapturedDisplayState(state);
        try { DisplayModeManager.RestoreRegistryModes(); } catch { }
    }

    private static void RestoreCapturedDisplayState(OpenSynapseState state)
    {
        foreach (var color in state.AdvancedColors)
            try { AdvancedColorManager.SetEnabled(color.Key, color.Enabled); } catch { }
        try
        {
            var current = AdvancedColorManager.GetStatus().ToDictionary(item => item.Key, item => item.Enabled);
            state.AdvancedColors.RemoveAll(color => current.TryGetValue(color.Key, out var enabled) && enabled == color.Enabled);
        }
        catch { }
        if (state.OriginalBrightness is int brightness)
        {
            if (SetBrightness(brightness)) state.OriginalBrightness = null;
        }
    }

    private static int? GetBrightness()
    {
        try
        {
            var output = RunPowerShell(
                "(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness | Where-Object Active | Select-Object -First 1).CurrentBrightness");
            return int.TryParse(output, out var brightness) ? brightness : null;
        }
        catch { return null; }
    }

    private static bool SetBrightness(int percent)
    {
        try
        {
            RunPowerShell(
                "$methods = @(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods | Where-Object Active); if (-not $methods) { throw 'No active brightness controller.' }; $methods | ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName WmiSetBrightness -Arguments @{Timeout=1;Brightness=[byte]"
                + percent
                + "} | Out-Null }");
            return true;
        }
        catch { return false; }
    }

    private static string RunPowerShell(string command) => ProcessRunner.Run(
        Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        command);
}
