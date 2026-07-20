using System.Text.Json;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class OpenSynapseConfig
{
    public const int CurrentSchemaVersion = 3;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public ModeSelection Selection { get; set; } = ModeSelection.Auto;
    public int BalancedBatteryThresholdPercent { get; set; } = 50;
    public bool ManageAdvancedColor { get; set; } = true;
    public bool ManageBrightness { get; set; } = true;
    public bool ManageDisplayScaling { get; set; } = true;
    public RefreshPolicy RefreshPolicy { get; set; } = RefreshPolicy.FollowMode;
    public int InternalDisplayScalePercent { get; set; } = 150;
    public int ExternalDisplayScalePercent { get; set; } = 125;
    public int BalancedBrightnessPercent { get; set; } = 60;
    public int QuietBrightnessPercent { get; set; } = 40;
    public int BalancedRefreshRateHz { get; set; } = 120;
    public int QuietRefreshRateHz { get; set; } = 60;
    public bool ManageWakeDevices { get; set; }
    public List<string> QuietWakeDeviceNames { get; set; } = [];

    public void Validate()
    {
        if (!Enum.IsDefined(Selection))
            throw new InvalidDataException($"Unsupported mode selection {Selection}.");
        ToDisplayPolicySettings().Validate();
        ToQuietMaintenanceSettings().Validate();
    }

    public DisplayPolicySettings ToDisplayPolicySettings() => new(
        BalancedBatteryThresholdPercent,
        ManageAdvancedColor,
        ManageBrightness,
        ManageDisplayScaling,
        RefreshPolicy,
        InternalDisplayScalePercent,
        ExternalDisplayScalePercent,
        BalancedBrightnessPercent,
        QuietBrightnessPercent,
        BalancedRefreshRateHz,
        QuietRefreshRateHz);

    public OpenSynapseConfig WithDisplayPolicy(DisplayPolicySettings settings)
    {
        settings.Validate();
        var updated = Copy();
        updated.BalancedBatteryThresholdPercent = settings.BalancedBatteryThresholdPercent;
        updated.ManageAdvancedColor = settings.ManageAdvancedColor;
        updated.ManageBrightness = settings.ManageBrightness;
        updated.ManageDisplayScaling = settings.ManageDisplayScaling;
        updated.RefreshPolicy = settings.RefreshPolicy;
        updated.InternalDisplayScalePercent = settings.InternalDisplayScalePercent;
        updated.ExternalDisplayScalePercent = settings.ExternalDisplayScalePercent;
        updated.BalancedBrightnessPercent = settings.BalancedBrightnessPercent;
        updated.QuietBrightnessPercent = settings.QuietBrightnessPercent;
        updated.BalancedRefreshRateHz = settings.BalancedRefreshRateHz;
        updated.QuietRefreshRateHz = settings.QuietRefreshRateHz;
        return updated;
    }

    public QuietMaintenanceSettings ToQuietMaintenanceSettings() => new(
        ManageWakeDevices,
        QuietWakeDeviceNames.AsReadOnly());

    public OpenSynapseConfig WithQuietMaintenance(QuietMaintenanceSettings settings)
    {
        settings.Validate();
        var updated = Copy();
        updated.ManageWakeDevices = settings.ManageWakeDevices;
        updated.QuietWakeDeviceNames = [.. settings.WakeDeviceNames];
        return updated;
    }

    private OpenSynapseConfig Copy() => new()
    {
        SchemaVersion = SchemaVersion,
        Selection = Selection,
        BalancedBatteryThresholdPercent = BalancedBatteryThresholdPercent,
        ManageAdvancedColor = ManageAdvancedColor,
        ManageBrightness = ManageBrightness,
        ManageDisplayScaling = ManageDisplayScaling,
        RefreshPolicy = RefreshPolicy,
        InternalDisplayScalePercent = InternalDisplayScalePercent,
        ExternalDisplayScalePercent = ExternalDisplayScalePercent,
        BalancedBrightnessPercent = BalancedBrightnessPercent,
        QuietBrightnessPercent = QuietBrightnessPercent,
        BalancedRefreshRateHz = BalancedRefreshRateHz,
        QuietRefreshRateHz = QuietRefreshRateHz,
        ManageWakeDevices = ManageWakeDevices,
        QuietWakeDeviceNames = [.. QuietWakeDeviceNames]
    };
}

internal sealed class ConfigurationStore
{
    private readonly string path;

    public ConfigurationStore(string? path = null)
    {
        this.path = path ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenSynapse",
            "config.json");
    }

    public OpenSynapseConfig Load(ModeSelection? legacySelection = null)
    {
        if (!File.Exists(path))
        {
            var created = new OpenSynapseConfig
            {
                Selection = legacySelection ?? ModeSelection.Auto
            };
            Save(created);
            return created;
        }

        OpenSynapseConfig config;
        try
        {
            config = JsonSerializer.Deserialize<OpenSynapseConfig>(File.ReadAllText(path), AgentJson.Options)
                ?? throw new InvalidDataException("Configuration file is empty.");
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException("Configuration file is not valid JSON and was not overwritten.", ex);
        }

        if (config.SchemaVersion > OpenSynapseConfig.CurrentSchemaVersion)
            throw new NotSupportedException(
                $"Configuration schema {config.SchemaVersion} is newer than supported schema {OpenSynapseConfig.CurrentSchemaVersion}.");
        var requiresMigration = config.SchemaVersion < OpenSynapseConfig.CurrentSchemaVersion;
        config.SchemaVersion = OpenSynapseConfig.CurrentSchemaVersion;
        config.QuietWakeDeviceNames ??= [];
        config.Validate();
        if (requiresMigration) Save(config);
        return config;
    }

    public void Save(OpenSynapseConfig config)
    {
        if (config.SchemaVersion > OpenSynapseConfig.CurrentSchemaVersion)
            throw new NotSupportedException(
                $"Configuration schema {config.SchemaVersion} is newer than supported schema {OpenSynapseConfig.CurrentSchemaVersion}.");
        config.SchemaVersion = OpenSynapseConfig.CurrentSchemaVersion;
        config.Validate();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(config, AgentJson.Options));
        File.Move(temporary, path, true);
    }
}
