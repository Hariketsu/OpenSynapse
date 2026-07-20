using OpenSynapse.Core;

namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class ConfigurationStoreTests
{
    private string directory = null!;
    private string configPath = null!;

    [TestInitialize]
    public void Initialize()
    {
        directory = Path.Combine(Path.GetTempPath(), "OpenSynapse.Tests", Guid.NewGuid().ToString("N"));
        configPath = Path.Combine(directory, "config.json");
        Directory.CreateDirectory(directory);
    }

    [TestCleanup]
    public void Cleanup()
    {
        if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
    }

    [TestMethod]
    public void LoadCreatesDefaultsAndMigratesLegacySelection()
    {
        var config = new ConfigurationStore(configPath).Load(ModeSelection.Balanced);

        Assert.AreEqual(OpenSynapseConfig.CurrentSchemaVersion, config.SchemaVersion);
        Assert.AreEqual(ModeSelection.Balanced, config.Selection);
        Assert.AreEqual(50, config.BalancedBatteryThresholdPercent);
        Assert.AreEqual(150, config.InternalDisplayScalePercent);
        Assert.AreEqual(125, config.ExternalDisplayScalePercent);
        Assert.IsTrue(File.Exists(configPath));
    }

    [TestMethod]
    public void SaveAndLoadRoundTripsDisplayPolicy()
    {
        var expected = new OpenSynapseConfig
        {
            Selection = ModeSelection.Quiet,
            BalancedBatteryThresholdPercent = 55,
            InternalDisplayScalePercent = 175,
            ExternalDisplayScalePercent = 150,
            BalancedBrightnessPercent = 65,
            QuietBrightnessPercent = 35,
            BalancedRefreshRateHz = 144,
            QuietRefreshRateHz = 75
        };
        var store = new ConfigurationStore(configPath);

        store.Save(expected);
        var actual = store.Load();

        Assert.AreEqual(expected.Selection, actual.Selection);
        Assert.AreEqual(expected.BalancedBatteryThresholdPercent, actual.BalancedBatteryThresholdPercent);
        Assert.AreEqual(expected.InternalDisplayScalePercent, actual.InternalDisplayScalePercent);
        Assert.AreEqual(expected.ExternalDisplayScalePercent, actual.ExternalDisplayScalePercent);
        Assert.AreEqual(expected.BalancedBrightnessPercent, actual.BalancedBrightnessPercent);
        Assert.AreEqual(expected.QuietBrightnessPercent, actual.QuietBrightnessPercent);
        Assert.AreEqual(expected.BalancedRefreshRateHz, actual.BalancedRefreshRateHz);
        Assert.AreEqual(expected.QuietRefreshRateHz, actual.QuietRefreshRateHz);
    }

    [TestMethod]
    public void LoadRejectsInvalidConfigurationWithoutOverwritingIt()
    {
        const string invalid = "{\"schemaVersion\":1,\"internalDisplayScalePercent\":110}";
        File.WriteAllText(configPath, invalid);

        Assert.ThrowsExactly<InvalidDataException>(() => new ConfigurationStore(configPath).Load());
        Assert.AreEqual(invalid, File.ReadAllText(configPath));
    }

    [TestMethod]
    public void LoadRejectsConfigurationFromANewerSchema()
    {
        File.WriteAllText(
            configPath,
            "{\"schemaVersion\":" + (OpenSynapseConfig.CurrentSchemaVersion + 1) + "}");

        Assert.ThrowsExactly<NotSupportedException>(() => new ConfigurationStore(configPath).Load());
    }
}
