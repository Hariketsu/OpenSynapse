using System.IO.Pipes;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class AgentServer(AgentController controller)
{
    internal const int MaxRequestCharacters = 32768;
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(5);
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
                await using var pipe = NamedPipeServerStreamAcl.Create(
                    "OpenSynapse.Agent",
                    PipeDirection.InOut,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous,
                    0,
                    0,
                    CreatePipeSecurity());
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
            controller.Dispose();
        }
    }

    private void PowerModeChanged(object sender, PowerModeChangedEventArgs args)
    {
        if (args.Mode == PowerModes.StatusChange) _ = Task.Run(() => controller.ApplyCurrentSelection());
    }

    private async Task MonitorSelectionAsync(CancellationToken cancellationToken)
    {
        var interval = TimeSpan.FromSeconds(5);
        while (!cancellationToken.IsCancellationRequested)
        {
            await Task.Delay(interval, cancellationToken);
            var succeeded = controller.ApplyCurrentSelection();
            interval = succeeded
                ? TimeSpan.FromSeconds(5)
                : TimeSpan.FromSeconds(Math.Min(interval.TotalSeconds * 2, 60));
        }
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
            using var requestCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            requestCancellation.CancelAfter(RequestTimeout);
            var line = await ReadBoundedLineAsync(reader, requestCancellation.Token);
            if (string.IsNullOrWhiteSpace(line))
                throw new InvalidDataException(
                    $"Request must be one JSON line no longer than {MaxRequestCharacters} characters.");
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

    private static System.IO.Pipes.PipeSecurity CreatePipeSecurity()
    {
        var userSid = WindowsIdentity.GetCurrent().User?.Value
            ?? throw new InvalidOperationException("The current Windows user SID is unavailable.");
        var security = new System.IO.Pipes.PipeSecurity();
        // The agent runs elevated, but the UI is intentionally unelevated. The
        // pipe is restricted to this user while its integrity label permits the
        // same user's medium-integrity desktop process to connect.
        security.SetSecurityDescriptorSddlForm(
            $"D:(A;;GA;;;{userSid})(A;;GA;;;SY)(A;;GA;;;BA)S:(ML;;NW;;;LW)");
        return security;
    }

    internal static async Task<string?> ReadBoundedLineAsync(
        TextReader reader,
        CancellationToken cancellationToken)
    {
        var builder = new StringBuilder(1024);
        var buffer = new char[1024];
        while (true)
        {
            var read = await reader.ReadAsync(buffer.AsMemory(), cancellationToken);
            if (read == 0)
                return builder.Length == 0 ? null : builder.ToString().TrimEnd('\r');

            for (var index = 0; index < read; index++)
            {
                var character = buffer[index];
                if (character is '\r' or '\n') return builder.ToString();
                if (builder.Length >= MaxRequestCharacters)
                    throw new InvalidDataException(
                        $"Request exceeds {MaxRequestCharacters} characters.");
                builder.Append(character);
            }
        }
    }
}
