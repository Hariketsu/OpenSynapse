using System.Text;

namespace OpenSynapse.Agent;

internal sealed class AgentLog
{
    private readonly object gate = new();
    private readonly string path;
    private readonly long maximumBytes;

    public AgentLog(string? path = null, long maximumBytes = 1024 * 1024)
    {
        if (maximumBytes <= 0) throw new ArgumentOutOfRangeException(nameof(maximumBytes));
        this.path = path ?? System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenSynapse",
            "logs",
            "agent.log");
        this.maximumBytes = maximumBytes;
    }

    public string FilePath => path;

    public bool TryWrite(string category, string message)
    {
        lock (gate)
        {
            try
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
                if (File.Exists(path) && new FileInfo(path).Length >= maximumBytes)
                    File.Move(path, path + ".1", overwrite: true);
                var line = $"{DateTimeOffset.Now:O}\t{Sanitize(category)}\t{Sanitize(message)}{Environment.NewLine}";
                File.AppendAllText(path, line, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
                return true;
            }
            catch
            {
                return false;
            }
        }
    }

    private static string Sanitize(string value) => value
        .Replace('\r', ' ')
        .Replace('\n', ' ')
        .Trim();
}
