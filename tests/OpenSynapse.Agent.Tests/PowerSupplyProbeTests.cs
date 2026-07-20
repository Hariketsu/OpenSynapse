using OpenSynapse.Core;

namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class PowerSupplyProbeTests
{
    [TestMethod]
    public void GetSnapshotCachesAcProbeForFiveMinutes()
    {
        var now = new DateTimeOffset(2026, 7, 20, 0, 0, 0, TimeSpan.Zero);
        var probeCount = 0;
        var probe = new PowerSupplyProbe(
            () => new SystemPowerSnapshot(PowerSource.Ac, 76),
            () => { probeCount++; return 160; },
            () => now,
            TimeSpan.FromMinutes(5));

        var first = probe.GetSnapshot();
        now = now.AddMinutes(4);
        var cached = probe.GetSnapshot();
        now = now.AddMinutes(1);
        var refreshed = probe.GetSnapshot();

        Assert.AreEqual(SupplyType.HighPowerAc, first.SupplyType);
        Assert.AreEqual(160, cached.AdapterLimitWatts);
        Assert.AreEqual(160, refreshed.AdapterLimitWatts);
        Assert.AreEqual(2, probeCount);
    }

    [TestMethod]
    public void GetSnapshotInvalidatesAdapterCacheAfterBatteryUse()
    {
        var source = PowerSource.Ac;
        var probeCount = 0;
        var probe = new PowerSupplyProbe(
            () => new SystemPowerSnapshot(source, 49),
            () => { probeCount++; return 70; },
            () => DateTimeOffset.UtcNow,
            TimeSpan.FromMinutes(5));

        var ac = probe.GetSnapshot();
        source = PowerSource.Battery;
        var battery = probe.GetSnapshot();
        source = PowerSource.Ac;
        _ = probe.GetSnapshot();

        Assert.AreEqual(SupplyType.LowPowerPd, ac.SupplyType);
        Assert.AreEqual(SupplyType.Battery, battery.SupplyType);
        Assert.IsNull(battery.AdapterLimitWatts);
        Assert.AreEqual(2, probeCount);
    }

    [TestMethod]
    public void GetSnapshotFailsSafeWhenAdapterProbeThrows()
    {
        var probe = new PowerSupplyProbe(
            () => new SystemPowerSnapshot(PowerSource.Ac, 100),
            () => throw new InvalidOperationException("nvidia-smi failed"),
            () => DateTimeOffset.UtcNow,
            TimeSpan.FromMinutes(5));

        var snapshot = probe.GetSnapshot();

        Assert.AreEqual(SupplyType.UnknownAc, snapshot.SupplyType);
        Assert.IsNull(snapshot.AdapterLimitWatts);
    }

    [DataRow("160.00", 160.0)]
    [DataRow("70.5\r\n80.0", 70.5)]
    [DataRow("not supported", null)]
    [TestMethod]
    public void ParseAdapterLimitReadsTheFirstInvariantValue(string output, double? expected)
    {
        Assert.AreEqual(expected, PowerSupplyProbe.ParseAdapterLimit(output));
    }
}
