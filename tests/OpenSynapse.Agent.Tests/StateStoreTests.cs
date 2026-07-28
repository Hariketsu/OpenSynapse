using System.Text.Json;
using OpenSynapse.Core;

namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class StateStoreTests
{
    private string directory = null!;
    private string statePath = null!;

    [TestInitialize]
    public void Initialize()
    {
        directory = Path.Combine(Path.GetTempPath(), "OpenSynapse.Tests", Guid.NewGuid().ToString("N"));
        statePath = Path.Combine(directory, "state.json");
        Directory.CreateDirectory(directory);
    }

    [TestCleanup]
    public void Cleanup()
    {
        if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
    }

    [TestMethod]
    public void LoadMigratesLegacyNullCollectionsToCurrentSchema()
    {
        File.WriteAllText(statePath, "{\"schemaVersion\":0,\"advancedColors\":null}");

        var state = new StateStore(statePath).Load();

        Assert.AreEqual(OpenSynapseState.CurrentSchemaVersion, state.SchemaVersion);
        Assert.IsNotNull(state.AdvancedColors);
        Assert.IsNotNull(state.DisplayScales);
        Assert.IsNotNull(state.DisabledWakeDevices);
        Assert.IsEmpty(state.AdvancedColors);
        Assert.IsEmpty(state.DisplayScales);
        Assert.IsEmpty(state.DisabledWakeDevices);
        StringAssert.Contains(
            File.ReadAllText(statePath),
            $"\"schemaVersion\":{OpenSynapseState.CurrentSchemaVersion}");
    }

    [TestMethod]
    public void LoadRejectsStateFromANewerSchema()
    {
        File.WriteAllText(
            statePath,
            "{\"schemaVersion\":" + (OpenSynapseState.CurrentSchemaVersion + 1) + "}");

        Assert.ThrowsExactly<NotSupportedException>(() => new StateStore(statePath).Load());
    }

    [TestMethod]
    public void LoadRejectsMalformedCapturedStateWithoutOverwritingIt()
    {
        const string malformed = "{not-json";
        File.WriteAllText(statePath, malformed);

        Assert.ThrowsExactly<InvalidDataException>(() => new StateStore(statePath).Load());
        Assert.AreEqual(malformed, File.ReadAllText(statePath));
    }

    [TestMethod]
    public void SaveWritesTheCurrentSchemaVersion()
    {
        var state = new OpenSynapseState { SchemaVersion = 0 };

        new StateStore(statePath).Save(state);

        using var document = JsonDocument.Parse(File.ReadAllText(statePath));
        Assert.AreEqual(
            OpenSynapseState.CurrentSchemaVersion,
            document.RootElement.GetProperty("schemaVersion").GetInt32());
    }

    [TestMethod]
    public void SaveAndLoadRoundTripsBalancedState()
    {
        var expected = new OpenSynapseState
        {
            ActiveMode = OperatingMode.Balanced,
            BalancedPowerPlan = "11111111-2222-3333-4444-555555555555",
            DisabledWakeDevices = ["HID-compliant mouse"]
        };
        var store = new StateStore(statePath);

        store.Save(expected);
        var actual = store.Load();

        Assert.AreEqual(OperatingMode.Balanced, actual.ActiveMode);
        Assert.AreEqual(expected.BalancedPowerPlan, actual.BalancedPowerPlan);
        CollectionAssert.AreEqual(expected.DisabledWakeDevices, actual.DisabledWakeDevices);
    }
}
