using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class TelemetryProbe : IDisposable
{
    private readonly object gate = new();
    private readonly GpuTelemetryProbe gpu = new();
    private long previousIdle;
    private long previousKernel;
    private long previousUser;
    private bool hasPreviousCpu;
    private PowerSource trendSource = PowerSource.Unknown;
    private DateTimeOffset? lastTrendSampleAt;
    private double? dischargeEmaWatts;
    private readonly List<BatteryTrendSample> batterySamples = [];

    public TelemetrySnapshot Read(bool includeRunningProcesses = false)
    {
        lock (gate)
        {
            var cpu = ReadCpuPercent();
            var foreground = ReadForeground();
            var battery = ReadBattery();
            var gpuSample = gpu.ReadLatest();
            var running = includeRunningProcesses ? ReadRunningProcesses() : null;
            return foreground with
            {
                CpuPercent = cpu,
                GpuPercent = gpuSample.Available ? gpuSample.TotalUtilizationPercent : -1,
                GpuAvailable = gpuSample.Available,
                DgpuPercent = gpuSample.Available ? gpuSample.DiscreteUtilizationPercent : -1,
                DgpuDedicatedMb = gpuSample.Available
                    ? Math.Round(gpuSample.DiscreteDedicatedBytes / 1024d / 1024d, 1)
                    : -1,
                DgpuConsumers = gpuSample.Consumers,
                GpuError = gpuSample.Error,
                BatteryDischargeWatts = battery.DischargeWatts,
                BatteryChargeWatts = battery.ChargeWatts,
                BatteryRemainingMwh = battery.RemainingMwh,
                BatteryVoltageMv = battery.VoltageMv,
                EstimatedHours = battery.EstimatedHours,
                Confidence = battery.Confidence,
                BatteryDischargeEmaWatts = battery.DischargeEmaWatts,
                BatteryDischargeAverage10mWatts = battery.DischargeAverage10mWatts,
                RunningProcesses = running
            };
        }
    }

    public void Dispose()
    {
        gpu.Dispose();
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
        return total <= 0
            ? -1
            : Math.Clamp((1d - (double)Math.Max(0, idleDelta) / total) * 100d, 0, 100);
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

        var sample = ReadForegroundWindow(window);
        var locked = processName is "LockApp" or "LogonUI";
        return new TelemetrySnapshot(-1, -1, processName, sample.IsFullscreen, locked);
    }

    private static ForegroundWindowSample ReadForegroundWindow(IntPtr window)
    {
        var sample = new ForegroundWindowSample();
        if (IsIconic(window)) sample.IsMinimized = true;
        try
        {
            if (DwmGetWindowAttribute(window, 14, out var cloaked, sizeof(int)) == 0)
                sample.IsCloaked = cloaked != 0;
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }

        if (sample.IsMinimized || sample.IsCloaked
            || !GetWindowRect(window, out var windowRect)) return sample;
        var monitor = MonitorFromWindow(window, MonitorDefaultToNearest);
        if (monitor == IntPtr.Zero) return sample;
        var info = new MonitorInfo { CbSize = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info)) return sample;
        const int tolerance = 3;
        sample.IsFullscreen = windowRect.Left <= info.Monitor.Left + tolerance
            && windowRect.Top <= info.Monitor.Top + tolerance
            && windowRect.Right >= info.Monitor.Right - tolerance
            && windowRect.Bottom >= info.Monitor.Bottom - tolerance;
        return sample;
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

    private BatterySample ReadBattery()
    {
        var source = ReadPowerSource();
        var sample = BatteryClassTelemetry.Read();
        if (sample.Available)
        {
            var discharge = sample.DischargeWatts > 0 ? (double?)sample.DischargeWatts : null;
            UpdateBatteryTrend(source, discharge);
            var estimate = discharge is > 0 && sample.RemainingCapacityMwh > 0
                ? sample.RemainingCapacityMwh / (discharge.Value * 1000d)
                : (double?)null;
            return new BatterySample(
                source,
                discharge,
                sample.ChargeWatts > 0 ? sample.ChargeWatts : null,
                sample.RemainingCapacityMwh > 0 ? sample.RemainingCapacityMwh : null,
                sample.VoltageMv > 0 ? sample.VoltageMv : null,
                estimate,
                "Windows Battery Class API",
                dischargeEmaWatts,
                GetAverage10m());
        }

        var fallback = ReadSystemBatteryState(source);
        UpdateBatteryTrend(source, fallback.DischargeWatts);
        return fallback with
        {
            DischargeEmaWatts = dischargeEmaWatts,
            DischargeAverage10mWatts = GetAverage10m()
        };
    }

    private static BatterySample ReadSystemBatteryState(PowerSource source)
    {
        try
        {
            var size = Marshal.SizeOf<SystemBatteryState>();
            var buffer = Marshal.AllocHGlobal(size);
            try
            {
                var status = CallNtPowerInformation(5, IntPtr.Zero, 0, buffer, (uint)size);
                if (status != 0) return BatterySample.Unavailable(source);
                var battery = Marshal.PtrToStructure<SystemBatteryState>(buffer);
                if (battery.BatteryPresent == 0) return BatterySample.Unavailable(source);
                var watts = Math.Abs(battery.Rate) / 1000d;
                var remainingMwh = (double)battery.RemainingCapacity;
                var estimate = battery.Discharging != 0 && watts > 0
                    ? remainingMwh / (watts * 1000d)
                    : (double?)null;
                return new BatterySample(
                    source,
                    battery.Discharging != 0 && watts > 0 ? watts : null,
                    battery.Charging != 0 && watts > 0 ? watts : null,
                    remainingMwh,
                    null,
                    estimate,
                    "Windows SystemBatteryState",
                    null,
                    null);
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        catch { return BatterySample.Unavailable(source); }
    }

    private void UpdateBatteryTrend(PowerSource source, double? dischargeWatts)
    {
        var now = DateTimeOffset.UtcNow;
        if (source != trendSource)
        {
            trendSource = source;
            batterySamples.Clear();
            dischargeEmaWatts = null;
            lastTrendSampleAt = null;
        }

        if (source != PowerSource.Battery || dischargeWatts is not > 0 || !double.IsFinite(dischargeWatts.Value))
            return;

        var sample = new BatteryTrendSample(now, dischargeWatts.Value);
        batterySamples.Add(sample);
        var cutoff = now - TimeSpan.FromMinutes(10);
        batterySamples.RemoveAll(item => item.Timestamp < cutoff);
        if (dischargeEmaWatts is null || lastTrendSampleAt is null)
            dischargeEmaWatts = sample.Watts;
        else
        {
            var elapsed = Math.Clamp((now - lastTrendSampleAt.Value).TotalSeconds, 0.1, 300);
            var alpha = 1 - Math.Exp(-elapsed / 120d);
            dischargeEmaWatts += alpha * (sample.Watts - dischargeEmaWatts.Value);
        }
        lastTrendSampleAt = now;
    }

    private double? GetAverage10m() => batterySamples.Count == 0
        ? null
        : batterySamples.Average(item => item.Watts);

    private static PowerSource ReadPowerSource()
    {
        var status = System.Windows.Forms.SystemInformation.PowerStatus;
        return status.PowerLineStatus switch
        {
            System.Windows.Forms.PowerLineStatus.Online => PowerSource.Ac,
            System.Windows.Forms.PowerLineStatus.Offline => PowerSource.Battery,
            _ => PowerSource.Unknown
        };
    }

    private static long ToInt64(FileTime value) =>
        ((long)value.High << 32) | value.Low;

    private const uint MonitorDefaultToNearest = 2;

    private readonly record struct BatteryTrendSample(DateTimeOffset Timestamp, double Watts);

    private readonly record struct BatterySample(
        PowerSource Source,
        double? DischargeWatts,
        double? ChargeWatts,
        double? RemainingMwh,
        double? VoltageMv,
        double? EstimatedHours,
        string Confidence,
        double? DischargeEmaWatts,
        double? DischargeAverage10mWatts)
    {
        public static BatterySample Unavailable(PowerSource source) =>
            new(source, null, null, null, null, null, "Unavailable", null, null);
    }

    private sealed class ForegroundWindowSample
    {
        public bool IsFullscreen { get; set; }
        public bool IsMinimized { get; set; }
        public bool IsCloaked { get; set; }
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

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr window);

    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out int value, int valueSize);
}

internal static class BatteryClassTelemetry
{
    private static readonly Guid BatteryInterfaceGuid = new("72631e54-78A4-11d0-bcf7-00aa00b7b32a");
    private const uint DigcfPresent = 0x00000002;
    private const uint DigcfDeviceInterface = 0x00000010;
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const uint IoctlBatteryQueryTag = 0x00294040;
    private const uint IoctlBatteryQueryStatus = 0x0029404c;
    private const int ErrorNoMoreItems = 259;

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceInterfaceData
    {
        public int Size;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BatteryWaitStatus
    {
        public uint BatteryTag;
        public uint Timeout;
        public uint PowerState;
        public uint LowCapacity;
        public uint HighCapacity;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BatteryStatus
    {
        public uint PowerState;
        public uint Capacity;
        public uint Voltage;
        public int Rate;
    }

    internal sealed record BatterySample(
        bool Available,
        double DischargeWatts,
        double ChargeWatts,
        uint RemainingCapacityMwh,
        uint VoltageMv,
        string Error)
    {
        public static BatterySample Unavailable(string error = "Battery Class API unavailable.") =>
            new(false, 0, 0, 0, 0, error);
    }

    internal static BatterySample Read()
    {
        var result = BatterySample.Unavailable(string.Empty);
        var batteryGuid = BatteryInterfaceGuid;
        var set = SetupDiGetClassDevs(
            ref batteryGuid,
            IntPtr.Zero,
            IntPtr.Zero,
            DigcfPresent | DigcfDeviceInterface);
        if (set == new IntPtr(-1)) return result with { Error = $"SetupDiGetClassDevs failed: {Marshal.GetLastWin32Error()}" };

        try
        {
            long signedRateMilliwatts = 0;
            ulong capacity = 0;
            ulong voltage = 0;
            uint index = 0;
            while (true)
            {
                var interfaceData = new DeviceInterfaceData
                {
                    Size = Marshal.SizeOf<DeviceInterfaceData>()
                };
                if (!SetupDiEnumDeviceInterfaces(
                        set,
                        IntPtr.Zero,
                        ref batteryGuid,
                        index++,
                        ref interfaceData))
                {
                    var error = Marshal.GetLastWin32Error();
                    if (error != ErrorNoMoreItems && string.IsNullOrEmpty(result.Error))
                        result = result with { Error = $"SetupDiEnumDeviceInterfaces failed: {error}" };
                    break;
                }

                var path = GetDevicePath(set, ref interfaceData);
                if (string.IsNullOrWhiteSpace(path)) continue;
                using var handle = CreateFile(
                    path,
                    GenericRead | GenericWrite,
                    FileShareRead | FileShareWrite,
                    IntPtr.Zero,
                    OpenExisting,
                    0,
                    IntPtr.Zero);
                if (handle.IsInvalid) continue;

                uint wait = 0;
                if (!DeviceIoControl(handle, IoctlBatteryQueryTag, ref wait, sizeof(uint), out var tag, sizeof(uint), out _, IntPtr.Zero)
                    || tag == 0) continue;
                var query = new BatteryWaitStatus { BatteryTag = tag };
                if (!DeviceIoControl(
                        handle,
                        IoctlBatteryQueryStatus,
                        ref query,
                        (uint)Marshal.SizeOf<BatteryWaitStatus>(),
                        out BatteryStatus status,
                        (uint)Marshal.SizeOf<BatteryStatus>(),
                        out _,
                        IntPtr.Zero)) continue;

                result = result with { Available = true };
                if (status.Rate != int.MinValue) signedRateMilliwatts += status.Rate;
                if (status.Capacity != uint.MaxValue) capacity += status.Capacity;
                if (status.Voltage != uint.MaxValue) voltage += status.Voltage;
            }

            if (!result.Available) return result with { Error = string.IsNullOrWhiteSpace(result.Error) ? "No battery interface responded." : result.Error };
            var signedWatts = signedRateMilliwatts / 1000d;
            return result with
            {
                DischargeWatts = Math.Round(Math.Max(0, -signedWatts), 2),
                ChargeWatts = Math.Round(Math.Max(0, signedWatts), 2),
                RemainingCapacityMwh = capacity > uint.MaxValue ? uint.MaxValue : (uint)capacity,
                VoltageMv = voltage > uint.MaxValue ? uint.MaxValue : (uint)voltage
            };
        }
        catch (Exception ex)
        {
            return result with { Error = ex.Message };
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
    }

    private static string GetDevicePath(IntPtr set, ref DeviceInterfaceData interfaceData)
    {
        SetupDiGetDeviceInterfaceDetail(set, ref interfaceData, IntPtr.Zero, 0, out var required, IntPtr.Zero);
        if (required == 0) return string.Empty;
        var buffer = Marshal.AllocHGlobal((int)required);
        try
        {
            Marshal.WriteInt32(buffer, IntPtr.Size == 8 ? 8 : 4 + Marshal.SystemDefaultCharSize);
            if (!SetupDiGetDeviceInterfaceDetail(set, ref interfaceData, buffer, required, out _, IntPtr.Zero))
                return string.Empty;
            return Marshal.PtrToStringUni(IntPtr.Add(buffer, 4)) ?? string.Empty;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(
        ref Guid classGuid,
        IntPtr enumerator,
        IntPtr parentWindow,
        uint flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiEnumDeviceInterfaces(
        IntPtr deviceInfoSet,
        IntPtr deviceInfoData,
        ref Guid interfaceClassGuid,
        uint memberIndex,
        ref DeviceInterfaceData interfaceData);

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(
        IntPtr deviceInfoSet,
        ref DeviceInterfaceData interfaceData,
        IntPtr detailData,
        uint detailDataSize,
        out uint requiredSize,
        IntPtr deviceInfoData);

    [DllImport("setupapi.dll")]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(
        SafeFileHandle device,
        uint controlCode,
        ref uint inputBuffer,
        uint inputSize,
        out uint outputBuffer,
        uint outputSize,
        out uint bytesReturned,
        IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(
        SafeFileHandle device,
        uint controlCode,
        ref BatteryWaitStatus inputBuffer,
        uint inputSize,
        out BatteryStatus outputBuffer,
        uint outputSize,
        out uint bytesReturned,
        IntPtr overlapped);
}
