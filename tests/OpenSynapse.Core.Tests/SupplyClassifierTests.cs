using OpenSynapse.Core;

namespace OpenSynapse.Core.Tests;

[TestClass]
public sealed class SupplyClassifierTests
{
    [DataRow(PowerSource.Battery, null, SupplyType.Battery)]
    [DataRow(PowerSource.Unknown, null, SupplyType.Unknown)]
    [DataRow(PowerSource.Ac, null, SupplyType.UnknownAc)]
    [DataRow(PowerSource.Ac, 70.0, SupplyType.LowPowerPd)]
    [DataRow(PowerSource.Ac, 85.0, SupplyType.LowPowerPd)]
    [DataRow(PowerSource.Ac, 85.1, SupplyType.UnknownAc)]
    [DataRow(PowerSource.Ac, 100.0, SupplyType.UnknownAc)]
    [DataRow(PowerSource.Ac, 129.9, SupplyType.UnknownAc)]
    [DataRow(PowerSource.Ac, 130.0, SupplyType.HighPowerAc)]
    [DataRow(PowerSource.Ac, 160.0, SupplyType.HighPowerAc)]
    [TestMethod]
    public void ResolveUsesFailSafeAdapterBoundaries(
        PowerSource source,
        double? adapterLimitWatts,
        SupplyType expected)
    {
        Assert.AreEqual(expected, SupplyClassifier.Resolve(source, adapterLimitWatts));
    }

    [TestMethod]
    public void ResolveTreatsNonFinitePowerLimitsAsUnknownAc()
    {
        Assert.AreEqual(SupplyType.UnknownAc, SupplyClassifier.Resolve(PowerSource.Ac, double.NaN));
        Assert.AreEqual(SupplyType.UnknownAc, SupplyClassifier.Resolve(PowerSource.Ac, double.PositiveInfinity));
    }
}
