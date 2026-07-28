using OpenSynapse.Core;

namespace OpenSynapse.Core.Tests;

[TestClass]
public sealed class SmartAutomationTests
{
    private static readonly SmartAutomationSettings Settings = new(
        MinimumDwellSeconds: 0,
        ApplicationRules:
        [
            new ApplicationRule("blender", ApplicationRuleProfile.Performance, ApplicationRuleScope.Foreground),
            new ApplicationRule("Code", ApplicationRuleProfile.Balanced, ApplicationRuleScope.Foreground)
        ],
        HyperProcessNames: ["Resolve"],
        BalanceProcessNames: ["WINWORD"],
        IgnoredFullscreenProcesses: ["explorer"]);

    [TestMethod]
    public void HighPowerAcStartsAtBalanceAndPromotesAfterThreeLoadSamples()
    {
        var state = new SmartAutomationState();
        var now = DateTimeOffset.UtcNow;

        var first = Evaluate(state, now, SupplyType.HighPowerAc, 20, "chrome");
        var second = Evaluate(state, now.AddSeconds(5), SupplyType.HighPowerAc, 50, "chrome");
        var third = Evaluate(state, now.AddSeconds(10), SupplyType.HighPowerAc, 50, "chrome");
        var fourth = Evaluate(state, now.AddSeconds(15), SupplyType.HighPowerAc, 50, "chrome");

        Assert.AreEqual(OperatingMode.Balanced, first.Mode);
        Assert.AreEqual(OperatingMode.Balanced, second.Mode);
        Assert.AreEqual(OperatingMode.Balanced, third.Mode);
        Assert.AreEqual(OperatingMode.Performance, fourth.Mode);
        Assert.IsTrue(fourth.Changed);
    }

    [TestMethod]
    public void PerformanceRulePromotesAfterTwoSamples()
    {
        var state = new SmartAutomationState();
        var now = DateTimeOffset.UtcNow;

        Evaluate(state, now, SupplyType.HighPowerAc, 10, "blender");
        var second = Evaluate(state, now.AddSeconds(5), SupplyType.HighPowerAc, 10, "blender");
        var third = Evaluate(state, now.AddSeconds(10), SupplyType.HighPowerAc, 10, "blender");

        Assert.AreEqual(OperatingMode.Balanced, second.Mode);
        Assert.AreEqual(OperatingMode.Performance, third.Mode);
    }

    [TestMethod]
    public void PortablePowerNeverPromotesToPerformanceAndLowBatteryStaysQuiet()
    {
        var state = new SmartAutomationState();
        var now = DateTimeOffset.UtcNow;

        var first = Evaluate(state, now, SupplyType.LowPowerPd, 55, "blender");
        for (var index = 1; index <= 8; index++)
            Evaluate(state, now.AddSeconds(index * 5), SupplyType.LowPowerPd, 60, "blender");

        Assert.AreEqual(OperatingMode.Quiet, first.Mode);
        Assert.AreNotEqual(OperatingMode.Performance, state.CurrentMode);

        var lowBattery = Evaluate(state, now.AddMinutes(1), SupplyType.LowPowerPd, 60, "Code", 49);
        Assert.AreEqual(OperatingMode.Quiet, lowBattery.Mode);
    }

    [TestMethod]
    public void FullscreenShellProcessDoesNotPromoteOnWindowSizeAlone()
    {
        var state = new SmartAutomationState();
        var decision = Evaluate(
            state,
            DateTimeOffset.UtcNow,
            SupplyType.HighPowerAc,
            5,
            "explorer",
            fullscreen: true,
            gpuPercent: 90);

        Assert.AreEqual(OperatingMode.Balanced, decision.Mode);
    }

    private static SmartAutomationDecision Evaluate(
        SmartAutomationState state,
        DateTimeOffset now,
        SupplyType supply,
        double cpu,
        string process,
        int battery = 100,
        bool fullscreen = false,
        double gpuPercent = 0) =>
        SmartAutomationEngine.Evaluate(
            new SmartAutomationInput(supply, battery, cpu, gpuPercent, process, fullscreen, false),
            Settings,
            state,
            now);
}
