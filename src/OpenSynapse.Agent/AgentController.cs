using System.Security.Principal;
using System.Text.Json;
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
    private readonly TelemetryProbe telemetry = new();
    private RuntimeHealth health = RuntimeHealth.Starting;
    private DateTimeOffset lastRuntimeWrite = DateTimeOffset.MinValue;
    private int consecutiveFailures;
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

    public bool ApplyCurrentSelection(bool force = false)
    {
        lock (gate)
        {
            if (shuttingDown) return false;
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
                var telemetrySnapshot = telemetry.Read(config.ApplicationRules.Any(rule => rule.Scope == ApplicationRuleScope.Running));
                var desiredMode = ResolveDesiredMode(state, config, powerSnapshot, telemetrySnapshot);
                if (!force && state.ActiveMode == desiredMode)
                {
                    wakeDevices.Apply(desiredMode, config, state, () => store.Save(state));
                    health = RuntimeHealth.Healthy;
                    consecutiveFailures = 0;
                    WriteRuntime();
                    store.Save(state);
                    return true;
                }
                ApplyMode(desiredMode, state, config, powerSnapshot);
                health = RuntimeHealth.Healthy;
                consecutiveFailures = 0;
                WriteRuntime();
                return true;
            }
            catch (Exception ex)
            {
                health = RuntimeHealth.Recovering;
                consecutiveFailures++;
                WriteRuntime(force: true);
                _ = log.TryWrite("selection.automatic.failed", ex.Message);
                Console.Error.WriteLine($"Automatic mode application failed: {ex.Message}");
                return false;
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
                displays.Apply(mode, state, context.Config, powerSnapshot: powerSupply.GetSnapshot());
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

            case AgentOperation.SetApplicationRules:
                var rules = request.ApplicationRules
                    ?? throw new ArgumentException("ApplicationRules are required.");
                var updatedRulesConfig = config.WithApplicationRules(rules);
                configurationStore.Save(updatedRulesConfig);
                _ = log.TryWrite("configuration.application-rules.changed", $"{rules.Count} rule(s).");
                return new AgentResponse(true, "Application rules saved.", GetStatus(state, updatedRulesConfig));

            case AgentOperation.SetTemporaryMode:
                RequireAdministrator();
                var temporaryMode = request.Mode ?? throw new ArgumentException("Mode is required.");
                var temporaryPower = powerSupply.GetSnapshot();
                EnsureBalancedEligible(temporaryMode, temporaryPower, config);
                if (!request.TemporaryUntilPowerChange && request.TemporaryMinutes is not (30 or 60 or 120))
                    throw new ArgumentException("Temporary mode duration must be 30, 60, 120 minutes, or until power changes.");
                state.TemporaryMode = new TemporaryModeState(
                    temporaryMode,
                    request.TemporaryUntilPowerChange
                        ? null
                        : DateTimeOffset.UtcNow.AddMinutes(request.TemporaryMinutes!.Value),
                    request.TemporaryUntilPowerChange,
                    temporaryPower.SupplyType);
                store.Save(state);
                return ApplyMode(temporaryMode, state, config, temporaryPower);

            case AgentOperation.ClearTemporaryMode:
                RequireAdministrator();
                state.TemporaryMode = null;
                store.Save(state);
                var resumedPower = powerSupply.GetSnapshot();
                var resumedMode = ResolveDesiredMode(state, config, resumedPower, telemetry.Read());
                return ApplyMode(resumedMode, state, config, resumedPower);

            case AgentOperation.ApplyDisplayPolicyNow:
                RequireAdministrator();
                var explicitMode = state.ActiveMode
                    ?? ResolveDesiredMode(state, config, powerSupply.GetSnapshot(), telemetry.Read());
                displays.Capture(explicitMode, state, config);
                store.Save(state);
                displays.Apply(explicitMode, state, config, applyDisplaySettings: true);
                _ = log.TryWrite("display.explicit-apply", explicitMode.ToString());
                return new AgentResponse(true, "Display policy applied. The display link may blink briefly.", GetStatus(state, config));

            case AgentOperation.ExportDiagnostics:
                var exportPath = DiagnosticExporter.Export(config, state, powerSupply, log.FilePath);
                _ = log.TryWrite("diagnostics.exported", exportPath);
                return new AgentResponse(true, $"Diagnostics exported to {exportPath}.", GetStatus(state, config) with { DiagnosticsPath = exportPath });

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
            GetWakeDevicesForStatus(),
            GetSmartStatus(state),
            telemetry.Read(config.ApplicationRules.Any(rule => rule.Scope == ApplicationRuleScope.Running)),
            state.TemporaryMode,
            health,
            null,
            config.ApplicationRules);
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
            var applyDisplay = !config.SeamlessModeSwitching;
            if (applyDisplay) displays.Capture(mode, state, config);
            store.Save(state);
            power.Apply(mode, state);
            if (mode == OperatingMode.Performance)
                power.ApplyHyperCpuPolicy(state, config.HyperCpuPolicy);
            if (mode == OperatingMode.Quiet && config.AdaptiveQuietCpu && powerSnapshot?.Source == PowerSource.Battery)
                power.ApplyQuietCpuMax(state, ResolveQuietCpuMax(config, powerSnapshot.BatteryPercent));
            wakeDevices.Apply(mode, config, state, () => store.Save(state));
            if (applyDisplay) displays.Apply(mode, state, config, applyDisplaySettings: true, powerSnapshot: powerSnapshot);
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

    private OperatingMode ResolveDesiredMode(
        OpenSynapseState state,
        OpenSynapseConfig config,
        PowerSnapshot powerSnapshot,
        TelemetrySnapshot telemetrySnapshot)
    {
        if (state.TemporaryMode is { } temporary)
        {
            var expired = temporary.ExpiresAt is not null && temporary.ExpiresAt <= DateTimeOffset.UtcNow;
            var powerChanged = temporary.UntilPowerChange && temporary.StartedSupplyType != powerSnapshot.SupplyType;
            if (expired || powerChanged)
            {
                state.TemporaryMode = null;
                _ = log.TryWrite("temporary-mode.expired", expired ? "duration elapsed" : "supply changed");
            }
            else
            {
                return temporary.Mode == OperatingMode.Balanced
                    && !ModeSelector.IsBalancedEligible(powerSnapshot, config.BalancedBatteryThresholdPercent)
                    ? OperatingMode.Quiet
                    : temporary.Mode;
            }
        }

        if (config.Selection != ModeSelection.Auto || !config.SmartAutomationEnabled)
            return ModeSelector.Resolve(config.Selection, powerSnapshot, config.BalancedBatteryThresholdPercent);

        var decision = SmartAutomationEngine.Evaluate(
            new SmartAutomationInput(
                powerSnapshot.SupplyType,
                powerSnapshot.BatteryPercent,
                telemetrySnapshot.CpuPercent,
                telemetrySnapshot.GpuPercent,
                telemetrySnapshot.ForegroundProcess,
                config.SmartFullscreenEnabled && telemetrySnapshot.ForegroundFullscreen,
                telemetrySnapshot.SessionLocked,
                telemetrySnapshot.RunningProcesses),
            config.ToSmartAutomationSettings(),
            state.SmartAutomation,
            DateTimeOffset.UtcNow);
        return decision.Mode;
    }

    private SmartAutomationStatus GetSmartStatus(OpenSynapseState state) => new(
        state.SmartAutomation.CurrentMode,
        state.SmartAutomation.CandidateMode,
        state.SmartAutomation.CandidateSamples,
        state.SmartAutomation.LastReason,
        state.SmartAutomation.MatchedRule);

    private void WriteRuntime(bool force = false)
    {
        var now = DateTimeOffset.UtcNow;
        if (!force && now - lastRuntimeWrite < TimeSpan.FromSeconds(60)) return;
        try
        {
            var path = Path.Combine(Path.GetDirectoryName(log.FilePath)!, "runtime.json");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var temporary = path + ".tmp";
            var record = new
            {
                Version = "OpenSynapse",
                Health = health,
                ConsecutiveFailures = consecutiveFailures,
                LastHeartbeatUtc = now,
                LastSuccessfulTickUtc = health == RuntimeHealth.Healthy ? now : (DateTimeOffset?)null
            };
            File.WriteAllText(temporary, JsonSerializer.Serialize(record, AgentJson.Options));
            File.Move(temporary, path, true);
            lastRuntimeWrite = now;
        }
        catch { }
    }

    private static int ResolveQuietCpuMax(OpenSynapseConfig config, int? batteryPercent)
    {
        if (batteryPercent is null || batteryPercent >= config.QuietCpuMediumThreshold)
            return config.QuietCpuMaxHighBattery;
        if (batteryPercent >= config.QuietCpuLowThreshold)
            return config.QuietCpuMaxMediumBattery;
        return config.QuietCpuMaxLowBattery;
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
            var dynamic = PowerPilotNative.DynamicRefreshManager.GetStatus();
            checks.Add(new DiagnosticCheck(
                "Native dynamic refresh",
                dynamic.Supported ? DiagnosticStatus.Passed : DiagnosticStatus.Warning,
                dynamic.Message));
        }
        catch (Exception ex)
        {
            checks.Add(new DiagnosticCheck("Native dynamic refresh", DiagnosticStatus.Warning, ex.Message));
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
