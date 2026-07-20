using System.Security.Principal;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class AgentController
{
    private readonly object gate = new();
    private readonly StateStore store = new();
    private readonly PowerPlanManager power = new();
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

    public void ApplyCurrentSelection()
    {
        lock (gate)
        {
            if (shuttingDown) return;
            try
            {
                var state = store.Load();
                ApplyMode(ModeSelector.Resolve(state.Selection, GetPowerSource()), state);
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
                return ApplyMode(request.Mode ?? throw new ArgumentException("Mode is required."), state);

            case AgentOperation.SetSelection:
                state.Selection = request.Selection ?? throw new ArgumentException("Selection is required.");
                store.Save(state);
                return ApplyMode(ModeSelector.Resolve(state.Selection, GetPowerSource()), state);

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

    private AgentStatus GetStatus(OpenSynapseState state) => new(
        power.GetActiveGuid(),
        state.ActiveMode,
        state.Selection,
        GetPowerSource(),
        deathAdder.ReadDevices());

    private AgentResponse ApplyMode(OperatingMode mode, OpenSynapseState state)
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
            return new AgentResponse(true, $"Applied {mode} mode.", GetStatus(state));
        }
        finally { store.Save(state); }
    }

    private static PowerSource GetPowerSource() => System.Windows.Forms.SystemInformation.PowerStatus.PowerLineStatus switch
    {
        System.Windows.Forms.PowerLineStatus.Online => PowerSource.Ac,
        System.Windows.Forms.PowerLineStatus.Offline => PowerSource.Battery,
        _ => PowerSource.Unknown
    };

    private static void RequireAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
            throw new UnauthorizedAccessException("Applying or restoring Windows policies requires an elevated OpenSynapse.Agent.");
    }
}
