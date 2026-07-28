using OpenSynapse.Core;

namespace OpenSynapse.Core.Tests;

[TestClass]
public sealed class SingleInstanceLeaseTests
{
    [TestMethod]
    public void LeaseBlocksASecondOwnerAndCanBeReacquiredAfterDispose()
    {
        var name = $"Local\\OpenSynapse.Tests.{Guid.NewGuid():N}";

        using var first = SingleInstanceLease.TryAcquire(name);
        using var blocked = SingleInstanceLease.TryAcquire(name);

        Assert.IsNotNull(first);
        Assert.IsNull(blocked);

        first.Dispose();
        using var reacquired = SingleInstanceLease.TryAcquire(name);
        Assert.IsNotNull(reacquired);
    }
}
