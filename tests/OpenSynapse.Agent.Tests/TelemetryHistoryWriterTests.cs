using OpenSynapse.Core;

namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class TelemetryHistoryWriterTests
{
    [TestMethod]
    public void WritesAtMostOneRecordPerThirtySecondsAndIncludesTrendFields()
    {
        var root = Path.Combine(Path.GetTempPath(), $"opensynapse-history-{Guid.NewGuid():N}");
        var path = Path.Combine(root, "telemetry.jsonl");
        var now = DateTimeOffset.UtcNow;
        try
        {
            var writer = new TelemetryHistoryWriter(path, () => now);
            var state = new OpenSynapseState();
            state.ActiveMode = OperatingMode.Quiet;
            state.SmartAutomation.DgpuActivitySuspected = true;
            state.SmartAutomation.DgpuActivityConfidence = "Medium";
            state.SmartAutomation.DgpuConsumers =
            [new GpuConsumerSnapshot(42, "renderer", "Discrete GPU", 2, 256L * 1024 * 1024, true)];
            var config = new OpenSynapseConfig();
            var power = new PowerSnapshot(PowerSource.Battery, SupplyType.Battery, 72);
            var telemetry = new TelemetrySnapshot(
                21,
                8,
                "renderer",
                false,
                false,
                BatteryDischargeWatts: 18,
                BatteryDischargeEmaWatts: 12,
                BatteryDischargeAverage10mWatts: 10,
                GpuAvailable: true,
                DgpuPercent: 2,
                DgpuDedicatedMb: 256);

            Assert.IsTrue(writer.TryWrite(state, config, power, telemetry));
            Assert.HasCount(1, File.ReadAllLines(path));

            now = now.AddSeconds(29);
            Assert.IsTrue(writer.TryWrite(state, config, power, telemetry));
            Assert.HasCount(1, File.ReadAllLines(path));

            now = now.AddSeconds(2);
            Assert.IsTrue(writer.TryWrite(state, config, power, telemetry));
            var contents = File.ReadAllText(path);
            Assert.HasCount(2, File.ReadAllLines(path));
            StringAssert.Contains(contents, "batteryDischargeEmaWatts");
            StringAssert.Contains(contents, "renderer");
            StringAssert.Contains(contents, "dgpuActivitySuspected");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
}
