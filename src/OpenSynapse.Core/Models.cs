namespace OpenSynapse.Core;

public enum OperatingMode
{
    Performance,
    Balanced,
    Quiet
}

public enum ModeSelection
{
    Auto,
    Performance,
    Balanced,
    Quiet
}

public enum PowerSource
{
    Unknown,
    Ac,
    Battery
}

public enum SupplyType
{
    Unknown,
    HighPowerAc,
    LowPowerPd,
    UnknownAc,
    Battery
}

public enum RuntimeHealth
{
    Starting,
    Healthy,
    Recovering
}

public enum RefreshPolicy
{
    Auto,
    FollowMode,
    Unmanaged,
    Maximum,
    Fixed60,
    Fixed120,
    Fixed240,
    DynamicNative
}

public sealed record DisplayPolicySettings(
    int BalancedBatteryThresholdPercent,
    bool ManageAdvancedColor,
    bool ManageBrightness,
    bool ManageDisplayScaling,
    RefreshPolicy RefreshPolicy,
    int InternalDisplayScalePercent,
    int ExternalDisplayScalePercent,
    int BalancedBrightnessPercent,
    int QuietBrightnessPercent,
    int BalancedRefreshRateHz,
    int QuietRefreshRateHz)
{
    public static IReadOnlyList<int> AllowedDisplayScales { get; } =
        Array.AsReadOnly([100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500]);

    public void Validate()
    {
        if (!Enum.IsDefined(RefreshPolicy))
            throw new InvalidDataException($"Unsupported refresh policy {RefreshPolicy}.");
        ValidatePercentage(BalancedBatteryThresholdPercent, nameof(BalancedBatteryThresholdPercent));
        ValidateScale(InternalDisplayScalePercent, nameof(InternalDisplayScalePercent));
        ValidateScale(ExternalDisplayScalePercent, nameof(ExternalDisplayScalePercent));
        ValidatePercentage(BalancedBrightnessPercent, nameof(BalancedBrightnessPercent));
        ValidatePercentage(QuietBrightnessPercent, nameof(QuietBrightnessPercent));
        ValidateRefreshRate(BalancedRefreshRateHz, nameof(BalancedRefreshRateHz));
        ValidateRefreshRate(QuietRefreshRateHz, nameof(QuietRefreshRateHz));
    }

    private static void ValidateScale(int value, string name)
    {
        if (!AllowedDisplayScales.Contains(value))
            throw new InvalidDataException($"{name} must be a supported Windows scale percentage.");
    }

    private static void ValidatePercentage(int value, string name)
    {
        if (value is < 0 or > 100)
            throw new InvalidDataException($"{name} must be between 0 and 100 percent.");
    }

    private static void ValidateRefreshRate(int value, string name)
    {
        if (value is < 24 or > 1000)
            throw new InvalidDataException($"{name} must be between 24 and 1000 Hz.");
    }
}

public sealed record QuietMaintenanceSettings(
    bool ManageWakeDevices,
    IReadOnlyList<string> WakeDeviceNames)
{
    public void Validate()
    {
        if (WakeDeviceNames is null)
            throw new InvalidDataException("Wake device names are required.");
        if (WakeDeviceNames.Count > 16)
            throw new InvalidDataException("At most 16 wake devices can be configured.");

        var unique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var name in WakeDeviceNames)
        {
            if (string.IsNullOrWhiteSpace(name) || name.Length > 192 || name.Any(char.IsControl))
                throw new InvalidDataException("Wake device names must contain 1 to 192 printable characters.");
            if (!string.Equals(name, name.Trim(), StringComparison.Ordinal))
                throw new InvalidDataException("Wake device names cannot have leading or trailing whitespace.");
            if (!unique.Add(name))
                throw new InvalidDataException($"Wake device name {name} is duplicated.");
        }
    }
}

public sealed record PowerSnapshot(
    PowerSource Source,
    SupplyType SupplyType,
    int? BatteryPercent = null,
    double? AdapterLimitWatts = null);

public static class SupplyClassifier
{
    public const double HighPowerAdapterThresholdWatts = 130;
    public const double LowPowerAdapterThresholdWatts = 85;

    public static SupplyType Resolve(PowerSource source, double? adapterLimitWatts) => source switch
    {
        PowerSource.Battery => SupplyType.Battery,
        PowerSource.Unknown => SupplyType.Unknown,
        _ when adapterLimitWatts is null || !double.IsFinite(adapterLimitWatts.Value) => SupplyType.UnknownAc,
        _ when adapterLimitWatts >= HighPowerAdapterThresholdWatts => SupplyType.HighPowerAc,
        _ when adapterLimitWatts <= LowPowerAdapterThresholdWatts => SupplyType.LowPowerPd,
        _ => SupplyType.UnknownAc
    };
}

public static class ModeSelector
{
    public const int BalancedBatteryThresholdPercent = 50;

    public static bool IsBalancedEligible(
        PowerSnapshot power,
        int batteryThresholdPercent = BalancedBatteryThresholdPercent) =>
        power.BatteryPercent >= batteryThresholdPercent;

    public static OperatingMode Resolve(
        ModeSelection selection,
        PowerSnapshot power,
        int balancedBatteryThresholdPercent = BalancedBatteryThresholdPercent) => selection switch
        {
            ModeSelection.Performance => OperatingMode.Performance,
            ModeSelection.Balanced when IsBalancedEligible(power, balancedBatteryThresholdPercent) => OperatingMode.Balanced,
            ModeSelection.Balanced => OperatingMode.Quiet,
            ModeSelection.Quiet => OperatingMode.Quiet,
            _ when power.SupplyType == SupplyType.HighPowerAc => OperatingMode.Performance,
            _ => OperatingMode.Quiet
        };
}

public enum AgentOperation
{
    Status,
    SelfTest,
    Apply,
    SetSelection,
    SetDisplayPolicy,
    SetQuietMaintenance,
    SetApplicationRules,
    SetTemporaryMode,
    ClearTemporaryMode,
    ApplyDisplayPolicyNow,
    ExportDiagnostics,
    Restore,
    UninstallCleanup,
    ListDevices,
    SetMouseDpi,
    SetMousePollingRate,
    Shutdown
}

public sealed record AgentRequest(
    AgentOperation Operation,
    OperatingMode? Mode = null,
    ModeSelection? Selection = null,
    int? DpiX = null,
    int? DpiY = null,
    int? PollingRate = null,
    int? ProductId = null,
    DisplayPolicySettings? DisplayPolicy = null,
    QuietMaintenanceSettings? QuietMaintenance = null,
    IReadOnlyList<ApplicationRule>? ApplicationRules = null,
    int? TemporaryMinutes = null,
    bool TemporaryUntilPowerChange = false);

public sealed record RazerDevice(
    int VendorId,
    int ProductId,
    string Name,
    string Connection,
    string? FirmwareVersion = null,
    string? SerialNumber = null,
    int? DpiX = null,
    int? DpiY = null,
    int? PollingRate = null,
    int? BatteryPercent = null,
    bool? IsCharging = null);

public sealed record AgentStatus(
    string? ActivePowerPlan,
    OperatingMode? ActiveMode,
    ModeSelection Selection,
    PowerSource PowerSource,
    SupplyType SupplyType,
    int? BatteryPercent,
    double? AdapterLimitWatts,
    IReadOnlyList<RazerDevice> RazerDevices,
    DisplayPolicySettings? DisplayPolicy = null,
    QuietMaintenanceSettings? QuietMaintenance = null,
    IReadOnlyList<string>? WakeArmedDevices = null,
    SmartAutomationStatus? SmartAutomation = null,
    TelemetrySnapshot? Telemetry = null,
    TemporaryModeState? TemporaryMode = null,
    RuntimeHealth Health = RuntimeHealth.Starting,
    string? DiagnosticsPath = null,
    IReadOnlyList<ApplicationRule>? ApplicationRules = null);

public sealed record SmartAutomationStatus(
    OperatingMode? CurrentMode,
    OperatingMode? CandidateMode,
    int CandidateSamples,
    string Reason,
    string? MatchedRule,
    bool DgpuActivitySuspected = false,
    string DgpuActivityConfidence = "None",
    int DgpuLeakSamples = 0,
    IReadOnlyList<GpuConsumerSnapshot>? DgpuConsumers = null);

public sealed record TelemetrySnapshot(
    double CpuPercent,
    double GpuPercent,
    string? ForegroundProcess,
    bool ForegroundFullscreen,
    bool SessionLocked,
    double? BatteryDischargeWatts = null,
    double? BatteryChargeWatts = null,
    double? BatteryRemainingMwh = null,
    double? BatteryVoltageMv = null,
    double? EstimatedHours = null,
    string Confidence = "Unavailable",
    IReadOnlyList<string>? RunningProcesses = null,
    bool GpuAvailable = false,
    double DgpuPercent = -1,
    double DgpuDedicatedMb = -1,
    bool DgpuActivitySuspected = false,
    string DgpuActivityConfidence = "None",
    IReadOnlyList<GpuConsumerSnapshot>? DgpuConsumers = null,
    string GpuError = "",
    double? BatteryDischargeEmaWatts = null,
    double? BatteryDischargeAverage10mWatts = null);

public sealed record GpuConsumerSnapshot(
    int ProcessId,
    string ProcessName,
    string AdapterName,
    double UtilizationPercent,
    long DedicatedBytes,
    bool Discrete);

public sealed record AgentResponse(
    bool Success,
    string Message,
    AgentStatus? Status = null,
    IReadOnlyList<DiagnosticCheck>? Diagnostics = null);

public enum DiagnosticStatus
{
    Passed,
    Warning,
    Failed
}

public sealed record DiagnosticCheck(
    string Name,
    DiagnosticStatus Status,
    string Message);
