using System.IO.Compression;
using System.Text.Json;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal static class DiagnosticExporter
{
    public static string Export(
        OpenSynapseConfig config,
        OpenSynapseState state,
        PowerSupplyProbe powerSupply,
        string logPath,
        TelemetrySnapshot? telemetry = null,
        string? telemetryHistoryPath = null)
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenSynapse",
            "diagnostics");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, $"OpenSynapse-diagnostics-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss}.zip");
        using var archive = ZipFile.Open(path, ZipArchiveMode.Create);
        AddText(archive, "config.json", JsonSerializer.Serialize(config, AgentJson.Options));
        AddText(archive, "state.json", JsonSerializer.Serialize(state, AgentJson.Options));
        AddText(archive, "power.json", JsonSerializer.Serialize(powerSupply.GetSnapshot(), AgentJson.Options));
        if (telemetry is not null)
            AddText(archive, "telemetry.json", JsonSerializer.Serialize(telemetry, AgentJson.Options));
        AddText(archive, "environment.txt", $"OS={Environment.OSVersion}{Environment.NewLine}"
            + $"Runtime={Environment.Version}{Environment.NewLine}"
            + $"Machine={Environment.MachineName}{Environment.NewLine}"
            + $"Utc={DateTimeOffset.UtcNow:o}{Environment.NewLine}");
        AddText(archive, "powercfg.txt", ReadPowerCfg());
        if (File.Exists(logPath)) archive.CreateEntryFromFile(logPath, "OpenSynapse.log");
        if (!string.IsNullOrWhiteSpace(telemetryHistoryPath) && File.Exists(telemetryHistoryPath))
            archive.CreateEntryFromFile(telemetryHistoryPath, "telemetry.jsonl");
        if (!string.IsNullOrWhiteSpace(telemetryHistoryPath) && File.Exists(telemetryHistoryPath + ".old"))
            archive.CreateEntryFromFile(telemetryHistoryPath + ".old", "telemetry.jsonl.old");
        var runtimePath = Path.Combine(Path.GetDirectoryName(logPath)!, "runtime.json");
        if (File.Exists(runtimePath)) archive.CreateEntryFromFile(runtimePath, "runtime.json");
        return path;
    }

    private static void AddText(ZipArchive archive, string name, string contents)
    {
        var entry = archive.CreateEntry(name, CompressionLevel.Fastest);
        using var writer = new StreamWriter(entry.Open());
        writer.Write(contents);
    }

    private static string ReadPowerCfg()
    {
        try
        {
            var executable = Path.Combine(Environment.SystemDirectory, "powercfg.exe");
            return ProcessRunner.Run(executable, "/getactivescheme", "/query");
        }
        catch (Exception ex) { return $"powercfg unavailable: {ex.Message}"; }
    }
}
