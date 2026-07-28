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

    [TestMethod]
    public async Task BoundedReaderAcceptsTheLimitAndRejectsLongerInput()
    {
        var accepted = new string('a', AgentServer.MaxRequestCharacters);
        var line = await AgentServer.ReadBoundedLineAsync(
            new StringReader(accepted + Environment.NewLine),
            CancellationToken.None);

        Assert.AreEqual(accepted, line);
        await Assert.ThrowsExactlyAsync<InvalidDataException>(() => AgentServer.ReadBoundedLineAsync(
            new StringReader(new string('a', AgentServer.MaxRequestCharacters + 1)),
            CancellationToken.None));
    }
}
