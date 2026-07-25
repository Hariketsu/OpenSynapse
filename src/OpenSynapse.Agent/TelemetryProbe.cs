using System.Diagnostics;
using System.Runtime.InteropServices;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class TelemetryProbe
{
    private readonly object gate = new();
    private long previousIdle;
    private long previousKernel;
    private long previousUser;
    private bool hasPreviousCpu;

    public TelemetrySnapshot Read(bool includeRunningProcesses = false)
    {
        lock (gate)
        {
            var cpu = ReadCpuPercent();
            var foreground = ReadForeground();
            var battery = ReadBattery();
            var running = includeRunningProcesses
                ? ReadRunningProcesses()
                : null;
            return foreground with
            {
                CpuPercent = cpu,
                BatteryDischargeWatts = battery.DischargeWatts,
                BatteryChargeWatts = battery.ChargeWatts,
                BatteryRemainingMwh = battery.RemainingMwh,
                EstimatedHours = battery.EstimatedHours,
                Confidence = battery.Confidence,
                RunningProcesses = running
            };
        }
    }

    private double ReadCpuPercent()
    {
        if (!GetSystemTimes(out var idle, out var kernel, out var user)) return -1;
        var idleTicks = ToInt64(idle);
        var kernelTicks = ToInt64(kernel);
        var userTicks = ToInt64(user);
        if (!hasPreviousCpu)
        {
            previousIdle = idleTicks;
            previousKernel = kernelTicks;
            previousUser = userTicks;
            hasPreviousCpu = true;
            return -1;
        }

        var idleDelta = idleTicks - previousIdle;
        var kernelDelta = kernelTicks - previousKernel;
        var userDelta = userTicks - previousUser;
        previousIdle = idleTicks;
        previousKernel = kernelTicks;
        previousUser = userTicks;
        var total = kernelDelta + userDelta;
        return total <= 0 ? -1 : Math.Clamp((1d - (double)idleDelta / total) * 100d, 0, 100);
    }

    private static TelemetrySnapshot ReadForeground()
    {
        var window = GetForegroundWindow();
        if (window == IntPtr.Zero)
            return new TelemetrySnapshot(-1, -1, null, false, false);

        GetWindowThreadProcessId(window, out var processId);
        string? processName = null;
        try { processName = Process.GetProcessById((int)processId).ProcessName; }
        catch { }

        var fullscreen = IsFullscreen(window);
        var locked = processName is "LockApp" or "LogonUI";
        return new TelemetrySnapshot(-1, -1, processName, fullscreen, locked);
    }

    private static IReadOnlyList<string> ReadRunningProcesses()
    {
        try
        {
            return Process.GetProcesses()
                .Select(process =>
                {
                    try { return process.ProcessName; }
                    catch { return string.Empty; }
                    finally { process.Dispose(); }
                })
                .Where(name => !string.IsNullOrWhiteSpace(name))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(512)
                .ToArray();
        }
        catch { return []; }
    }

    private static BatterySample ReadBattery()
    {
        try
        {
            var size = Marshal.SizeOf<SystemBatteryState>();
            var buffer = Marshal.AllocHGlobal(size);
            try
            {
                var status = CallNtPowerInformation(5, IntPtr.Zero, 0, buffer, (uint)size);
                if (status != 0) return BatterySample.Unavailable;
                var battery = Marshal.PtrToStructure<SystemBatteryState>(buffer);
                if (battery.BatteryPresent == 0) return BatterySample.Unavailable;
                var watts = battery.Rate / 1000d;
                var remainingMwh = (double)battery.RemainingCapacity;
                var estimatedHours = battery.Discharging != 0 && watts > 0
                    ? remainingMwh / (watts * 1000d)
                    : (double?)null;
                return new BatterySample(
                    battery.Discharging != 0 && watts > 0 ? watts : null,
                    battery.Charging != 0 && watts > 0 ? watts : null,
                    remainingMwh,
                    estimatedHours,
                    "Windows SystemBatteryState");
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        catch { return BatterySample.Unavailable; }
    }

    private static bool IsFullscreen(IntPtr window)
    {
        if (!GetWindowRect(window, out var windowRect)) return false;
        var monitor = MonitorFromWindow(window, MonitorDefaultToNearest);
        if (monitor == IntPtr.Zero) return false;
        var info = new MonitorInfo { CbSize = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info)) return false;
        return Math.Abs(windowRect.Left - info.Monitor.Left) <= 1
            && Math.Abs(windowRect.Top - info.Monitor.Top) <= 1
            && Math.Abs(windowRect.Right - info.Monitor.Right) <= 1
            && Math.Abs(windowRect.Bottom - info.Monitor.Bottom) <= 1;
    }

    private static long ToInt64(FileTime value) =>
        ((long)value.High << 32) | value.Low;

    private const uint MonitorDefaultToNearest = 2;

    private readonly record struct BatterySample(
        double? DischargeWatts,
        double? ChargeWatts,
        double? RemainingMwh,
        double? EstimatedHours,
        string Confidence)
    {
        public static BatterySample Unavailable => new(null, null, null, null, "Unavailable");
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime
    {
        public uint Low;
        public int High;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfo
    {
        public int CbSize;
        public Rect Monitor;
        public Rect Work;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SystemBatteryState
    {
        public byte AcOnLine;
        public byte BatteryPresent;
        public byte Charging;
        public byte Discharging;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)] public byte[] Spare;
        public uint MaxCapacity;
        public uint RemainingCapacity;
        public int Rate;
        public uint EstimatedTime;
        public uint DefaultAlert1;
        public uint DefaultAlert2;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);

    [DllImport("powrprof.dll")]
    private static extern uint CallNtPowerInformation(
        int informationLevel,
        IntPtr inputBuffer,
        uint inputBufferLength,
        IntPtr outputBuffer,
        uint outputBufferLength);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
}
