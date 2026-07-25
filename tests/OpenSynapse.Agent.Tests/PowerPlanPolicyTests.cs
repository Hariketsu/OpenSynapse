using OpenSynapse.Core;

namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class PowerPlanPolicyTests
{
    [DataRow("893dee8e-2bef-41e0-89c6-b55d0929964c", 5, 5, 5, 5, 5, 5, false)]
    [DataRow("bc5038f7-23e0-4960-96da-33abaf5935ec", 100, 100, 100, 100, 80, 75, false)]
    [DataRow("36687f9e-e3a5-4dbf-b1dc-15eb381c6863", 0, 20, 50, 70, 90, 95, true)]
    [DataRow("be337238-0d82-4146-a960-4f3749d470c7", 2, 2, 3, 3, 0, 0, true)]
    [DataRow("94d3a615-a899-4ac5-ae2b-e4d8f634367f", 1, 1, 1, 0, 0, 0, true)]
    [DataRow("12bbebe6-58d6-4636-95bb-3217ef867c1a", 0, 1, 1, 2, 3, 3, true)]
    [DataRow("ee12f906-d277-404b-b6da-e5fa1a576df5", 0, 1, 1, 2, 2, 2, true)]
    [DataRow("3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e", 900, 300, 600, 300, 300, 120, false)]
    [DataRow("48e6b7a6-50f5-4782-a5d4-53bb8f07e226", 0, 1, 1, 1, 1, 1, true)]
    [DataRow("e69653ca-cf7f-4f05-aa73-cb833fa90ad4", 0, 20, 0, 50, 0, 100, true)]
    [DataRow("29f6c1db-86da-48c5-9fdb-f2b67b1f44da", 0, 900, 900, 600, 600, 180, false)]
    [DataRow("9d7815a6-7ee4-497e-8888-515a05f02364", 0, 3600, 3600, 1800, 1800, 900, false)]
    [DataRow("5ca83367-6e45-459f-a27b-476b1d01c936", 1, 1, 1, 2, 1, 2, false)]
    [TestMethod]
    public void PolicyMatchesTheReferenceValues(
        string settingId,
        int performanceAc,
        int performanceDc,
        int balancedAc,
        int balancedDc,
        int quietAc,
        int quietDc,
        bool optional)
    {
        var setting = PowerPlanManager.PolicySettings.Single(item => item.Setting == settingId);
        var expectedSubgroup = settingId switch
        {
            "893dee8e-2bef-41e0-89c6-b55d0929964c"
                or "bc5038f7-23e0-4960-96da-33abaf5935ec"
                or "36687f9e-e3a5-4dbf-b1dc-15eb381c6863"
                or "be337238-0d82-4146-a960-4f3749d470c7"
                or "94d3a615-a899-4ac5-ae2b-e4d8f634367f" => "54533251-82be-4824-96c1-47b60b740d00",
            "12bbebe6-58d6-4636-95bb-3217ef867c1a" => "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1",
            "ee12f906-d277-404b-b6da-e5fa1a576df5" => "501a4d13-42af-4429-9fd1-a8218c268e20",
            "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" => "7516b95f-f776-4464-8c53-06167f40cc99",
            "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" => "2a737441-1930-4402-8d77-b2bebba308a3",
            "e69653ca-cf7f-4f05-aa73-cb833fa90ad4" => "de830923-a562-41af-a086-e3a2c6bad2da",
            "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
                or "9d7815a6-7ee4-497e-8888-515a05f02364" => "238c9fa8-0aad-41ed-83f4-97be242c8f20",
            "5ca83367-6e45-459f-a27b-476b1d01c936" => "4f971e89-eebd-4455-a8de-9e59040e7347",
            _ => throw new AssertFailedException($"Unexpected setting {settingId}.")
        };

        Assert.AreEqual(expectedSubgroup, setting.Subgroup);
        Assert.AreEqual(new PowerPlanValues(performanceAc, performanceDc), setting.GetValues(OperatingMode.Performance));
        Assert.AreEqual(new PowerPlanValues(balancedAc, balancedDc), setting.GetValues(OperatingMode.Balanced));
        Assert.AreEqual(new PowerPlanValues(quietAc, quietDc), setting.GetValues(OperatingMode.Quiet));
        Assert.AreEqual(optional, setting.Optional);
        Assert.HasCount(25, PowerPlanManager.PolicySettings);
    }

    [TestMethod]
    public void LatestReferenceSettingsAreScopedToTheCorrectProfile()
    {
        var processor = "54533251-82be-4824-96c1-47b60b740d00";
        var hyperOnly = new Dictionary<string, (PowerPlanValues Values, int Expected)>
        {
            ["893dee8e-2bef-41e0-89c6-b55d0929964d"] = (new(5, 5), 5),
            ["893dee8e-2bef-41e0-89c6-b55d0929964e"] = (new(5, 5), 5),
            ["bc5038f7-23e0-4960-96da-33abaf5935ed"] = (new(100, 100), 100),
            ["bc5038f7-23e0-4960-96da-33abaf5935ee"] = (new(100, 100), 100),
            ["45bcc044-d885-43e2-8605-ee0ec6e96b59"] = (new(100, 100), 100),
            ["8baa4a8a-14c6-4451-8e8b-14bdbd197537"] = (new(1, 1), 1),
            ["465e1f50-b610-473a-ab58-00d1077dc418"] = (new(2, 2), 2),
            ["465e1f50-b610-473a-ab58-00d1077dc419"] = (new(3, 3), 3),
            ["0cc5b647-c1df-4637-891a-dec35c318583"] = (new(100, 100), 100),
            ["0cc5b647-c1df-4637-891a-dec35c318584"] = (new(0, 0), 0)
        };

        foreach (var item in hyperOnly)
        {
            var setting = PowerPlanManager.PolicySettings.Single(value => value.Setting == item.Key);
            Assert.AreEqual(processor, setting.Subgroup);
            Assert.AreEqual(item.Value.Values, setting.GetValues(OperatingMode.Performance));
            Assert.AreEqual(OperatingMode.Performance, setting.OnlyMode);
        }

        var wakeTimers = PowerPlanManager.PolicySettings.Single(value => value.Setting == "bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d");
        var standbyNetwork = PowerPlanManager.PolicySettings.Single(value => value.Setting == "f15576e8-98b7-4186-b944-eafa664402d9");
        Assert.AreEqual(OperatingMode.Quiet, wakeTimers.OnlyMode);
        Assert.AreEqual(OperatingMode.Quiet, standbyNetwork.OnlyMode);
        Assert.AreEqual(new PowerPlanValues(0, 0), wakeTimers.GetValues(OperatingMode.Quiet));
        Assert.AreEqual(new PowerPlanValues(0, 0), standbyNetwork.GetValues(OperatingMode.Quiet));
    }
}
