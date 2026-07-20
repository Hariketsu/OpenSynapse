using System.Text.Json;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class OpenSynapseConfig
{
    private static readonly int[] AllowedDisplayScales =
    [
        100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500
    ];

    public const int CurrentSchemaVersion = 2;

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

    public void Validate()
    {
        if (!Enum.IsDefined(Selection))
            throw new InvalidDataException($"Unsupported mode selection {Selection}.");
        if (!Enum.IsDefined(RefreshPolicy))
            throw new InvalidDataException($"Unsupported refresh policy {RefreshPolicy}.");
        if (BalancedBatteryThresholdPercent is < 0 or > 100)
            throw new InvalidDataException("Balanced battery threshold must be between 0 and 100 percent.");
        ValidateScale(InternalDisplayScalePercent, nameof(InternalDisplayScalePercent));
        ValidateScale(ExternalDisplayScalePercent, nameof(ExternalDisplayScalePercent));
        ValidatePercentage(BalancedBrightnessPercent, nameof(BalancedBrightnessPercent));
        ValidatePercentage(QuietBrightnessPercent, nameof(QuietBrightnessPercent));
        ValidateRefreshRate(BalancedRefreshRateHz, nameof(BalancedRefreshRateHz));
        ValidateRefreshRate(QuietRefreshRateHz, nameof(QuietRefreshRateHz));
    }

    private static void ValidateScale(int value, string name)
    {
        if (!AllowedDisplayScales.Contains(value))
            throw new InvalidDataException($"{name} must be a supported Windows scale percentage.");
    }

    private static void ValidatePercentage(int value, string name)
    {
        if (value is < 0 or > 100)
            throw new InvalidDataException($"{name} must be between 0 and 100 percent.");
    }

    private static void ValidateRefreshRate(int value, string name)
    {
        if (value is < 24 or > 1000)
            throw new InvalidDataException($"{name} must be between 24 and 1000 Hz.");
    }
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
