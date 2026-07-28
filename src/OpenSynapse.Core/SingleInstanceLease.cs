namespace OpenSynapse.Core;

public sealed class SingleInstanceLease : IDisposable
{
    private Semaphore? semaphore;

    private SingleInstanceLease(Semaphore semaphore)
    {
        this.semaphore = semaphore;
    }

    public static SingleInstanceLease? TryAcquire(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) throw new ArgumentException("A name is required.", nameof(name));
        var semaphore = new Semaphore(1, 1, name);
        if (semaphore.WaitOne(0)) return new SingleInstanceLease(semaphore);
        semaphore.Dispose();
        return null;
    }

    public void Dispose()
    {
        var held = Interlocked.Exchange(ref semaphore, null);
        if (held is null) return;
        held.Release();
        held.Dispose();
    }
}
