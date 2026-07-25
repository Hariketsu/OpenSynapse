using System.Text.Json;
using System.Text.Json.Serialization;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class OpenSynapseState
{
    public const int CurrentSchemaVersion = 10;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    [JsonPropertyName("selection")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public ModeSelection? LegacySelection { get; set; }
    public string? OriginalPowerPlan { get; set; }
    public string? PerformancePowerPlan { get; set; }
    public string? BalancedPowerPlan { get; set; }
    public string? QuietPowerPlan { get; set; }
    public OperatingMode? ActiveMode { get; set; }
    public int? OriginalBrightness { get; set; }
    public List<AdvancedColorState> AdvancedColors { get; set; } = [];
    public List<DisplayScaleState> DisplayScales { get; set; } = [];
    public List<string> DisabledWakeDevices { get; set; } = [];
    public SmartAutomationState SmartAutomation { get; set; } = new();
    public TemporaryModeState? TemporaryMode { get; set; }
}

internal sealed record AdvancedColorState(string Key, bool Enabled);
internal sealed record DisplayScaleState(string Key, int ScalePercent);

internal sealed class StateStore
{
    private readonly string path;

    public StateStore(string? path = null)
    {
        this.path = path ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenSynapse",
            "state.json");
    }

    public OpenSynapseState Load()
    {
        if (!File.Exists(path)) return new OpenSynapseState();
        try
        {
            var state = JsonSerializer.Deserialize<OpenSynapseState>(File.ReadAllText(path), AgentJson.Options)
                ?? new OpenSynapseState();
            if (state.SchemaVersion > OpenSynapseState.CurrentSchemaVersion)
                throw new NotSupportedException(
                    $"State schema {state.SchemaVersion} is newer than supported schema {OpenSynapseState.CurrentSchemaVersion}.");
            var requiresMigration = state.SchemaVersion < OpenSynapseState.CurrentSchemaVersion;
            state.SchemaVersion = OpenSynapseState.CurrentSchemaVersion;
            state.AdvancedColors ??= [];
            state.DisplayScales ??= [];
            state.DisabledWakeDevices ??= [];
            state.SmartAutomation ??= new SmartAutomationState();
            if (requiresMigration) Save(state);
            return state;
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException("Captured state is not valid JSON and was not overwritten.", ex);
        }
    }

    public void Save(OpenSynapseState state)
    {
        if (state.SchemaVersion > OpenSynapseState.CurrentSchemaVersion)
            throw new NotSupportedException(
                $"State schema {state.SchemaVersion} is newer than supported schema {OpenSynapseState.CurrentSchemaVersion}.");
        state.SchemaVersion = OpenSynapseState.CurrentSchemaVersion;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(state, AgentJson.Options));
        File.Move(temporary, path, true);
    }
}
