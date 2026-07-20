using System.Text.Json;

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
        Assert.IsEmpty(state.AdvancedColors);
        Assert.IsEmpty(state.DisplayScales);
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
    public void SaveWritesTheCurrentSchemaVersion()
    {
        var state = new OpenSynapseState { SchemaVersion = 0 };

        new StateStore(statePath).Save(state);

        using var document = JsonDocument.Parse(File.ReadAllText(statePath));
        Assert.AreEqual(
            OpenSynapseState.CurrentSchemaVersion,
            document.RootElement.GetProperty("schemaVersion").GetInt32());
    }
}
