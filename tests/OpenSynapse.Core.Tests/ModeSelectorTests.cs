using OpenSynapse.Core;

namespace OpenSynapse.Core.Tests;

[TestClass]
public sealed class ModeSelectorTests
{
    [DataRow(ModeSelection.Auto, PowerSource.Ac, OperatingMode.Performance)]
    [DataRow(ModeSelection.Auto, PowerSource.Battery, OperatingMode.Quiet)]
    [DataRow(ModeSelection.Auto, PowerSource.Unknown, OperatingMode.Quiet)]
    [DataRow(ModeSelection.Performance, PowerSource.Battery, OperatingMode.Performance)]
    [DataRow(ModeSelection.Quiet, PowerSource.Ac, OperatingMode.Quiet)]
    [TestMethod]
    public void ResolveReturnsExpectedMode(
        ModeSelection selection,
        PowerSource source,
        OperatingMode expected)
    {
        Assert.AreEqual(expected, ModeSelector.Resolve(selection, source));
    }
}
