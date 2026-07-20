using System.Text.RegularExpressions;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal readonly record struct PowerPlanValues(int Ac, int Dc);

internal sealed record PowerPlanSetting(
    string Subgroup,
    string Setting,
    PowerPlanValues Performance,
    PowerPlanValues Balanced,
    PowerPlanValues Quiet,
    bool Optional)
{
    public PowerPlanValues GetValues(OperatingMode mode) => mode switch
    {
        OperatingMode.Performance => Performance,
        OperatingMode.Balanced => Balanced,
        OperatingMode.Quiet => Quiet,
        _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, "Unsupported operating mode.")
    };
}

internal sealed partial class PowerPlanManager
{
    private const string BalancedScheme = "381b4222-f694-41f0-9685-ff5bb260df2e";
    private readonly string powerCfg = Path.Combine(Environment.SystemDirectory, "powercfg.exe");

    internal static IReadOnlyList<PowerPlanSetting> PolicySettings { get; } =
    [
        new("54533251-82be-4824-96c1-47b60b740d00", "893dee8e-2bef-41e0-89c6-b55d0929964c", new(5, 5), new(5, 5), new(5, 5), false),
        new("54533251-82be-4824-96c1-47b60b740d00", "bc5038f7-23e0-4960-96da-33abaf5935ec", new(100, 100), new(100, 100), new(80, 80), false),
        new("54533251-82be-4824-96c1-47b60b740d00", "36687f9e-e3a5-4dbf-b1dc-15eb381c6863", new(0, 20), new(50, 70), new(90, 90), true),
        new("54533251-82be-4824-96c1-47b60b740d00", "be337238-0d82-4146-a960-4f3749d470c7", new(2, 2), new(3, 3), new(0, 0), true),
        new("54533251-82be-4824-96c1-47b60b740d00", "94d3a615-a899-4ac5-ae2b-e4d8f634367f", new(1, 1), new(1, 0), new(0, 0), true),
        new("19cbb8fa-5279-450e-9fac-8a3d5fedd0c1", "12bbebe6-58d6-4636-95bb-3217ef867c1a", new(0, 1), new(1, 2), new(3, 3), true),
        new("501a4d13-42af-4429-9fd1-a8218c268e20", "ee12f906-d277-404b-b6da-e5fa1a576df5", new(0, 1), new(1, 2), new(2, 2), true),
        new("7516b95f-f776-4464-8c53-06167f40cc99", "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e", new(900, 300), new(600, 300), new(300, 120), false),
        new("2a737441-1930-4402-8d77-b2bebba308a3", "48e6b7a6-50f5-4782-a5d4-53bb8f07e226", new(0, 1), new(1, 1), new(1, 1), true),
        new("de830923-a562-41af-a086-e3a2c6bad2da", "e69653ca-cf7f-4f05-aa73-cb833fa90ad4", new(0, 20), new(0, 50), new(0, 100), true),
        new("238c9fa8-0aad-41ed-83f4-97be242c8f20", "29f6c1db-86da-48c5-9fdb-f2b67b1f44da", new(0, 900), new(900, 600), new(600, 180), false),
        new("238c9fa8-0aad-41ed-83f4-97be242c8f20", "9d7815a6-7ee4-497e-8888-515a05f02364", new(0, 3600), new(3600, 1800), new(1800, 900), false),
        new("4f971e89-eebd-4455-a8de-9e59040e7347", "5ca83367-6e45-459f-a27b-476b1d01c936", new(1, 1), new(1, 2), new(1, 2), false)
    ];

    public string GetActiveGuid() => ParseGuid(Run("/getactivescheme"));

    public string Apply(OperatingMode mode, OpenSynapseState state)
    {
        state.OriginalPowerPlan ??= GetActiveGuid();
        EnsurePlans(state);
        var target = mode switch
        {
            OperatingMode.Performance => state.PerformancePowerPlan!,
            OperatingMode.Balanced => state.BalancedPowerPlan!,
            OperatingMode.Quiet => state.QuietPowerPlan!,
            _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, "Unsupported operating mode.")
        };
        Run("/setactive", target);
        var active = GetActiveGuid();
        if (!active.Equals(target, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Power plan activation failed: expected {target}, got {active}.");
        return active;
    }

    public void Restore(OpenSynapseState state)
    {
        if (string.IsNullOrWhiteSpace(state.OriginalPowerPlan)) return;
        if (!Exists(state.OriginalPowerPlan))
            throw new InvalidOperationException($"Original power plan {state.OriginalPowerPlan} no longer exists.");
        Run("/setactive", state.OriginalPowerPlan);
        var active = GetActiveGuid();
        if (!active.Equals(state.OriginalPowerPlan, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Power plan restoration failed: expected {state.OriginalPowerPlan}, got {active}.");
        state.OriginalPowerPlan = null;
    }

    private void EnsurePlans(OpenSynapseState state)
    {
        if (!Exists(state.PerformancePowerPlan))
        {
            var plan = Duplicate("OpenSynapse Performance");
            Configure(plan, OperatingMode.Performance);
            state.PerformancePowerPlan = plan;
        }
        if (!Exists(state.BalancedPowerPlan))
        {
            var plan = Duplicate("OpenSynapse Balanced");
            Configure(plan, OperatingMode.Balanced);
            state.BalancedPowerPlan = plan;
        }
        if (!Exists(state.QuietPowerPlan))
        {
            var plan = Duplicate("OpenSynapse Quiet");
            Configure(plan, OperatingMode.Quiet);
            state.QuietPowerPlan = plan;
        }
    }

    private string Duplicate(string name)
    {
        var guid = ParseGuid(Run("/duplicatescheme", BalancedScheme));
        Run("/changename", guid, name, "Managed by OpenSynapse");
        return guid;
    }

    private void Configure(string guid, OperatingMode mode)
    {
        foreach (var setting in PolicySettings)
        {
            var values = setting.GetValues(mode);
            try
            {
                Run("/setacvalueindex", guid, setting.Subgroup, setting.Setting, values.Ac.ToString());
                Run("/setdcvalueindex", guid, setting.Subgroup, setting.Setting, values.Dc.ToString());
            }
            catch when (setting.Optional) { }
        }
    }

    private bool Exists(string? guid) => !string.IsNullOrWhiteSpace(guid)
        && Run("/list").Contains(guid, StringComparison.OrdinalIgnoreCase);

    private string Run(params string[] arguments) => ProcessRunner.Run(powerCfg, arguments);

    private static string ParseGuid(string text)
    {
        var match = GuidRegex().Match(text);
        if (!match.Success) throw new InvalidOperationException($"Cannot parse power plan GUID from: {text}");
        return match.Value.ToLowerInvariant();
    }

    [GeneratedRegex("[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")]
    private static partial Regex GuidRegex();
}
