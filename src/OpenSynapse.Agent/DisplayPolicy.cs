using OpenSynapse.Core;
namespace OpenSynapse.Agent;

internal sealed class DisplayPolicy
{
    private readonly IDisplaySystem displaySystem;

    public DisplayPolicy()
        : this(new WindowsDisplaySystem())
    {
    }

    internal DisplayPolicy(IDisplaySystem displaySystem)
    {
        this.displaySystem = displaySystem;
    }

    public int GetActiveDisplayCount() => displaySystem.GetDisplays().Count;

    public void Capture(OperatingMode mode, OpenSynapseState state, OpenSynapseConfig config)
    {
        if (config.ManageDisplayScaling) CaptureDisplayScales(state);
        if (mode != OperatingMode.Performance) CaptureForLowPower(state, config);
    }

    private void CaptureForLowPower(OpenSynapseState state, OpenSynapseConfig config)
    {
        if (config.ManageAdvancedColor)
        {
            try
            {
                var captured = state.AdvancedColors
                    .Select(item => item.Key)
                    .ToHashSet(StringComparer.Ordinal);
                state.AdvancedColors.AddRange(displaySystem.GetAdvancedColors()
                    .Where(item => item.Supported && captured.Add(item.Key))
                    .Select(item => new AdvancedColorState(item.Key, item.Enabled)));
            }
            catch { }
        }
        if (config.ManageBrightness && state.OriginalBrightness is null)
        {
            try { state.OriginalBrightness = displaySystem.GetBrightness(); } catch { }
        }
    }

    public void Apply(
        OperatingMode mode,
        OpenSynapseState state,
        OpenSynapseConfig config,
        bool applyDisplaySettings = true,
        PowerSnapshot? powerSnapshot = null)
    {
        if (!applyDisplaySettings) return;
        if (mode != OperatingMode.Performance)
        {
            CaptureForLowPower(state, config);
            if (config.ManageAdvancedColor)
            {
                foreach (var color in state.AdvancedColors)
                    try { displaySystem.SetAdvancedColor(color.Key, false); } catch { }
            }
            else
            {
                RestoreAdvancedColors(state, clearCompleted: false);
            }
            if (config.ManageBrightness)
            {
                try
                {
                    displaySystem.SetBrightness(ResolveBrightness(mode, config, powerSnapshot));
                }
                catch { }
            }
            else
            {
                RestoreBrightness(state, clearCompleted: false);
            }
        }
        else
        {
            RestoreCapturedDisplayState(state, clearCompleted: false, restoreScales: false);
        }
        ApplyRefreshPolicy(mode, config);

        if (config.ManageDisplayScaling)
        {
            try
            {
                foreach (var display in displaySystem.GetDisplays())
                    try
                    {
                        displaySystem.SetDisplayScale(
                            display.Key,
                            display.IsInternal
                                ? config.InternalDisplayScalePercent
                                : config.ExternalDisplayScalePercent);
                    }
                    catch { }
            }
            catch { }
        }
        else
        {
            RestoreDisplayScales(state, clearCompleted: false);
        }
    }

    public bool Restore(OpenSynapseState state)
    {
        RestoreCapturedDisplayState(state, clearCompleted: true, restoreScales: true);
        var refreshRestored = true;
        try { displaySystem.RestoreRefresh(); }
        catch { refreshRestored = false; }
        return state.AdvancedColors.Count == 0
            && state.DisplayScales.Count == 0
            && state.OriginalBrightness is null
            && refreshRestored;
    }

    private void CaptureDisplayScales(OpenSynapseState state)
    {
        try
        {
            var captured = state.DisplayScales
                .Select(item => item.Key)
                .ToHashSet(StringComparer.Ordinal);
            state.DisplayScales.AddRange(displaySystem.GetDisplays()
                .Where(display => captured.Add(display.Key))
                .Select(display => new DisplayScaleState(display.Key, display.CurrentScalePercent)));
        }
        catch { }
    }

    private void RestoreCapturedDisplayState(OpenSynapseState state, bool clearCompleted, bool restoreScales)
    {
        RestoreAdvancedColors(state, clearCompleted);
        RestoreBrightness(state, clearCompleted);
        if (restoreScales) RestoreDisplayScales(state, clearCompleted);
    }

    private void RestoreAdvancedColors(OpenSynapseState state, bool clearCompleted)
    {
        foreach (var color in state.AdvancedColors)
            try { displaySystem.SetAdvancedColor(color.Key, color.Enabled); } catch { }
        if (clearCompleted)
        {
            try
            {
                var current = displaySystem.GetAdvancedColors().ToDictionary(item => item.Key, item => item.Enabled);
                state.AdvancedColors.RemoveAll(color => current.TryGetValue(color.Key, out var enabled) && enabled == color.Enabled);
            }
            catch { }
        }
    }

    private void RestoreBrightness(OpenSynapseState state, bool clearCompleted)
    {
        if (state.OriginalBrightness is int brightness)
        {
            try { displaySystem.SetBrightness(brightness); } catch { }
            if (clearCompleted)
            {
                try
                {
                    if (displaySystem.GetBrightness() == brightness) state.OriginalBrightness = null;
                }
                catch { }
            }
        }
    }

    private void ApplyRefreshPolicy(OperatingMode mode, OpenSynapseConfig config)
    {
        switch (config.RefreshPolicy)
        {
            case RefreshPolicy.Unmanaged:
                displaySystem.RestoreRefresh();
                break;
            case RefreshPolicy.Maximum:
                displaySystem.ApplyMaximumRefresh();
                break;
            case RefreshPolicy.Fixed60:
                displaySystem.ApplyFixedRefresh(60);
                break;
            case RefreshPolicy.Fixed120:
                displaySystem.ApplyFixedRefresh(120);
                break;
            case RefreshPolicy.Fixed240:
                displaySystem.ApplyFixedRefresh(240);
                break;
            case RefreshPolicy.DynamicNative:
                displaySystem.ApplyDynamicNativeRefresh();
                break;
            case RefreshPolicy.FollowMode when mode == OperatingMode.Performance:
                displaySystem.ApplyMaximumRefresh();
                break;
            case RefreshPolicy.FollowMode:
                displaySystem.ApplyFixedRefresh(
                    mode == OperatingMode.Balanced
                        ? config.BalancedRefreshRateHz
                        : config.QuietRefreshRateHz);
                break;
        }
    }

    private void RestoreDisplayScales(OpenSynapseState state, bool clearCompleted)
    {
        if (state.DisplayScales.Count == 0) return;
        try
        {
            var displays = displaySystem.GetDisplays()
                .ToDictionary(display => display.Key, StringComparer.Ordinal);
            foreach (var captured in state.DisplayScales)
            {
                if (displays.ContainsKey(captured.Key))
                {
                    try { displaySystem.SetDisplayScale(captured.Key, captured.ScalePercent); } catch { }
                }
            }

            if (!clearCompleted) return;
            var current = displaySystem.GetDisplays()
                .ToDictionary(display => display.Key, StringComparer.Ordinal);
            state.DisplayScales.RemoveAll(captured =>
                current.TryGetValue(captured.Key, out var display)
                && display.CurrentScalePercent == captured.ScalePercent);
        }
        catch { }
    }

    private static int ResolveBrightness(
        OperatingMode mode,
        OpenSynapseConfig config,
        PowerSnapshot? powerSnapshot)
    {
        if (mode == OperatingMode.Balanced) return config.BalancedBrightnessPercent;
        var target = config.QuietBrightnessPercent;
        if (!config.AdaptiveQuietBrightness || powerSnapshot?.Source != PowerSource.Battery)
            return target;
        var battery = powerSnapshot.BatteryPercent;
        var upperBound = battery is < 20 ? 20 : battery is < 50 ? 30 : 35;
        return Math.Min(target, upperBound);
    }
}
