using OpenSynapse.Core;

namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class AgentServerSecurityTests
{
    [TestMethod]
    public void PipeRejectsMaintenanceOnlyUninstallCleanup()
    {
        Assert.IsFalse(AgentServer.IsPipeOperationAllowed(AgentOperation.UninstallCleanup));
        Assert.IsTrue(AgentServer.IsPipeOperationAllowed(AgentOperation.Shutdown));
    }
}
