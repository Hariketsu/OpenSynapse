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

public sealed record PowerSnapshot(
    PowerSource Source,
    SupplyType SupplyType,
    int? BatteryPercent = null,
    double? AdapterLimitWatts = null);

public static class SupplyClassifier
{
    public const double HighPowerAdapterThresholdWatts = 130;
    public const double LowPowerAdapterThresholdWatts = 100;

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

    public static bool IsBalancedEligible(PowerSnapshot power) =>
        power.BatteryPercent >= BalancedBatteryThresholdPercent;

    public static OperatingMode Resolve(ModeSelection selection, PowerSnapshot power) => selection switch
    {
        ModeSelection.Performance => OperatingMode.Performance,
        ModeSelection.Balanced when IsBalancedEligible(power) => OperatingMode.Balanced,
        ModeSelection.Balanced => OperatingMode.Quiet,
        ModeSelection.Quiet => OperatingMode.Quiet,
        _ when power.SupplyType == SupplyType.HighPowerAc => OperatingMode.Performance,
        _ => OperatingMode.Quiet
    };
}

public enum AgentOperation
{
    Status,
    Apply,
    SetSelection,
    Restore,
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
    int? ProductId = null);

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
    IReadOnlyList<RazerDevice> RazerDevices);

public sealed record AgentResponse(
    bool Success,
    string Message,
    AgentStatus? Status = null);
