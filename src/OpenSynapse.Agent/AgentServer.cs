using System.IO.Pipes;
using System.Text.Json;
using Microsoft.Win32;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class AgentServer(AgentController controller)
{
    private readonly object displayEventGate = new();
    private CancellationTokenSource? displayDebounceCancellation;
    private Task displayReapply = Task.CompletedTask;

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        SystemEvents.PowerModeChanged += PowerModeChanged;
        SystemEvents.DisplaySettingsChanged += DisplaySettingsChanged;
        controller.ApplyCurrentSelection(force: true);
        using var monitorCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var monitor = MonitorSelectionAsync(monitorCancellation.Token);
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                await using var pipe = new NamedPipeServerStream(
                    "OpenSynapse.Agent",
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(cancellationToken);
                if (await HandleConnectionAsync(pipe, cancellationToken)) break;
            }
        }
        finally
        {
            monitorCancellation.Cancel();
            try { await monitor; } catch (OperationCanceledException) { }
            SystemEvents.DisplaySettingsChanged -= DisplaySettingsChanged;
            await CancelDisplayReapplyAsync();
            SystemEvents.PowerModeChanged -= PowerModeChanged;
        }
    }

    private void PowerModeChanged(object sender, PowerModeChangedEventArgs args)
    {
        if (args.Mode == PowerModes.StatusChange) _ = Task.Run(() => controller.ApplyCurrentSelection());
    }

    private async Task MonitorSelectionAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));
        while (await timer.WaitForNextTickAsync(cancellationToken))
            controller.ApplyCurrentSelection();
    }

    private void DisplaySettingsChanged(object? sender, EventArgs args)
    {
        lock (displayEventGate)
        {
            displayDebounceCancellation?.Cancel();
            var cancellation = new CancellationTokenSource();
            displayDebounceCancellation = cancellation;
            displayReapply = ReapplyDisplayAfterDelayAsync(cancellation);
        }
    }

    private async Task ReapplyDisplayAfterDelayAsync(CancellationTokenSource cancellation)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(1), cancellation.Token);
            controller.ReapplyDisplayPolicy();
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        finally
        {
            lock (displayEventGate)
            {
                if (ReferenceEquals(displayDebounceCancellation, cancellation))
                    displayDebounceCancellation = null;
            }
            cancellation.Dispose();
        }
    }

    private async Task CancelDisplayReapplyAsync()
    {
        Task pending;
        lock (displayEventGate)
        {
            displayDebounceCancellation?.Cancel();
            pending = displayReapply;
        }
        await pending;
    }

    private async Task<bool> HandleConnectionAsync(Stream stream, CancellationToken cancellationToken)
    {
        using var reader = new StreamReader(stream, leaveOpen: true);
        await using var writer = new StreamWriter(stream, leaveOpen: true) { AutoFlush = true };
        AgentResponse response;
        AgentRequest? request = null;
        try
        {
            var line = await reader.ReadLineAsync(cancellationToken);
            if (string.IsNullOrWhiteSpace(line) || line.Length > 4096)
                throw new InvalidDataException("Request must be one JSON line no longer than 4096 characters.");
            request = JsonSerializer.Deserialize<AgentRequest>(line, AgentJson.Options)
                ?? throw new InvalidDataException("Request is empty.");
            if (!IsPipeOperationAllowed(request.Operation))
                throw new InvalidDataException("Uninstall cleanup is only available to the elevated maintenance CLI.");
            response = await controller.HandleAsync(request);
        }
        catch (Exception ex)
        {
            response = new AgentResponse(false, ex.Message);
        }
        await writer.WriteLineAsync(JsonSerializer.Serialize(response, AgentJson.Options));
        return response.Success && request?.Operation == AgentOperation.Shutdown;
    }

    internal static bool IsPipeOperationAllowed(AgentOperation operation) =>
        operation != AgentOperation.UninstallCleanup;
}
