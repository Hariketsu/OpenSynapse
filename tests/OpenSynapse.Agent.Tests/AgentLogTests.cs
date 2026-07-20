namespace OpenSynapse.Agent.Tests;

[TestClass]
public sealed class AgentLogTests
{
    private string directory = null!;
    private string logPath = null!;

    [TestInitialize]
    public void Initialize()
    {
        directory = Path.Combine(Path.GetTempPath(), "OpenSynapse.Tests", Guid.NewGuid().ToString("N"));
        logPath = Path.Combine(directory, "agent.log");
    }

    [TestCleanup]
    public void Cleanup()
    {
        if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
    }

    [TestMethod]
    public void TryWriteCreatesUtf8LogAndRemovesEmbeddedNewlines()
    {
        var log = new AgentLog(logPath);

        var written = log.TryWrite("test\ncategory", "first\r\nsecond");

        Assert.IsTrue(written);
        var text = File.ReadAllText(logPath);
        StringAssert.Contains(text, "test category\tfirst  second");
        Assert.HasCount(1, File.ReadAllLines(logPath));
    }

    [TestMethod]
    public void TryWriteKeepsOneRotatedBackup()
    {
        var log = new AgentLog(logPath, maximumBytes: 32);
        Assert.IsTrue(log.TryWrite("test", new string('a', 64)));

        Assert.IsTrue(log.TryWrite("test", "second"));

        Assert.IsTrue(File.Exists(logPath + ".1"));
        StringAssert.Contains(File.ReadAllText(logPath + ".1"), new string('a', 64));
        StringAssert.Contains(File.ReadAllText(logPath), "second");
    }
}
