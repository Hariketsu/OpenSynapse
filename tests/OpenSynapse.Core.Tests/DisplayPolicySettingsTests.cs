using OpenSynapse.Core;

namespace OpenSynapse.Core.Tests;

[TestClass]
public sealed class DisplayPolicySettingsTests
{
    [TestMethod]
    public void ValidSettingsAreAccepted()
    {
        CreateValid().Validate();
    }

    [TestMethod]
    public void UnsupportedScaleIsRejected()
    {
        var settings = CreateValid() with { InternalDisplayScalePercent = 110 };

        Assert.ThrowsExactly<InvalidDataException>(settings.Validate);
    }

    [TestMethod]
    public void OutOfRangeValuesAreRejected()
    {
        Assert.ThrowsExactly<InvalidDataException>(
            (CreateValid() with { BalancedBatteryThresholdPercent = 101 }).Validate);
        Assert.ThrowsExactly<InvalidDataException>(
            (CreateValid() with { QuietBrightnessPercent = -1 }).Validate);
        Assert.ThrowsExactly<InvalidDataException>(
            (CreateValid() with { BalancedRefreshRateHz = 23 }).Validate);
    }

    private static DisplayPolicySettings CreateValid() => new(
        50,
        true,
        true,
        true,
        RefreshPolicy.FollowMode,
        150,
        125,
        60,
        40,
        120,
        60);
}
