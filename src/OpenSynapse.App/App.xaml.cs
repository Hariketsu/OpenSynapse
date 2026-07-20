using System.Security.Principal;
using OpenSynapse.Core;

namespace OpenSynapse.App;

public partial class App : System.Windows.Application
{
    private SingleInstanceLease? instanceLease;
    private EventWaitHandle? activationEvent;
    private CancellationTokenSource? activationCancellation;
    private Task? activationWatcher;

    protected override void OnStartup(System.Windows.StartupEventArgs e)
    {
        base.OnStartup(e);
        var user = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        var suffix = user.Replace('\\', '_');
        activationEvent = new EventWaitHandle(
            false,
            EventResetMode.AutoReset,
            $"Local\\OpenSynapse.App.Activate.{suffix}");
        instanceLease = SingleInstanceLease.TryAcquire($"Local\\OpenSynapse.App.{suffix}");
        if (instanceLease is null)
        {
            activationEvent.Set();
            activationEvent.Dispose();
            activationEvent = null;
            Shutdown();
            return;
        }

        activationCancellation = new CancellationTokenSource();
        activationWatcher = Task.Run(() => WatchForActivation(activationCancellation.Token));
        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }

    protected override void OnExit(System.Windows.ExitEventArgs e)
    {
        activationCancellation?.Cancel();
        activationEvent?.Set();
        try { activationWatcher?.Wait(TimeSpan.FromSeconds(1)); } catch (AggregateException) { }
        activationCancellation?.Dispose();
        activationEvent?.Dispose();
        instanceLease?.Dispose();
        base.OnExit(e);
    }

    private void WatchForActivation(CancellationToken cancellationToken)
    {
        var handles = new[] { activationEvent!, cancellationToken.WaitHandle };
        while (WaitHandle.WaitAny(handles) == 0 && !cancellationToken.IsCancellationRequested)
            Dispatcher.BeginInvoke(() => (MainWindow as MainWindow)?.ActivateFromExternalRequest());
    }
}
