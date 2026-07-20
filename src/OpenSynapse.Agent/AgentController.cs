using System.Security.Principal;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class AgentController
{
    private readonly object gate = new();
    private readonly StateStore store = new();
    private readonly ConfigurationStore configurationStore = new();
    private readonly AgentLog log = new();
    private readonly PowerPlanManager power = new();
    private readonly PowerSupplyProbe powerSupply = new();
    private readonly DisplayPolicy displays = new();
    private readonly WakeDeviceManager wakeDevices = new();
    private readonly DeathAdderHid deathAdder = new();
    private bool shuttingDown;

    public Task<AgentResponse> HandleAsync(AgentRequest request)
    {
        lock (gate)
        {
            try { return Task.FromResult(Handle(request)); }
            catch (Exception ex)
            {
                _ = log.TryWrite($"request.{request.Operation}.failed", ex.Message);
                return Task.FromResult(new AgentResponse(false, ex.Message));
            }
        }
    }

    public void ApplyCurrentSelection(bool force = false)
    {
        lock (gate)
        {
            if (shuttingDown) return;
            try
            {
                var (state, config) = LoadContext();
                var powerSnapshot = powerSupply.GetSnapshot();
                if (config.Selection == ModeSelection.Balanced
                    && !ModeSelector.IsBalancedEligible(powerSnapshot, config.BalancedBatteryThresholdPercent))
                {
                    config.Selection = ModeSelection.Quiet;
                    configurationStore.Save(config);
                    _ = log.TryWrite(
                        "selection.latched",
                        $"Balanced changed to Quiet below {config.BalancedBatteryThresholdPercent}% battery.");
                }
                var desiredMode = ModeSelector.Resolve(
                    config.Selection,
                    powerSnapshot,
                    config.BalancedBatteryThresholdPercent);
                if (!force && state.ActiveMode == desiredMode)
                {
                    wakeDevices.Apply(desiredMode, config, state, () => store.Save(state));
                    return;
                }
                ApplyMode(desiredMode, state, config, powerSnapshot);
            }
            catch (Exception ex)
            {
                _ = log.TryWrite("selection.automatic.failed", ex.Message);
                Console.Error.WriteLine($"Automatic mode application failed: {ex.Message}");
            }
        }
    }

    public void ReapplyDisplayPolicy()
    {
        lock (gate)
        {
            if (shuttingDown) return;
            OpenSynapseState? state = null;
            try
            {
                var context = LoadContext();
                state = context.State;
                if (state.ActiveMode is not OperatingMode mode) return;
                RequireAdministrator();
                displays.Capture(mode, state, context.Config);
                store.Save(state);
                displays.Apply(mode, state, context.Config);
                _ = log.TryWrite("display.reapplied", mode.ToString());
            }
            catch (Exception ex)
            {
                _ = log.TryWrite("display.reapply.failed", ex.Message);
                Console.Error.WriteLine($"Display policy reapplication failed: {ex.Message}");
            }
            finally
            {
                if (state is not null)
                {
                    try { store.Save(state); }
                    catch (Exception ex) { _ = log.TryWrite("display.state-save.failed", ex.Message); }
                }
            }
        }
    }

    private AgentResponse Handle(AgentRequest request)
    {
        if (request.Operation == AgentOperation.SelfTest) return RunSelfTest();
        var (state, config) = LoadContext();
        switch (request.Operation)
        {
            case AgentOperation.Status:
            case AgentOperation.ListDevices:
                return new AgentResponse(true, "OK", GetStatus(state, config));

            case AgentOperation.Apply:
                var mode = request.Mode ?? throw new ArgumentException("Mode is required.");
                var applyPowerSnapshot = powerSupply.GetSnapshot();
                EnsureBalancedEligible(mode, applyPowerSnapshot, config);
                return ApplyMode(mode, state, config, applyPowerSnapshot);

            case AgentOperation.SetSelection:
                var selection = request.Selection ?? throw new ArgumentException("Selection is required.");
                var powerSnapshot = powerSupply.GetSnapshot();
                if (selection == ModeSelection.Balanced
                    && !ModeSelector.IsBalancedEligible(powerSnapshot, config.BalancedBatteryThresholdPercent))
                    throw new InvalidOperationException(
                        $"Balanced mode requires at least {config.BalancedBatteryThresholdPercent}% battery; "
                        + $"current charge is {powerSnapshot.BatteryPercent?.ToString() ?? "unavailable"}%.");
                config.Selection = selection;
                configurationStore.Save(config);
                _ = log.TryWrite("selection.changed", selection.ToString());
                return ApplyMode(
                    ModeSelector.Resolve(selection, powerSnapshot, config.BalancedBatteryThresholdPercent),
                    state,
                    config,
                    powerSnapshot);

            case AgentOperation.SetDisplayPolicy:
                RequireAdministrator();
                var displaySettings = request.DisplayPolicy
                    ?? throw new ArgumentException("DisplayPolicy is required.");
                var updatedConfig = config.WithDisplayPolicy(displaySettings);
                var existingDisplayRestored = displays.Restore(state);
                if (!existingDisplayRestored)
                    throw new InvalidOperationException(
                        "Existing display state restoration remains pending; settings were not changed.");
                state.ActiveMode = null;
                store.Save(state);
                configurationStore.Save(updatedConfig);
                var updatedPowerSnapshot = powerSupply.GetSnapshot();
                var updatedMode = ModeSelector.Resolve(
                    updatedConfig.Selection,
                    updatedPowerSnapshot,
                    updatedConfig.BalancedBatteryThresholdPercent);
                _ = log.TryWrite("configuration.display.changed", updatedConfig.RefreshPolicy.ToString());
                return ApplyMode(updatedMode, state, updatedConfig, updatedPowerSnapshot);

            case AgentOperation.SetQuietMaintenance:
                RequireAdministrator();
                var quietSettings = request.QuietMaintenance
                    ?? throw new ArgumentException("QuietMaintenance is required.");
                var updatedQuietConfig = config.WithQuietMaintenance(quietSettings);
                wakeDevices.Restore(state, () => store.Save(state));
                configurationStore.Save(updatedQuietConfig);
                if (state.ActiveMode == OperatingMode.Quiet)
                    wakeDevices.Apply(OperatingMode.Quiet, updatedQuietConfig, state, () => store.Save(state));
                _ = log.TryWrite(
                    "configuration.quiet-maintenance.changed",
                    updatedQuietConfig.ManageWakeDevices
                        ? $"Enabled for {updatedQuietConfig.QuietWakeDeviceNames.Count} exact device name(s)."
                        : "Disabled.");
                return new AgentResponse(
                    true,
                    "Quiet wake-device settings saved and reconciled.",
                    GetStatus(state, updatedQuietConfig));

            case AgentOperation.Restore:
            case AgentOperation.Shutdown:
                RequireAdministrator();
                shuttingDown = request.Operation == AgentOperation.Shutdown;
                try
                {
                    var displayRestored = displays.Restore(state);
                    power.Restore(state);
                    wakeDevices.Restore(state, () => store.Save(state));
                    if (!displayRestored)
                        throw new InvalidOperationException("Display state restoration remains pending; captured state was retained for retry.");
                    state.ActiveMode = null;
                    var message = request.Operation == AgentOperation.Shutdown
                        ? "Restored captured Windows and wake state; agent is shutting down."
                        : "Restored captured Windows and wake state.";
                    _ = log.TryWrite("state.restored", message);
                    return new AgentResponse(true, message, GetStatus(state, config));
                }
                catch
                {
                    shuttingDown = false;
                    throw;
                }
                finally { store.Save(state); }

            case AgentOperation.UninstallCleanup:
                RequireAdministrator();
                try
                {
                    var displayRestored = displays.Restore(state);
                    power.Restore(state);
                    wakeDevices.Restore(state, () => store.Save(state));
                    if (!displayRestored)
                        throw new InvalidOperationException(
                            "Display restoration remains pending; uninstall cleanup was stopped for a later retry.");
                    state.ActiveMode = null;
                    power.DeleteManagedPlans(state);
                    _ = log.TryWrite(
                        "uninstall.cleanup",
                        "Restored captured state and wake permissions, then removed managed power plans.");
                    return new AgentResponse(
                        true,
                        "Restored captured state and wake permissions, then removed managed power plans.",
                        GetStatus(state, config));
                }
                finally { store.Save(state); }

            case AgentOperation.SetMouseDpi:
                deathAdder.SetDpi(
                    request.DpiX ?? throw new ArgumentException("DpiX is required."),
                    request.DpiY ?? request.DpiX.Value,
                    request.ProductId);
                return new AgentResponse(true, "DeathAdder DPI updated.", GetStatus(state, config));

            case AgentOperation.SetMousePollingRate:
                deathAdder.SetPollingRate(
                    request.PollingRate ?? throw new ArgumentException("PollingRate is required."),
                    request.ProductId);
                return new AgentResponse(true, "DeathAdder polling rate updated.", GetStatus(state, config));

            default:
                throw new ArgumentOutOfRangeException(nameof(request.Operation));
        }
    }

    private AgentStatus GetStatus(
        OpenSynapseState state,
        OpenSynapseConfig config,
        PowerSnapshot? powerSnapshot = null)
    {
        powerSnapshot ??= powerSupply.GetSnapshot();
        return new AgentStatus(
            power.GetActiveGuid(),
            state.ActiveMode,
            config.Selection,
            powerSnapshot.Source,
            powerSnapshot.SupplyType,
            powerSnapshot.BatteryPercent,
            powerSnapshot.AdapterLimitWatts,
            deathAdder.ReadDevices(),
            config.ToDisplayPolicySettings(),
            config.ToQuietMaintenanceSettings(),
            GetWakeDevicesForStatus());
    }

    private AgentResponse ApplyMode(
        OperatingMode mode,
        OpenSynapseState state,
        OpenSynapseConfig config,
        PowerSnapshot? powerSnapshot = null)
    {
        RequireAdministrator();
        try
        {
            state.OriginalPowerPlan ??= power.GetActiveGuid();
            displays.Capture(mode, state, config);
            store.Save(state);
            power.Apply(mode, state);
            wakeDevices.Apply(mode, config, state, () => store.Save(state));
            displays.Apply(mode, state, config);
            state.ActiveMode = mode;
            _ = log.TryWrite("mode.applied", mode.ToString());
            return new AgentResponse(true, $"Applied {mode} mode.", GetStatus(state, config, powerSnapshot));
        }
        finally { store.Save(state); }
    }

    private static void RequireAdministrator()
    {
        if (!IsAdministrator())
            throw new UnauthorizedAccessException("Applying or restoring Windows policies requires an elevated OpenSynapse.Agent.");
    }

    private static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    private (OpenSynapseState State, OpenSynapseConfig Config) LoadContext()
    {
        var state = store.Load();
        var config = configurationStore.Load(state.LegacySelection);
        if (state.LegacySelection is not null)
        {
            state.LegacySelection = null;
            store.Save(state);
            _ = log.TryWrite("configuration.migrated", "Moved mode selection from state schema to config schema.");
        }
        return (state, config);
    }

    private AgentResponse RunSelfTest()
    {
        var checks = new List<DiagnosticCheck>();
        OpenSynapseState? state = null;
        try
        {
            state = store.Load();
            checks.Add(new DiagnosticCheck(
                "Captured state",
                DiagnosticStatus.Passed,
                $"Schema {state.SchemaVersion} loaded."));
            var hasRollback = state.ActiveMode is not null
                || state.OriginalPowerPlan is not null
                || state.OriginalBrightness is not null
                || state.AdvancedColors.Count != 0
                || state.DisplayScales.Count != 0
                || state.DisabledWakeDevices.Count != 0;
            checks.Add(new DiagnosticCheck(
                "Rollback snapshot",
                hasRollback ? DiagnosticStatus.Warning : DiagnosticStatus.Passed,
                hasRollback ? "Captured rollback data is active or pending." : "No rollback is pending."));
        }
        catch (Exception ex)
        {
            checks.Add(new DiagnosticCheck("Captured state", DiagnosticStatus.Failed, ex.Message));
        }

        try
        {
            var config = configurationStore.Load(state?.LegacySelection);
            checks.Add(new DiagnosticCheck(
                "Configuration",
                DiagnosticStatus.Passed,
                $"Schema {config.SchemaVersion} loaded; selection is {config.Selection}."));
        }
        catch (Exception ex)
        {
            checks.Add(new DiagnosticCheck("Configuration", DiagnosticStatus.Failed, ex.Message));
        }

        var isAdministrator = IsAdministrator();
        checks.Add(new DiagnosticCheck(
            "Administrator",
            isAdministrator ? DiagnosticStatus.Passed : DiagnosticStatus.Warning,
            isAdministrator ? "Agent is elevated." : "Read-only checks work, but policy changes require elevation."));

        try
        {
            checks.Add(new DiagnosticCheck(
                "Power plan",
                DiagnosticStatus.Passed,
                $"Active plan is {power.GetActiveGuid()}."));
        }
        catch (Exception ex)
        {
            checks.Add(new DiagnosticCheck("Power plan", DiagnosticStatus.Failed, ex.Message));
        }

        try
        {
            var snapshot = powerSupply.GetSnapshot();
            var ambiguous = snapshot.SupplyType is SupplyType.Unknown or SupplyType.UnknownAc;
            checks.Add(new DiagnosticCheck(
                "Power supply",
                ambiguous ? DiagnosticStatus.Warning : DiagnosticStatus.Passed,
                $"{snapshot.SupplyType}; battery {snapshot.BatteryPercent?.ToString() ?? "unavailable"}%; "
                + $"adapter limit {snapshot.AdapterLimitWatts?.ToString("0.#") ?? "unavailable"} W."));
        }
        catch (Exception ex)
        {
            checks.Add(new DiagnosticCheck("Power supply", DiagnosticStatus.Failed, ex.Message));
        }

        try
        {
            var count = displays.GetActiveDisplayCount();
            checks.Add(new DiagnosticCheck(
                "Displays",
                count == 0 ? DiagnosticStatus.Warning : DiagnosticStatus.Passed,
                $"Detected {count} active display(s)."));
        }
        catch (Exception ex)
        {
            checks.Add(new DiagnosticCheck("Displays", DiagnosticStatus.Failed, ex.Message));
        }

        try
        {
            var devices = wakeDevices.GetWakeArmedDevices();
            checks.Add(new DiagnosticCheck(
                "Wake devices",
                DiagnosticStatus.Passed,
                $"Detected {devices.Count} currently wake-armed device(s)."));
        }
        catch (Exception ex)
        {
            checks.Add(new DiagnosticCheck("Wake devices", DiagnosticStatus.Warning, ex.Message));
        }

        try
        {
            var count = deathAdder.ReadDevices().Count;
            checks.Add(new DiagnosticCheck(
                "Razer devices",
                count == 0 ? DiagnosticStatus.Warning : DiagnosticStatus.Passed,
                count == 0 ? "No supported Razer device detected." : $"Detected {count} supported device(s)."));
        }
        catch (Exception ex)
        {
            checks.Add(new DiagnosticCheck("Razer devices", DiagnosticStatus.Failed, ex.Message));
        }

        var logWritable = log.TryWrite("self-test", "Read-only diagnostics completed.");
        checks.Add(new DiagnosticCheck(
            "Local log",
            logWritable ? DiagnosticStatus.Passed : DiagnosticStatus.Failed,
            logWritable ? $"Writable at {log.FilePath}." : "Cannot write the local agent log."));

        var failures = checks.Count(check => check.Status == DiagnosticStatus.Failed);
        var warnings = checks.Count(check => check.Status == DiagnosticStatus.Warning);
        return new AgentResponse(
            failures == 0,
            $"Self-test completed with {failures} failure(s) and {warnings} warning(s).",
            Diagnostics: checks);
    }

    private static void EnsureBalancedEligible(
        OperatingMode mode,
        PowerSnapshot powerSnapshot,
        OpenSynapseConfig config)
    {
        if (mode != OperatingMode.Balanced
            || ModeSelector.IsBalancedEligible(powerSnapshot, config.BalancedBatteryThresholdPercent)) return;
        throw new InvalidOperationException(
            $"Balanced mode requires at least {config.BalancedBatteryThresholdPercent}% battery; "
            + $"current charge is {powerSnapshot.BatteryPercent?.ToString() ?? "unavailable"}%.");
    }

    private IReadOnlyList<string> GetWakeDevicesForStatus()
    {
        try { return wakeDevices.GetWakeArmedDevices(); }
        catch (Exception ex)
        {
            _ = log.TryWrite("wake-device.query.failed", ex.Message);
            return [];
        }
    }
}
