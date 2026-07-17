using System.Text.RegularExpressions;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed partial class PowerPlanManager
{
    private const string Balanced = "381b4222-f694-41f0-9685-ff5bb260df2e";
    private readonly string powerCfg = Path.Combine(Environment.SystemDirectory, "powercfg.exe");

    private static readonly (string Subgroup, string Setting, int PerfAc, int PerfDc, int QuietAc, int QuietDc, bool Optional)[] Settings =
    [
        ("54533251-82be-4824-96c1-47b60b740d00", "893dee8e-2bef-41e0-89c6-b55d0929964c", 5, 5, 5, 5, false),
        ("54533251-82be-4824-96c1-47b60b740d00", "bc5038f7-23e0-4960-96da-33abaf5935ec", 100, 100, 80, 80, false),
        ("54533251-82be-4824-96c1-47b60b740d00", "36687f9e-e3a5-4dbf-b1dc-15eb381c6863", 0, 20, 90, 90, true),
        ("54533251-82be-4824-96c1-47b60b740d00", "be337238-0d82-4146-a960-4f3749d470c7", 2, 2, 0, 0, true),
        ("54533251-82be-4824-96c1-47b60b740d00", "94d3a615-a899-4ac5-ae2b-e4d8f634367f", 1, 1, 0, 0, true),
        ("19cbb8fa-5279-450e-9fac-8a3d5fedd0c1", "12bbebe6-58d6-4636-95bb-3217ef867c1a", 0, 1, 3, 3, true),
        ("501a4d13-42af-4429-9fd1-a8218c268e20", "ee12f906-d277-404b-b6da-e5fa1a576df5", 0, 1, 2, 2, true),
        ("7516b95f-f776-4464-8c53-06167f40cc99", "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e", 0, 300, 300, 120, false),
        ("2a737441-1930-4402-8d77-b2bebba308a3", "48e6b7a6-50f5-4782-a5d4-53bb8f07e226", 0, 1, 1, 1, true),
        ("de830923-a562-41af-a086-e3a2c6bad2da", "e69653ca-cf7f-4f05-aa73-cb833fa90ad4", 0, 20, 0, 100, true),
        ("238c9fa8-0aad-41ed-83f4-97be242c8f20", "29f6c1db-86da-48c5-9fdb-f2b67b1f44da", 0, 900, 600, 180, false),
        ("238c9fa8-0aad-41ed-83f4-97be242c8f20", "9d7815a6-7ee4-497e-8888-515a05f02364", 0, 3600, 1800, 900, false),
        ("4f971e89-eebd-4455-a8de-9e59040e7347", "5ca83367-6e45-459f-a27b-476b1d01c936", 1, 1, 1, 2, false)
    ];

    public string GetActiveGuid() => ParseGuid(Run("/getactivescheme"));

    public string Apply(OperatingMode mode, OpenSynapseState state)
    {
        state.OriginalPowerPlan ??= GetActiveGuid();
        EnsurePlans(state);
        var target = mode == OperatingMode.Performance ? state.PerformancePowerPlan! : state.QuietPowerPlan!;
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
        if (!Exists(state.QuietPowerPlan))
        {
            var plan = Duplicate("OpenSynapse Quiet");
            Configure(plan, OperatingMode.Quiet);
            state.QuietPowerPlan = plan;
        }
    }

    private string Duplicate(string name)
    {
        var guid = ParseGuid(Run("/duplicatescheme", Balanced));
        Run("/changename", guid, name, "Managed by OpenSynapse");
        return guid;
    }

    private void Configure(string guid, OperatingMode mode)
    {
        foreach (var setting in Settings)
        {
            var ac = mode == OperatingMode.Performance ? setting.PerfAc : setting.QuietAc;
            var dc = mode == OperatingMode.Performance ? setting.PerfDc : setting.QuietDc;
            try
            {
                Run("/setacvalueindex", guid, setting.Subgroup, setting.Setting, ac.ToString());
                Run("/setdcvalueindex", guid, setting.Subgroup, setting.Setting, dc.ToString());
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
