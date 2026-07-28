using OpenSynapse.Core;

namespace OpenSynapse.Core.Tests;

[TestClass]
public sealed class QuietMaintenanceSettingsTests
{
    [TestMethod]
    public void EmptyDisabledAllowlistIsValid()
    {
        new QuietMaintenanceSettings(false, []).Validate();
    }

    [TestMethod]
    public void DuplicateOrUntrimmedNamesAreRejected()
    {
        Assert.ThrowsExactly<InvalidDataException>(
            new QuietMaintenanceSettings(true, ["Mouse", "mouse"]).Validate);
        Assert.ThrowsExactly<InvalidDataException>(
            new QuietMaintenanceSettings(true, [" Mouse"]).Validate);
    }

    [TestMethod]
    public void OversizedAllowlistIsRejected()
    {
        var names = Enumerable.Range(0, 17).Select(index => $"Device {index}").ToArray();

        Assert.ThrowsExactly<InvalidDataException>(
            new QuietMaintenanceSettings(true, names).Validate);
    }
}
