using OpenSynapse.Core;

namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class DisplayPolicyTests
{
    [TestMethod]
    public void CapturePreservesTheFirstDisplayStateUntilFinalRestore()
    {
        var displaySystem = new FakeDisplaySystem
        {
            Brightness = 82
        };
        displaySystem.Displays["internal"] = (100, true);
        displaySystem.Colors["hdr"] = (true, true);
        displaySystem.Colors["unsupported"] = (false, true);
        var state = new OpenSynapseState();
        var policy = new DisplayPolicy(displaySystem);

        policy.Capture(OperatingMode.Quiet, state);
        displaySystem.Displays["internal"] = (150, true);
        policy.Capture(OperatingMode.Performance, state);

        Assert.AreEqual(82, state.OriginalBrightness);
        CollectionAssert.AreEqual(
            new[] { new AdvancedColorState("hdr", true) },
            state.AdvancedColors);
        CollectionAssert.AreEqual(
            new[] { new DisplayScaleState("internal", 100) },
            state.DisplayScales);
    }

    [TestMethod]
    public void PerformanceTransitionRestoresQuietChangesButRetainsRollbackState()
    {
        var displaySystem = new FakeDisplaySystem
        {
            Brightness = 40
        };
        displaySystem.Displays["internal"] = (150, true);
        displaySystem.Colors["hdr"] = (true, false);
        var state = new OpenSynapseState
        {
            OriginalBrightness = 82,
            AdvancedColors = [new AdvancedColorState("hdr", true)],
            DisplayScales = [new DisplayScaleState("internal", 100)]
        };
        var policy = new DisplayPolicy(displaySystem);

        policy.Apply(OperatingMode.Performance, state, new OpenSynapseConfig());

        Assert.AreEqual(82, displaySystem.Brightness);
        Assert.IsTrue(displaySystem.Colors["hdr"].Enabled);
        Assert.AreEqual(1, displaySystem.MaximumRefreshApplications);
        CollectionAssert.AreEqual(
            new[] { ("internal", 150) },
            displaySystem.ScaleWrites);
        Assert.HasCount(1, state.AdvancedColors);
        Assert.HasCount(1, state.DisplayScales);
        Assert.AreEqual(82, state.OriginalBrightness);
    }

    [TestMethod]
    public void BalancedAppliesLowPowerDisplayPolicy()
    {
        var displaySystem = new FakeDisplaySystem
        {
            Brightness = 82
        };
        displaySystem.Displays["internal"] = (100, true);
        displaySystem.Colors["hdr"] = (true, true);
        var state = new OpenSynapseState();
        var policy = new DisplayPolicy(displaySystem);
        var config = new OpenSynapseConfig
        {
            BalancedBrightnessPercent = 65,
            BalancedRefreshRateHz = 144,
            InternalDisplayScalePercent = 175
        };

        policy.Capture(OperatingMode.Balanced, state);
        policy.Apply(OperatingMode.Balanced, state, config);

        Assert.AreEqual(65, displaySystem.Brightness);
        Assert.IsFalse(displaySystem.Colors["hdr"].Enabled);
        CollectionAssert.AreEqual(new[] { 144 }, displaySystem.FixedRefreshApplications);
        CollectionAssert.AreEqual(new[] { ("internal", 175) }, displaySystem.ScaleWrites);
    }

    [TestMethod]
    public void RestoreClearsOnlyStateConfirmedByReadback()
    {
        var displaySystem = new FakeDisplaySystem
        {
            Brightness = 40
        };
        displaySystem.Displays["internal"] = (150, true);
        displaySystem.Colors["hdr"] = (true, false);
        var state = new OpenSynapseState
        {
            OriginalBrightness = 82,
            AdvancedColors =
            [
                new AdvancedColorState("hdr", true),
                new AdvancedColorState("disconnected-color", true)
            ],
            DisplayScales =
            [
                new DisplayScaleState("internal", 100),
                new DisplayScaleState("disconnected-display", 125)
            ]
        };
        var policy = new DisplayPolicy(displaySystem);

        var firstResult = policy.Restore(state);

        Assert.IsFalse(firstResult);
        Assert.IsNull(state.OriginalBrightness);
        CollectionAssert.AreEqual(
            new[] { new AdvancedColorState("disconnected-color", true) },
            state.AdvancedColors);
        CollectionAssert.AreEqual(
            new[] { new DisplayScaleState("disconnected-display", 125) },
            state.DisplayScales);

        displaySystem.Colors["disconnected-color"] = (true, false);
        displaySystem.Displays["disconnected-display"] = (150, false);

        var secondResult = policy.Restore(state);

        Assert.IsTrue(secondResult);
        Assert.IsEmpty(state.AdvancedColors);
        Assert.IsEmpty(state.DisplayScales);
    }

    [TestMethod]
    public void RestoreReportsPendingWhenRefreshResetFails()
    {
        var displaySystem = new FakeDisplaySystem
        {
            ThrowOnRefreshRestore = true
        };
        var policy = new DisplayPolicy(displaySystem);

        var restored = policy.Restore(new OpenSynapseState());

        Assert.IsFalse(restored);
    }

    private sealed class FakeDisplaySystem : IDisplaySystem
    {
        public Dictionary<string, (bool Supported, bool Enabled)> Colors { get; } = [];
        public Dictionary<string, (int Scale, bool IsInternal)> Displays { get; } = [];
        public List<(string Key, int Percent)> ScaleWrites { get; } = [];
        public List<int> FixedRefreshApplications { get; } = [];
        public int? Brightness { get; set; }
        public int MaximumRefreshApplications { get; private set; }
        public bool ThrowOnRefreshRestore { get; init; }

        public IReadOnlyList<AdvancedColorSnapshot> GetAdvancedColors() => Colors
            .Select(item => new AdvancedColorSnapshot(item.Key, item.Value.Supported, item.Value.Enabled))
            .ToArray();

        public void SetAdvancedColor(string key, bool enabled)
        {
            if (!Colors.TryGetValue(key, out var color)) return;
            Colors[key] = (color.Supported, enabled);
        }

        public int? GetBrightness() => Brightness;

        public void SetBrightness(int percent) => Brightness = percent;

        public IReadOnlyList<ActiveDisplaySnapshot> GetDisplays() => Displays
            .Select(item => new ActiveDisplaySnapshot(item.Key, item.Value.Scale, item.Value.IsInternal))
            .ToArray();

        public void SetDisplayScale(string key, int desiredPercent)
        {
            if (!Displays.TryGetValue(key, out var display)) return;
            ScaleWrites.Add((key, desiredPercent));
            Displays[key] = (desiredPercent, display.IsInternal);
        }

        public void ApplyMaximumRefresh() => MaximumRefreshApplications++;

        public void ApplyFixedRefresh(int targetHz) => FixedRefreshApplications.Add(targetHz);

        public void RestoreRefresh()
        {
            if (ThrowOnRefreshRestore) throw new InvalidOperationException("Refresh reset failed.");
        }
    }
}
