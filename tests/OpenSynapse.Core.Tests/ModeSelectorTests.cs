using OpenSynapse.Core;

namespace OpenSynapse.Core.Tests;

[TestClass]
public sealed class ModeSelectorTests
{
    [DataRow(ModeSelection.Auto, SupplyType.HighPowerAc, OperatingMode.Performance)]
    [DataRow(ModeSelection.Auto, SupplyType.LowPowerPd, OperatingMode.Quiet)]
    [DataRow(ModeSelection.Auto, SupplyType.UnknownAc, OperatingMode.Quiet)]
    [DataRow(ModeSelection.Auto, SupplyType.Battery, OperatingMode.Quiet)]
    [DataRow(ModeSelection.Auto, SupplyType.Unknown, OperatingMode.Quiet)]
    [DataRow(ModeSelection.Performance, SupplyType.Battery, OperatingMode.Performance)]
    [DataRow(ModeSelection.Quiet, SupplyType.HighPowerAc, OperatingMode.Quiet)]
    [TestMethod]
    public void ResolveReturnsExpectedMode(
        ModeSelection selection,
        SupplyType supplyType,
        OperatingMode expected)
    {
        var snapshot = new PowerSnapshot(PowerSource.Unknown, supplyType);

        Assert.AreEqual(expected, ModeSelector.Resolve(selection, snapshot));
    }

    [DataRow(49, OperatingMode.Quiet)]
    [DataRow(50, OperatingMode.Balanced)]
    [DataRow(100, OperatingMode.Balanced)]
    [DataRow(null, OperatingMode.Quiet)]
    [TestMethod]
    public void BalancedRequiresAtLeastFiftyPercentBattery(
        int? batteryPercent,
        OperatingMode expected)
    {
        var snapshot = new PowerSnapshot(PowerSource.Ac, SupplyType.LowPowerPd, batteryPercent);

        Assert.AreEqual(expected, ModeSelector.Resolve(ModeSelection.Balanced, snapshot));
        Assert.AreEqual(expected == OperatingMode.Balanced, ModeSelector.IsBalancedEligible(snapshot));
    }

    [TestMethod]
    public void BalancedUsesConfiguredBatteryThreshold()
    {
        var snapshot = new PowerSnapshot(PowerSource.Battery, SupplyType.Battery, 54);

        Assert.AreEqual(OperatingMode.Quiet, ModeSelector.Resolve(ModeSelection.Balanced, snapshot, 55));
        Assert.AreEqual(OperatingMode.Balanced, ModeSelector.Resolve(ModeSelection.Balanced, snapshot, 54));
    }
}
