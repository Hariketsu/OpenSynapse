using System.IO;
using System.IO.Pipes;
using System.Text.Json;
using System.Text.Json.Serialization;
using OpenSynapse.Core;

namespace OpenSynapse.App;

internal sealed class AgentClient
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(allowIntegerValues: false) }
    };

    public async Task<AgentResponse> SendAsync(AgentRequest request, CancellationToken cancellationToken = default)
    {
        await using var pipe = new NamedPipeClientStream(
            ".",
            "OpenSynapse.Agent",
            PipeDirection.InOut,
            // The server applies an explicit same-user ACL and low-integrity
            // label so an unelevated UI can talk to the elevated Agent.
            PipeOptions.Asynchronous);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(3));
        await pipe.ConnectAsync(timeout.Token);
        await using var writer = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };
        using var reader = new StreamReader(pipe, leaveOpen: true);
        await writer.WriteLineAsync(JsonSerializer.Serialize(request, JsonOptions));
        var line = await reader.ReadLineAsync(timeout.Token)
            ?? throw new IOException("OpenSynapse.Agent closed the pipe without a response.");
        return JsonSerializer.Deserialize<AgentResponse>(line, JsonOptions)
            ?? throw new InvalidDataException("OpenSynapse.Agent returned invalid JSON.");
    }
}
