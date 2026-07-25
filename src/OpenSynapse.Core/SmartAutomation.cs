namespace OpenSynapse.Core;

public enum ApplicationRuleProfile
{
    Performance,
    Balanced,
    Quiet
}

public enum ApplicationRuleScope
{
    Foreground,
    Fullscreen,
    Running
}

public enum HyperCpuPolicy
{
    Sustained,
    Latency
}

public sealed record ApplicationRule(
    string ProcessName,
    ApplicationRuleProfile Profile,
    ApplicationRuleScope Scope,
    bool Enabled = true)
{
    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(ProcessName)
            || ProcessName.Length > 128
            || ProcessName.Any(char.IsControl)
            || !string.Equals(ProcessName, ProcessName.Trim(), StringComparison.Ordinal))
            throw new InvalidDataException("Application rule process names must contain 1 to 128 printable characters.");
        if (!Enum.IsDefined(Profile))
            throw new InvalidDataException($"Unsupported application rule profile {Profile}.");
        if (!Enum.IsDefined(Scope))
            throw new InvalidDataException($"Unsupported application rule scope {Scope}.");
    }

    public string NormalizedProcessName => ProcessName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
        ? ProcessName[..^4]
        : ProcessName;
}

public sealed record SmartAutomationSettings(
    bool Enabled = true,
    int HighPowerCpuEnterPercent = 45,
    int HighPowerCpuExitPercent = 25,
    int PortableCpuEnterPercent = 35,
    int PortableCpuExitPercent = 18,
    int LoadEnterSamples = 3,
    int AppEnterSamples = 2,
    int ExitSamples = 12,
    int MinimumDwellSeconds = 30,
    int AppCpuFloorPercent = 8,
    int GpuEnterPercent = 20,
    int GpuExitPercent = 5,
    int FullscreenCpuFloorPercent = 15,
    int FullscreenGpuFloorPercent = 15,
    int BalancedBatteryThresholdPercent = 50,
    IReadOnlyList<string>? HyperProcessNames = null,
    IReadOnlyList<string>? BalanceProcessNames = null,
    IReadOnlyList<string>? IgnoredFullscreenProcesses = null,
    IReadOnlyList<ApplicationRule>? ApplicationRules = null)
{
    public void Validate()
    {
        ValidateRange(HighPowerCpuEnterPercent, 10, 100, nameof(HighPowerCpuEnterPercent));
        ValidateRange(HighPowerCpuExitPercent, 0, HighPowerCpuEnterPercent - 1, nameof(HighPowerCpuExitPercent));
        ValidateRange(PortableCpuEnterPercent, 10, 100, nameof(PortableCpuEnterPercent));
        ValidateRange(PortableCpuExitPercent, 0, PortableCpuEnterPercent - 1, nameof(PortableCpuExitPercent));
        ValidateRange(LoadEnterSamples, 1, 12, nameof(LoadEnterSamples));
        ValidateRange(AppEnterSamples, 1, 6, nameof(AppEnterSamples));
        ValidateRange(ExitSamples, 2, 60, nameof(ExitSamples));
        ValidateRange(MinimumDwellSeconds, 0, 600, nameof(MinimumDwellSeconds));
        ValidateRange(AppCpuFloorPercent, 0, 100, nameof(AppCpuFloorPercent));
        ValidateRange(GpuEnterPercent, 1, 100, nameof(GpuEnterPercent));
        ValidateRange(GpuExitPercent, 0, GpuEnterPercent - 1, nameof(GpuExitPercent));
        ValidateRange(FullscreenCpuFloorPercent, 1, 100, nameof(FullscreenCpuFloorPercent));
        ValidateRange(FullscreenGpuFloorPercent, 1, 100, nameof(FullscreenGpuFloorPercent));
        ValidateRange(BalancedBatteryThresholdPercent, 0, 100, nameof(BalancedBatteryThresholdPercent));
        ValidateNames(HyperProcessNames, nameof(HyperProcessNames));
        ValidateNames(BalanceProcessNames, nameof(BalanceProcessNames));
        ValidateNames(IgnoredFullscreenProcesses, nameof(IgnoredFullscreenProcesses));
        foreach (var rule in ApplicationRules ?? []) rule.Validate();
        if ((ApplicationRules ?? []).Count > 64)
            throw new InvalidDataException("At most 64 application rules can be configured.");
    }

    private static void ValidateRange(int value, int minimum, int maximum, string name)
    {
        if (value is < 0 || value < minimum || value > maximum)
            throw new InvalidDataException($"{name} must be between {minimum} and {maximum}.");
    }

    private static void ValidateNames(IReadOnlyList<string>? values, string name)
    {
        if (values is null) return;
        if (values.Count > 64) throw new InvalidDataException($"{name} has too many entries.");
        foreach (var value in values)
        {
            if (string.IsNullOrWhiteSpace(value) || value.Length > 128 || value.Any(char.IsControl))
                throw new InvalidDataException($"{name} contains an invalid process name.");
        }
    }
}

public sealed record SmartAutomationInput(
    SupplyType SupplyType,
    int? BatteryPercent,
    double CpuPercent,
    double GpuPercent,
    string? ForegroundProcess,
    bool ForegroundFullscreen,
    bool SessionLocked,
    IReadOnlyList<string>? RunningProcesses = null);

public sealed class SmartAutomationState
{
    public OperatingMode? CurrentMode { get; set; }
    public OperatingMode? CandidateMode { get; set; }
    public int CandidateSamples { get; set; }
    public DateTimeOffset LastTransitionAt { get; set; } = DateTimeOffset.MinValue;
    public SupplyType LastSupplyType { get; set; } = SupplyType.Unknown;
    public string LastReason { get; set; } = "waiting for first telemetry sample";
    public string? MatchedRule { get; set; }
    public int DgpuLeakSamples { get; set; }
    public bool DgpuActivitySuspected { get; set; }
    public string DgpuActivityConfidence { get; set; } = "None";
    public List<GpuConsumerSnapshot> DgpuConsumers { get; set; } = [];
}

public sealed record SmartAutomationDecision(
    OperatingMode Mode,
    bool Changed,
    string Reason,
    string? MatchedRule,
    int CandidateSamples);

public sealed record TemporaryModeState(
    OperatingMode Mode,
    DateTimeOffset? ExpiresAt,
    bool UntilPowerChange,
    SupplyType StartedSupplyType);

public static class SmartAutomationEngine
{
    public static SmartAutomationDecision Evaluate(
        SmartAutomationInput input,
        SmartAutomationSettings settings,
        SmartAutomationState state,
        DateTimeOffset now)
    {
        settings.Validate();
        var baseline = GetBaseline(input, settings);
        var rule = ResolveRule(input, settings);
        var requested = baseline;
        var reason = baseline == OperatingMode.Balanced
            ? "HighPowerAC baseline is Balance"
            : "portable or unverified supply baseline is Quiet";

        if (input.SessionLocked)
        {
            reason = "session is locked; automatic performance promotion is disabled";
        }
        else if (baseline == OperatingMode.Balanced)
        {
            var performanceApp = rule?.Profile == ApplicationRuleProfile.Performance;
            var fullscreenLoad = input.ForegroundFullscreen
                && !IsIgnoredFullscreen(input.ForegroundProcess, settings)
                && AtLeast(input.CpuPercent, settings.FullscreenCpuFloorPercent)
                && AtLeast(input.GpuPercent, settings.FullscreenGpuFloorPercent);
            var highLoad = AtLeast(input.CpuPercent, settings.HighPowerCpuEnterPercent)
                || AtLeast(input.GpuPercent, settings.GpuEnterPercent);
            if (performanceApp || fullscreenLoad || highLoad)
            {
                requested = OperatingMode.Performance;
                reason = performanceApp
                    ? $"performance application rule matched: {rule!.ProcessName}"
                    : fullscreenLoad
                        ? "unlisted fullscreen application crossed CPU and GPU floors"
                        : "HighPowerAC load crossed the promotion threshold";
            }
        }
        else if (input.BatteryPercent is >= 50 && rule?.Profile == ApplicationRuleProfile.Balanced
                 && AtLeast(input.CpuPercent, settings.AppCpuFloorPercent))
        {
            requested = OperatingMode.Balanced;
            reason = $"portable productivity rule matched: {rule!.ProcessName}";
        }
        else if (input.BatteryPercent is >= 50 && AtLeast(input.CpuPercent, settings.PortableCpuEnterPercent))
        {
            requested = OperatingMode.Balanced;
            reason = "portable CPU load crossed the Balance threshold";
        }

        if (input.BatteryPercent is not null && input.BatteryPercent < settings.BalancedBatteryThresholdPercent)
        {
            requested = OperatingMode.Quiet;
            reason = "battery is below the Balance safety threshold";
        }

        if (state.CurrentMode is null)
        {
            state.CurrentMode = baseline;
            state.LastTransitionAt = now;
            state.LastSupplyType = input.SupplyType;
            state.LastReason = reason;
            state.MatchedRule = rule?.ProcessName;
            return new SmartAutomationDecision(baseline, true, reason, rule?.ProcessName, 0);
        }

        var current = state.CurrentMode.Value;
        var supplyBecameLessCapable = current == OperatingMode.Performance
            && requested != OperatingMode.Performance;
        var safetyOverride = requested == OperatingMode.Quiet
            && (input.BatteryPercent is < 50 || input.SupplyType != SupplyType.HighPowerAc);
        var exitSignal = current switch
        {
            OperatingMode.Performance => !AtLeast(input.CpuPercent, settings.HighPowerCpuExitPercent)
                && !AtLeast(input.GpuPercent, settings.GpuExitPercent),
            OperatingMode.Balanced => !AtLeast(input.CpuPercent, settings.PortableCpuExitPercent),
            _ => false
        };
        var desiredDifferent = requested != current;
        var requiredSamples = desiredDifferent
            ? requested == OperatingMode.Performance
                ? rule?.Profile == ApplicationRuleProfile.Performance
                    ? settings.AppEnterSamples
                    : settings.LoadEnterSamples
                : requested == OperatingMode.Balanced
                    ? rule?.Profile == ApplicationRuleProfile.Balanced
                        && AtLeast(input.CpuPercent, settings.AppCpuFloorPercent)
                            ? settings.AppEnterSamples
                            : settings.LoadEnterSamples
                    : exitSignal ? settings.ExitSamples : settings.AppEnterSamples
            : 0;

        if (!desiredDifferent)
        {
            state.CandidateMode = null;
            state.CandidateSamples = 0;
        }
        else if (safetyOverride || supplyBecameLessCapable)
        {
            state.CandidateMode = requested;
            state.CandidateSamples = requiredSamples;
        }
        else if (state.CandidateMode == requested)
        {
            state.CandidateSamples++;
        }
        else
        {
            state.CandidateMode = requested;
            state.CandidateSamples = 1;
        }

        var dwellElapsed = now - state.LastTransitionAt >= TimeSpan.FromSeconds(settings.MinimumDwellSeconds);
        var canTransition = desiredDifferent
            && (safetyOverride || supplyBecameLessCapable || dwellElapsed)
            && state.CandidateSamples >= requiredSamples;
        if (canTransition)
        {
            state.CurrentMode = requested;
            state.LastTransitionAt = now;
            state.CandidateMode = null;
            state.CandidateSamples = 0;
            state.LastSupplyType = input.SupplyType;
            state.LastReason = reason;
            state.MatchedRule = rule?.ProcessName;
            return new SmartAutomationDecision(requested, true, reason, rule?.ProcessName, 0);
        }

        state.LastSupplyType = input.SupplyType;
        state.LastReason = current == OperatingMode.Performance && exitSignal
            ? "performance exit hysteresis is collecting samples"
            : reason;
        state.MatchedRule = rule?.ProcessName;
        return new SmartAutomationDecision(current, false, state.LastReason, rule?.ProcessName, state.CandidateSamples);
    }

    private static OperatingMode GetBaseline(SmartAutomationInput input, SmartAutomationSettings settings) =>
        input.SupplyType == SupplyType.HighPowerAc
            && (input.BatteryPercent is null || input.BatteryPercent >= settings.BalancedBatteryThresholdPercent)
            ? OperatingMode.Balanced
            : OperatingMode.Quiet;

    private static ApplicationRule? ResolveRule(SmartAutomationInput input, SmartAutomationSettings settings)
    {
        foreach (var rule in settings.ApplicationRules ?? [])
        {
            if (!rule.Enabled) continue;
            var matches = rule.Scope switch
            {
                ApplicationRuleScope.Foreground => Matches(input.ForegroundProcess, rule.NormalizedProcessName),
                ApplicationRuleScope.Fullscreen => input.ForegroundFullscreen
                    && Matches(input.ForegroundProcess, rule.NormalizedProcessName),
                ApplicationRuleScope.Running => (input.RunningProcesses ?? [])
                    .Any(process => Matches(process, rule.NormalizedProcessName)),
                _ => false
            };
            if (matches) return rule;
        }
        if (Matches(input.ForegroundProcess, settings.HyperProcessNames))
            return new ApplicationRule(input.ForegroundProcess!, ApplicationRuleProfile.Performance, ApplicationRuleScope.Foreground);
        if (Matches(input.ForegroundProcess, settings.BalanceProcessNames))
            return new ApplicationRule(input.ForegroundProcess!, ApplicationRuleProfile.Balanced, ApplicationRuleScope.Foreground);
        return null;
    }

    private static bool IsIgnoredFullscreen(string? process, SmartAutomationSettings settings) =>
        Matches(process, settings.IgnoredFullscreenProcesses);

    private static bool Matches(string? value, string? expected) =>
        !string.IsNullOrWhiteSpace(value)
        && string.Equals(Normalize(value), Normalize(expected), StringComparison.OrdinalIgnoreCase);

    private static bool Matches(string? value, IReadOnlyList<string>? expected) =>
        expected?.Any(item => Matches(value, item)) == true;

    private static string Normalize(string? value) =>
        value?.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) == true
            ? value[..^4]
            : value ?? string.Empty;

    private static bool AtLeast(double value, double threshold) =>
        double.IsFinite(value) && value >= threshold;
}
