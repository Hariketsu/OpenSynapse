namespace OpenSynapse.Core;

public enum OperatingMode
{
    Performance,
    Quiet
}

public enum ModeSelection
{
    Auto,
    Performance,
    Quiet
}

public enum PowerSource
{
    Unknown,
    Ac,
    Battery
}

public static class ModeSelector
{
    public static OperatingMode Resolve(ModeSelection selection, PowerSource source) => selection switch
    {
        ModeSelection.Performance => OperatingMode.Performance,
        ModeSelection.Quiet => OperatingMode.Quiet,
        _ when source == PowerSource.Ac => OperatingMode.Performance,
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
    IReadOnlyList<RazerDevice> RazerDevices);

public sealed record AgentResponse(
    bool Success,
    string Message,
    AgentStatus? Status = null);
