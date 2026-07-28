namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class PowerPlanLifecycleTests
{
    private const string Original = "11111111-1111-1111-1111-111111111111";
    private const string Performance = "22222222-2222-2222-2222-222222222222";
    private const string Balanced = "33333333-3333-3333-3333-333333333333";
    private const string Quiet = "44444444-4444-4444-4444-444444444444";

    [TestMethod]
    public void DeleteManagedPlansVerifiesRemovalBeforeClearingState()
    {
        var plans = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            Original, Performance, Balanced, Quiet
        };
        var deleted = new List<string>();
        var manager = new PowerPlanManager(arguments => RunFake(arguments, plans, deleted, Original));
        var state = new OpenSynapseState
        {
            PerformancePowerPlan = Performance,
            BalancedPowerPlan = Balanced,
            QuietPowerPlan = Quiet
        };

        manager.DeleteManagedPlans(state);

        Assert.IsNull(state.PerformancePowerPlan);
        Assert.IsNull(state.BalancedPowerPlan);
        Assert.IsNull(state.QuietPowerPlan);
        CollectionAssert.AreEquivalent(new[] { Performance, Balanced, Quiet }, deleted);
        Assert.IsTrue(plans.SetEquals([Original]));
    }

    [TestMethod]
    public void DeleteManagedPlansRefusesToDeleteTheActivePlan()
    {
        var plans = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Performance };
        var state = new OpenSynapseState { PerformancePowerPlan = Performance };
        var manager = new PowerPlanManager(arguments => RunFake(arguments, plans, [], Performance));

        Assert.ThrowsExactly<InvalidOperationException>(() => manager.DeleteManagedPlans(state));
        Assert.AreEqual(Performance, state.PerformancePowerPlan);
        Assert.Contains(Performance, plans);
    }

    [TestMethod]
    public void DeleteManagedPlansRefusesToDeleteAnUnmarkedPlan()
    {
        var plans = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Original, Performance };
        var state = new OpenSynapseState { PerformancePowerPlan = Performance };
        var manager = new PowerPlanManager(arguments =>
            RunFake(arguments, plans, [], Original, performanceName: "Personal Plan"));

        Assert.ThrowsExactly<InvalidOperationException>(() => manager.DeleteManagedPlans(state));
        Assert.AreEqual(Performance, state.PerformancePowerPlan);
        Assert.Contains(Performance, plans);
    }

    private static string RunFake(
        IReadOnlyList<string> arguments,
        HashSet<string> plans,
        List<string> deleted,
        string active,
        string performanceName = "OpenSynapse Performance")
    {
        return arguments[0] switch
        {
            "/getactivescheme" => $"Power Scheme GUID: {active}",
            "/list" => string.Join(Environment.NewLine, plans.Select(guid =>
                $"Power Scheme GUID: {guid} ({GetName(guid, performanceName)})")),
            "/delete" => Delete(arguments[1], plans, deleted),
            _ => throw new AssertFailedException($"Unexpected powercfg call: {string.Join(' ', arguments)}")
        };
    }

    private static string GetName(string guid, string performanceName) => guid switch
    {
        Performance => performanceName,
        Balanced => "OpenSynapse Balanced",
        Quiet => "OpenSynapse Quiet",
        _ => "Original"
    };

    private static string Delete(string guid, HashSet<string> plans, List<string> deleted)
    {
        plans.Remove(guid);
        deleted.Add(guid);
        return string.Empty;
    }
}
