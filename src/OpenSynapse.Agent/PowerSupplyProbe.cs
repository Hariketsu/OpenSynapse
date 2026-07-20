using System.Globalization;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed record SystemPowerSnapshot(PowerSource Source, int? BatteryPercent);

internal sealed class PowerSupplyProbe
{
    private static readonly TimeSpan DefaultCacheDuration = TimeSpan.FromMinutes(5);
    private readonly Func<SystemPowerSnapshot> readSystemPower;
    private readonly Func<double?> readAdapterLimit;
    private readonly Func<DateTimeOffset> getCurrentTime;
    private readonly TimeSpan cacheDuration;
    private bool hasCachedAdapterLimit;
    private double? cachedAdapterLimit;
    private DateTimeOffset cachedAt;

    public PowerSupplyProbe()
        : this(ReadWindowsPower, ReadNvidiaAdapterLimit, () => DateTimeOffset.UtcNow, DefaultCacheDuration)
    {
    }

    internal PowerSupplyProbe(
        Func<SystemPowerSnapshot> readSystemPower,
        Func<double?> readAdapterLimit,
        Func<DateTimeOffset> getCurrentTime,
        TimeSpan cacheDuration)
    {
        this.readSystemPower = readSystemPower;
        this.readAdapterLimit = readAdapterLimit;
        this.getCurrentTime = getCurrentTime;
        this.cacheDuration = cacheDuration;
    }

    public PowerSnapshot GetSnapshot()
    {
        var systemPower = readSystemPower();
        if (systemPower.Source != PowerSource.Ac)
        {
            hasCachedAdapterLimit = false;
            cachedAdapterLimit = null;
            return new PowerSnapshot(
                systemPower.Source,
                SupplyClassifier.Resolve(systemPower.Source, null),
                systemPower.BatteryPercent);
        }

        var now = getCurrentTime();
        if (!hasCachedAdapterLimit || now - cachedAt >= cacheDuration)
        {
            try { cachedAdapterLimit = readAdapterLimit(); }
            catch { cachedAdapterLimit = null; }
            cachedAt = now;
            hasCachedAdapterLimit = true;
        }

        return new PowerSnapshot(
            systemPower.Source,
            SupplyClassifier.Resolve(systemPower.Source, cachedAdapterLimit),
            systemPower.BatteryPercent,
            cachedAdapterLimit);
    }

    internal static double? ParseAdapterLimit(string output)
    {
        var firstLine = output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault();
        return double.TryParse(firstLine?.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var watts)
            && double.IsFinite(watts)
            ? watts
            : null;
    }

    private static SystemPowerSnapshot ReadWindowsPower()
    {
        var status = System.Windows.Forms.SystemInformation.PowerStatus;
        var source = status.PowerLineStatus switch
        {
            System.Windows.Forms.PowerLineStatus.Online => PowerSource.Ac,
            System.Windows.Forms.PowerLineStatus.Offline => PowerSource.Battery,
            _ => PowerSource.Unknown
        };
        var fraction = status.BatteryLifePercent;
        var percent = float.IsFinite(fraction) && fraction is >= 0 and <= 1
            ? (int?)Math.Round(fraction * 100)
            : null;
        return new SystemPowerSnapshot(source, percent);
    }

    private static double? ReadNvidiaAdapterLimit()
    {
        try
        {
            var output = ProcessRunner.Run(
                "nvidia-smi.exe",
                "--query-gpu=enforced.power.limit",
                "--format=csv,noheader,nounits");
            return ParseAdapterLimit(output);
        }
        catch
        {
            return null;
        }
    }
}
