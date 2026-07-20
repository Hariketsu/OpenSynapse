using System.Text.Json;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class OpenSynapseState
{
    public const int CurrentSchemaVersion = 1;

    public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    public ModeSelection Selection { get; set; } = ModeSelection.Auto;
    public string? OriginalPowerPlan { get; set; }
    public string? PerformancePowerPlan { get; set; }
    public string? QuietPowerPlan { get; set; }
    public OperatingMode? ActiveMode { get; set; }
    public int? OriginalBrightness { get; set; }
    public List<AdvancedColorState> AdvancedColors { get; set; } = [];
    public List<DisplayScaleState> DisplayScales { get; set; } = [];
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
            state.SchemaVersion = OpenSynapseState.CurrentSchemaVersion;
            state.AdvancedColors ??= [];
            state.DisplayScales ??= [];
            return state;
        }
        catch (JsonException)
        {
            return new OpenSynapseState();
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
