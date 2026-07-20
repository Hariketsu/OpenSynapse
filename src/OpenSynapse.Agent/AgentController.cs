using System.Security.Principal;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class AgentController
{
    private readonly object gate = new();
    private readonly StateStore store = new();
    private readonly PowerPlanManager power = new();
    private readonly PowerSupplyProbe powerSupply = new();
    private readonly DisplayPolicy displays = new();
    private readonly DeathAdderHid deathAdder = new();
    private bool shuttingDown;

    public Task<AgentResponse> HandleAsync(AgentRequest request)
    {
        lock (gate)
        {
            try { return Task.FromResult(Handle(request)); }
            catch (Exception ex) { return Task.FromResult(new AgentResponse(false, ex.Message)); }
        }
    }

    public void ApplyCurrentSelection(bool force = false)
    {
        lock (gate)
        {
            if (shuttingDown) return;
            try
            {
                var state = store.Load();
                var powerSnapshot = powerSupply.GetSnapshot();
                if (state.Selection == ModeSelection.Balanced && !ModeSelector.IsBalancedEligible(powerSnapshot))
                {
                    state.Selection = ModeSelection.Quiet;
                    store.Save(state);
                }
                var desiredMode = ModeSelector.Resolve(state.Selection, powerSnapshot);
                if (!force && state.ActiveMode == desiredMode) return;
                ApplyMode(desiredMode, state, powerSnapshot);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Automatic mode application failed: {ex.Message}");
            }
        }
    }

    private AgentResponse Handle(AgentRequest request)
    {
        var state = store.Load();
        switch (request.Operation)
        {
            case AgentOperation.Status:
            case AgentOperation.ListDevices:
                return new AgentResponse(true, "OK", GetStatus(state));

            case AgentOperation.Apply:
                var mode = request.Mode ?? throw new ArgumentException("Mode is required.");
                var applyPowerSnapshot = powerSupply.GetSnapshot();
                EnsureBalancedEligible(mode, applyPowerSnapshot);
                return ApplyMode(mode, state, applyPowerSnapshot);

            case AgentOperation.SetSelection:
                var selection = request.Selection ?? throw new ArgumentException("Selection is required.");
                var powerSnapshot = powerSupply.GetSnapshot();
                if (selection == ModeSelection.Balanced && !ModeSelector.IsBalancedEligible(powerSnapshot))
                    throw new InvalidOperationException(
                        $"Balanced mode requires at least {ModeSelector.BalancedBatteryThresholdPercent}% battery; "
                        + $"current charge is {powerSnapshot.BatteryPercent?.ToString() ?? "unavailable"}%.");
                state.Selection = selection;
                store.Save(state);
                return ApplyMode(ModeSelector.Resolve(state.Selection, powerSnapshot), state, powerSnapshot);

            case AgentOperation.Restore:
            case AgentOperation.Shutdown:
                RequireAdministrator();
                shuttingDown = request.Operation == AgentOperation.Shutdown;
                try
                {
                    var displayRestored = displays.Restore(state);
                    power.Restore(state);
                    if (!displayRestored)
                        throw new InvalidOperationException("Display state restoration remains pending; captured state was retained for retry.");
                    state.ActiveMode = null;
                    var message = request.Operation == AgentOperation.Shutdown
                        ? "Restored captured Windows state; agent is shutting down."
                        : "Restored captured Windows state.";
                    return new AgentResponse(true, message, GetStatus(state));
                }
                catch
                {
                    shuttingDown = false;
                    throw;
                }
                finally { store.Save(state); }

            case AgentOperation.SetMouseDpi:
                deathAdder.SetDpi(
                    request.DpiX ?? throw new ArgumentException("DpiX is required."),
                    request.DpiY ?? request.DpiX.Value,
                    request.ProductId);
                return new AgentResponse(true, "DeathAdder DPI updated.", GetStatus(state));

            case AgentOperation.SetMousePollingRate:
                deathAdder.SetPollingRate(
                    request.PollingRate ?? throw new ArgumentException("PollingRate is required."),
                    request.ProductId);
                return new AgentResponse(true, "DeathAdder polling rate updated.", GetStatus(state));

            default:
                throw new ArgumentOutOfRangeException(nameof(request.Operation));
        }
    }

    private AgentStatus GetStatus(OpenSynapseState state, PowerSnapshot? powerSnapshot = null)
    {
        powerSnapshot ??= powerSupply.GetSnapshot();
        return new AgentStatus(
            power.GetActiveGuid(),
            state.ActiveMode,
            state.Selection,
            powerSnapshot.Source,
            powerSnapshot.SupplyType,
            powerSnapshot.BatteryPercent,
            powerSnapshot.AdapterLimitWatts,
            deathAdder.ReadDevices());
    }

    private AgentResponse ApplyMode(
        OperatingMode mode,
        OpenSynapseState state,
        PowerSnapshot? powerSnapshot = null)
    {
        RequireAdministrator();
        try
        {
            state.OriginalPowerPlan ??= power.GetActiveGuid();
            displays.Capture(mode, state);
            store.Save(state);
            power.Apply(mode, state);
            displays.Apply(mode, state);
            state.ActiveMode = mode;
            return new AgentResponse(true, $"Applied {mode} mode.", GetStatus(state, powerSnapshot));
        }
        finally { store.Save(state); }
    }

    private static void RequireAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
            throw new UnauthorizedAccessException("Applying or restoring Windows policies requires an elevated OpenSynapse.Agent.");
    }

    private static void EnsureBalancedEligible(OperatingMode mode, PowerSnapshot powerSnapshot)
    {
        if (mode != OperatingMode.Balanced || ModeSelector.IsBalancedEligible(powerSnapshot)) return;
        throw new InvalidOperationException(
            $"Balanced mode requires at least {ModeSelector.BalancedBatteryThresholdPercent}% battery; "
            + $"current charge is {powerSnapshot.BatteryPercent?.ToString() ?? "unavailable"}%.");
    }
}
