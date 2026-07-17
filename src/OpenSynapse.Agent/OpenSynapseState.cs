using System.Text.Json;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class OpenSynapseState
{
    public ModeSelection Selection { get; set; } = ModeSelection.Auto;
    public string? OriginalPowerPlan { get; set; }
    public string? PerformancePowerPlan { get; set; }
    public string? QuietPowerPlan { get; set; }
    public OperatingMode? ActiveMode { get; set; }
    public int? OriginalBrightness { get; set; }
    public List<AdvancedColorState> AdvancedColors { get; set; } = [];
}

internal sealed record AdvancedColorState(string Key, bool Enabled);

internal sealed class StateStore
{
    private readonly string path = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "OpenSynapse",
        "state.json");

    public OpenSynapseState Load()
    {
        if (!File.Exists(path)) return new OpenSynapseState();
        try
        {
            return JsonSerializer.Deserialize<OpenSynapseState>(File.ReadAllText(path), AgentJson.Options)
                ?? new OpenSynapseState();
        }
        catch (JsonException)
        {
            return new OpenSynapseState();
        }
    }

    public void Save(OpenSynapseState state)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(state, AgentJson.Options));
        File.Move(temporary, path, true);
    }
}
