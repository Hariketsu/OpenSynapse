using System.Text;
using System.Text.Json;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class TelemetryHistoryWriter
{
    private const long RotateAtBytes = 2 * 1024 * 1024;
    private readonly string path;
    private readonly Func<DateTimeOffset> now;
    private DateTimeOffset lastWrite = DateTimeOffset.MinValue;

    public TelemetryHistoryWriter(string? path = null, Func<DateTimeOffset>? now = null)
    {
        this.path = path ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenSynapse",
            "telemetry.jsonl");
        this.now = now ?? (() => DateTimeOffset.UtcNow);
    }

    public string FilePath => path;

    public bool TryWrite(
        OpenSynapseState state,
        OpenSynapseConfig config,
        PowerSnapshot power,
        TelemetrySnapshot telemetry)
    {
        var timestamp = now();
        if (timestamp - lastWrite < TimeSpan.FromSeconds(30)) return true;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            if (File.Exists(path) && new FileInfo(path).Length > RotateAtBytes)
                File.Move(path, path + ".old", true);

            var smart = state.SmartAutomation ?? new SmartAutomationState();
            var record = new
            {
                Timestamp = timestamp,
                Source = power.Source,
                SupplyType = power.SupplyType,
                BatteryPercent = power.BatteryPercent,
                AdapterLimitWatts = power.AdapterLimitWatts,
                BatteryDischargeWatts = telemetry.BatteryDischargeWatts,
                BatteryDischargeEmaWatts = telemetry.BatteryDischargeEmaWatts,
                BatteryDischargeAverage10mWatts = telemetry.BatteryDischargeAverage10mWatts,
                BatteryChargeWatts = telemetry.BatteryChargeWatts,
                BatteryRemainingMwh = telemetry.BatteryRemainingMwh,
                BatteryVoltageMv = telemetry.BatteryVoltageMv,
                BatteryEstimateConfidence = telemetry.Confidence,
                EstimatedHours = telemetry.EstimatedHours,
                Selection = config.Selection,
                TemporaryMode = state.TemporaryMode,
                ActiveMode = state.ActiveMode,
                CpuPercent = telemetry.CpuPercent,
                GpuPercent = telemetry.GpuPercent,
                GpuAvailable = telemetry.GpuAvailable,
                GpuError = telemetry.GpuError,
                DgpuPercent = telemetry.DgpuPercent,
                DgpuDedicatedMb = telemetry.DgpuDedicatedMb,
                DgpuActivitySuspected = smart.DgpuActivitySuspected,
                DgpuActivityConfidence = smart.DgpuActivityConfidence,
                DgpuConsumers = smart.DgpuConsumers.Select(item => item.ProcessName).Distinct(StringComparer.OrdinalIgnoreCase),
                ForegroundProcess = telemetry.ForegroundProcess,
                ForegroundFullscreen = telemetry.ForegroundFullscreen,
                SessionLocked = telemetry.SessionLocked,
                SmartReason = smart.LastReason,
                SmartMatchedRule = smart.MatchedRule
            };
            File.AppendAllText(
                path,
                JsonSerializer.Serialize(record, AgentJson.Options) + Environment.NewLine,
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            lastWrite = timestamp;
            return true;
        }
        catch { return false; }
    }
}
