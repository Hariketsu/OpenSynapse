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

    public void Capture(OperatingMode mode, OpenSynapseState state)
    {
        CaptureDisplayScales(state);
        if (mode != OperatingMode.Performance) CaptureForLowPower(state);
    }

    private void CaptureForLowPower(OpenSynapseState state)
    {
        if (state.AdvancedColors.Count == 0)
        {
            try
            {
                state.AdvancedColors = displaySystem.GetAdvancedColors()
                    .Where(item => item.Supported)
                    .Select(item => new AdvancedColorState(item.Key, item.Enabled))
                    .ToList();
            }
            catch { }
        }
        if (state.OriginalBrightness is null)
        {
            try { state.OriginalBrightness = displaySystem.GetBrightness(); } catch { }
        }
    }

    public void Apply(OperatingMode mode, OpenSynapseState state)
    {
        if (mode != OperatingMode.Performance)
        {
            CaptureForLowPower(state);
            foreach (var color in state.AdvancedColors)
                try { displaySystem.SetAdvancedColor(color.Key, false); } catch { }
            try { displaySystem.SetBrightness(mode == OperatingMode.Balanced ? 60 : 40); } catch { }
            try { displaySystem.ApplyFixedRefresh(mode == OperatingMode.Balanced ? 120 : 60); } catch { }
        }
        else
        {
            RestoreCapturedDisplayState(state, clearCompleted: false, restoreScales: false);
            try { displaySystem.ApplyMaximumRefresh(); } catch { }
        }

        try
        {
            foreach (var display in displaySystem.GetDisplays())
                try { displaySystem.SetDisplayScale(display.Key, display.IsInternal ? 150 : 125); } catch { }
        }
        catch { }
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
        if (state.DisplayScales.Count != 0) return;
        try
        {
            state.DisplayScales = displaySystem.GetDisplays()
                .Select(display => new DisplayScaleState(display.Key, display.CurrentScalePercent))
                .ToList();
        }
        catch { }
    }

    private void RestoreCapturedDisplayState(OpenSynapseState state, bool clearCompleted, bool restoreScales)
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
        if (restoreScales) RestoreDisplayScales(state, clearCompleted);
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
}
