using OpenSynapse.Core;

namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class WakeDeviceManagerTests
{
    [TestMethod]
    public void QuietDisablesOnlyExactConfiguredNamesAndRestoresTrackedDevices()
    {
        var armed = new HashSet<string>(["Mouse", "Mouse Extra"], StringComparer.OrdinalIgnoreCase);
        var state = new OpenSynapseState();
        var persistCount = 0;
        var manager = new WakeDeviceManager(arguments => RunFake(arguments, armed, state));
        var config = new OpenSynapseConfig
        {
            ManageWakeDevices = true,
            QuietWakeDeviceNames = ["mouse"]
        };

        manager.Apply(OperatingMode.Quiet, config, state, () => persistCount++);

        Assert.DoesNotContain("Mouse", armed);
        Assert.Contains("Mouse Extra", armed);
        CollectionAssert.AreEqual(new[] { "Mouse" }, state.DisabledWakeDevices);
        Assert.AreEqual(1, persistCount);

        manager.Restore(state, () => persistCount++);

        Assert.Contains("Mouse", armed);
        Assert.IsEmpty(state.DisabledWakeDevices);
        Assert.AreEqual(2, persistCount);
    }

    [TestMethod]
    public void RollbackIntentIsPersistedBeforeWakePermissionChanges()
    {
        var armed = new HashSet<string>(["Mouse"], StringComparer.OrdinalIgnoreCase);
        var state = new OpenSynapseState();
        var manager = new WakeDeviceManager(arguments =>
        {
            if (arguments[0] == "/devicedisablewake")
                Assert.Contains("Mouse", state.DisabledWakeDevices);
            return RunFake(arguments, armed, state);
        });
        var config = new OpenSynapseConfig
        {
            ManageWakeDevices = true,
            QuietWakeDeviceNames = ["Mouse"]
        };

        manager.Apply(OperatingMode.Quiet, config, state, () => { });
    }

    [TestMethod]
    public void FailedRestoreRetainsRollbackRecord()
    {
        var state = new OpenSynapseState { DisabledWakeDevices = ["Mouse"] };
        var manager = new WakeDeviceManager(arguments => arguments[0] switch
        {
            "/deviceenablewake" => string.Empty,
            "/devicequery" => string.Empty,
            _ => throw new AssertFailedException($"Unexpected powercfg call: {string.Join(' ', arguments)}")
        });

        Assert.ThrowsExactly<InvalidOperationException>(() => manager.Restore(state, () => { }));
        Assert.Contains("Mouse", state.DisabledWakeDevices);
    }

    [TestMethod]
    public void QuietRestoresTrackedDeviceRemovedFromTheAllowlist()
    {
        var armed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var state = new OpenSynapseState { DisabledWakeDevices = ["Mouse"] };
        var manager = new WakeDeviceManager(arguments => RunFake(arguments, armed, state));
        var config = new OpenSynapseConfig
        {
            ManageWakeDevices = true,
            QuietWakeDeviceNames = ["Keyboard"]
        };

        manager.Apply(OperatingMode.Quiet, config, state, () => { });

        Assert.Contains("Mouse", armed);
        Assert.IsEmpty(state.DisabledWakeDevices);
    }

    private static string RunFake(
        IReadOnlyList<string> arguments,
        HashSet<string> armed,
        OpenSynapseState state)
    {
        return arguments[0] switch
        {
            "/devicequery" => string.Join(Environment.NewLine, armed),
            "/devicedisablewake" => Change(arguments[1], armed, enabled: false),
            "/deviceenablewake" => Change(arguments[1], armed, enabled: true),
            _ => throw new AssertFailedException(
                $"Unexpected powercfg call for {state.SchemaVersion}: {string.Join(' ', arguments)}")
        };
    }

    private static string Change(string device, HashSet<string> armed, bool enabled)
    {
        if (enabled) armed.Add(device);
        else armed.Remove(device);
        return string.Empty;
    }
}
