using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class WakeDeviceManager
{
    private readonly Func<IReadOnlyList<string>, string> run;

    public WakeDeviceManager()
    {
        var powerCfg = Path.Combine(Environment.SystemDirectory, "powercfg.exe");
        run = arguments => ProcessRunner.Run(powerCfg, arguments.ToArray());
    }

    internal WakeDeviceManager(Func<IReadOnlyList<string>, string> run)
    {
        this.run = run;
    }

    public IReadOnlyList<string> GetWakeArmedDevices() => ParseDeviceNames(Run("/devicequery", "wake_armed"));

    public void Apply(
        OperatingMode mode,
        OpenSynapseConfig config,
        OpenSynapseState state,
        Action persist)
    {
        if (mode != OperatingMode.Quiet || !config.ManageWakeDevices)
        {
            Restore(state, persist);
            return;
        }

        var configured = new HashSet<string>(config.QuietWakeDeviceNames, StringComparer.OrdinalIgnoreCase);
        foreach (var device in state.DisabledWakeDevices.Where(device => !configured.Contains(device)).ToArray())
            RestoreDevice(device, state, persist);

        foreach (var device in GetWakeArmedDevices().Where(configured.Contains))
        {
            if (!state.DisabledWakeDevices.Contains(device, StringComparer.OrdinalIgnoreCase))
            {
                state.DisabledWakeDevices.Add(device);
                persist();
            }

            Run("/devicedisablewake", device);
            if (GetWakeArmedDevices().Contains(device, StringComparer.OrdinalIgnoreCase))
                throw new InvalidOperationException($"Wake permission for {device} was not disabled.");
        }
    }

    public void Restore(OpenSynapseState state, Action persist)
    {
        foreach (var device in state.DisabledWakeDevices.ToArray())
            RestoreDevice(device, state, persist);
    }

    private string Run(params string[] arguments) => run(arguments);

    private void RestoreDevice(string device, OpenSynapseState state, Action persist)
    {
        Run("/deviceenablewake", device);
        if (!GetWakeArmedDevices().Contains(device, StringComparer.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Wake permission for {device} was not restored.");
        state.DisabledWakeDevices.Remove(device);
        persist();
    }

    private static IReadOnlyList<string> ParseDeviceNames(string output) => output
        .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
        .Select(line => line.Trim())
        .Where(line => line.Length > 0
            && !line.Equals("NONE", StringComparison.OrdinalIgnoreCase)
            && !line.Equals("无", StringComparison.OrdinalIgnoreCase))
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .ToArray();
}
