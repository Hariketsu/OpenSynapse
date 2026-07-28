using System.Text.Json;
using System.Security.Principal;
using OpenSynapse.Agent;
using OpenSynapse.Core;

if (!OperatingSystem.IsWindows())
{
    Console.Error.WriteLine("OpenSynapse.Agent only runs on Windows.");
    return 1;
}

var controller = new AgentController();
if (args.Length == 0 || args[0].Equals("serve", StringComparison.OrdinalIgnoreCase))
{
    var user = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
    using var instance = SingleInstanceLease.TryAcquire($"Local\\OpenSynapse.Agent.{user.Replace('\\', '_')}");
    if (instance is null)
    {
        Console.Error.WriteLine("OpenSynapse.Agent is already running for this user.");
        return 2;
    }
    await new AgentServer(controller).RunAsync(CancellationToken.None);
    return 0;
}

var request = args[0].ToLowerInvariant() switch
{
    "status" => new AgentRequest(AgentOperation.Status),
    "self-test" => new AgentRequest(AgentOperation.SelfTest),
    "devices" => new AgentRequest(AgentOperation.ListDevices),
    "restore" => new AgentRequest(AgentOperation.Restore),
    "uninstall-cleanup" => new AgentRequest(AgentOperation.UninstallCleanup),
    "apply" when args.Length == 2
        && TryParseRequestedMode(args[1], out var mode)
        => new AgentRequest(AgentOperation.Apply, mode),
    "mouse-dpi" when args.Length == 2 && int.TryParse(args[1], out var dpi)
        => new AgentRequest(AgentOperation.SetMouseDpi, DpiX: dpi, DpiY: dpi),
    "mouse-polling" when args.Length == 2 && int.TryParse(args[1], out var polling)
        => new AgentRequest(AgentOperation.SetMousePollingRate, PollingRate: polling),
    _ => throw new ArgumentException(
        "Usage: OpenSynapse.Agent [serve|status|self-test|devices|apply <Hyper|Balance|Quiet>|restore|uninstall-cleanup|mouse-dpi <100..30000>|mouse-polling <125|500|1000>]")
};

var response = await controller.HandleAsync(request);
Console.WriteLine(JsonSerializer.Serialize(response, AgentJson.Options));
return response.Success ? 0 : 1;

static bool TryParseRequestedMode(string value, out OperatingMode mode)
{
    if (value.Equals("Hyper", StringComparison.OrdinalIgnoreCase)
        || value.Equals("Performance", StringComparison.OrdinalIgnoreCase))
    {
        mode = OperatingMode.Performance;
        return true;
    }
    if (value.Equals("Balance", StringComparison.OrdinalIgnoreCase)
        || value.Equals("Balanced", StringComparison.OrdinalIgnoreCase))
    {
        mode = OperatingMode.Balanced;
        return true;
    }
    if (value.Equals("Quiet", StringComparison.OrdinalIgnoreCase))
    {
        mode = OperatingMode.Quiet;
        return true;
    }
    mode = default;
    return false;
}
