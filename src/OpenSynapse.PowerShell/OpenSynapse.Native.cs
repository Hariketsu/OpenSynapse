using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

namespace OpenSynapseNative
{
    public static class WindowTheme
    {
        private const int DarkModeAttribute = 20;
        private const int LegacyDarkModeAttribute = 19;
        private const int BorderColorAttribute = 34;
        private const int CaptionColorAttribute = 35;
        private const int TextColorAttribute = 36;
        private const int WindowCornerPreferenceAttribute = 33;

        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmSetWindowAttribute(IntPtr windowHandle, int attribute, ref int value, int valueSize);

        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SetWindowTheme(IntPtr windowHandle, string subAppName, string subIdList);

        private static int ColorRef(byte red, byte green, byte blue)
        {
            return red | (green << 8) | (blue << 16);
        }

        private static bool SetDwmValue(IntPtr windowHandle, int attribute, int value)
        {
            try { return DwmSetWindowAttribute(windowHandle, attribute, ref value, sizeof(int)) == 0; }
            catch (DllNotFoundException) { return false; }
            catch (EntryPointNotFoundException) { return false; }
        }

        public static bool ApplyDarkFrame(IntPtr windowHandle)
        {
            if (windowHandle == IntPtr.Zero) return false;
            int enabled = 1;
            bool dark = SetDwmValue(windowHandle, DarkModeAttribute, enabled);
            if (!dark) dark = SetDwmValue(windowHandle, LegacyDarkModeAttribute, enabled);
            bool caption = SetDwmValue(windowHandle, CaptionColorAttribute, ColorRef(15, 15, 15));
            bool border = SetDwmValue(windowHandle, BorderColorAttribute, ColorRef(45, 49, 50));
            bool text = SetDwmValue(windowHandle, TextColorAttribute, ColorRef(242, 242, 242));
            return dark || caption || border || text;
        }

        public static bool ApplyRoundedCorners(IntPtr windowHandle)
        {
            if (windowHandle == IntPtr.Zero) return false;
            // DWMWCP_ROUND gives the custom borderless shell the restrained
            // Windows 11 corner treatment used by current Razer applications.
            return SetDwmValue(windowHandle, WindowCornerPreferenceAttribute, 2);
        }

        public static bool ApplyDarkControl(IntPtr windowHandle)
        {
            if (windowHandle == IntPtr.Zero) return false;
            try { return SetWindowTheme(windowHandle, "DarkMode_Explorer", null) == 0; }
            catch (DllNotFoundException) { return false; }
            catch (EntryPointNotFoundException) { return false; }
        }

        public static bool ApplyDarkCombo(IntPtr windowHandle)
        {
            if (windowHandle == IntPtr.Zero) return false;
            try { return SetWindowTheme(windowHandle, "DarkMode_CFD", null) == 0; }
            catch (DllNotFoundException) { return false; }
            catch (EntryPointNotFoundException) { return false; }
        }
    }

    public static class WindowChrome
    {
        private const int WindowCaptionHit = 0x00A1;
        private const int Caption = 0x0002;

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr windowHandle, int message, IntPtr wParam, IntPtr lParam);

        public static void BeginDrag(IntPtr windowHandle)
        {
            if (windowHandle == IntPtr.Zero) return;
            ReleaseCapture();
            SendMessage(windowHandle, WindowCaptionHit, new IntPtr(Caption), IntPtr.Zero);
        }
    }

    public static class AutomationTelemetry
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME
        {
            public uint LowDateTime;
            public uint HighDateTime;
        }

        private static readonly object SyncRoot = new object();
        private static ulong previousIdle;
        private static ulong previousKernel;
        private static ulong previousUser;
        private static bool hasPreviousSample;

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetSystemTimes(out FILETIME idleTime, out FILETIME kernelTime, out FILETIME userTime);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr windowHandle, out uint processId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr windowHandle, out RECT rectangle);

        [DllImport("user32.dll")]
        private static extern IntPtr MonitorFromWindow(IntPtr windowHandle, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMonitorInfo(IntPtr monitorHandle, ref MONITORINFO monitorInfo);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(IntPtr windowHandle);

        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmGetWindowAttribute(IntPtr windowHandle, int attribute, out int value, int valueSize);

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct MONITORINFO
        {
            public int Size;
            public RECT Monitor;
            public RECT Work;
            public uint Flags;
        }

        public sealed class ForegroundWindowSample
        {
            public int ProcessId { get; set; }
            public bool IsFullscreen { get; set; }
            public bool IsMinimized { get; set; }
            public bool IsCloaked { get; set; }
        }

        private static ulong ToUInt64(FILETIME value)
        {
            return ((ulong)value.HighDateTime << 32) | value.LowDateTime;
        }

        public static double SampleCpuPercent()
        {
            FILETIME idleTime;
            FILETIME kernelTime;
            FILETIME userTime;
            if (!GetSystemTimes(out idleTime, out kernelTime, out userTime)) return -1.0;

            ulong idle = ToUInt64(idleTime);
            ulong kernel = ToUInt64(kernelTime);
            ulong user = ToUInt64(userTime);
            lock (SyncRoot)
            {
                if (!hasPreviousSample)
                {
                    previousIdle = idle;
                    previousKernel = kernel;
                    previousUser = user;
                    hasPreviousSample = true;
                    return -1.0;
                }

                ulong idleDelta = idle - previousIdle;
                ulong kernelDelta = kernel - previousKernel;
                ulong userDelta = user - previousUser;
                previousIdle = idle;
                previousKernel = kernel;
                previousUser = user;
                ulong total = kernelDelta + userDelta;
                if (total == 0 || idleDelta > total) return 0.0;
                return Math.Max(0.0, Math.Min(100.0, ((double)(total - idleDelta) * 100.0) / total));
            }
        }

        public static int GetForegroundProcessId()
        {
            IntPtr windowHandle = GetForegroundWindow();
            if (windowHandle == IntPtr.Zero) return 0;
            uint processId;
            GetWindowThreadProcessId(windowHandle, out processId);
            return processId > Int32.MaxValue ? 0 : (int)processId;
        }

        public static ForegroundWindowSample GetForegroundWindowSample()
        {
            ForegroundWindowSample sample = new ForegroundWindowSample();
            IntPtr windowHandle = GetForegroundWindow();
            if (windowHandle == IntPtr.Zero) return sample;

            uint processId;
            GetWindowThreadProcessId(windowHandle, out processId);
            sample.ProcessId = processId > Int32.MaxValue ? 0 : (int)processId;
            sample.IsMinimized = IsIconic(windowHandle);
            int cloaked = 0;
            try
            {
                if (DwmGetWindowAttribute(windowHandle, 14, out cloaked, sizeof(int)) == 0)
                    sample.IsCloaked = cloaked != 0;
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }

            RECT windowRectangle;
            IntPtr monitorHandle = MonitorFromWindow(windowHandle, 2);
            MONITORINFO monitorInfo = new MONITORINFO();
            monitorInfo.Size = Marshal.SizeOf(typeof(MONITORINFO));
            if (!sample.IsMinimized && !sample.IsCloaked &&
                GetWindowRect(windowHandle, out windowRectangle) && monitorHandle != IntPtr.Zero &&
                GetMonitorInfo(monitorHandle, ref monitorInfo))
            {
                const int tolerance = 3;
                sample.IsFullscreen =
                    windowRectangle.Left <= monitorInfo.Monitor.Left + tolerance &&
                    windowRectangle.Top <= monitorInfo.Monitor.Top + tolerance &&
                    windowRectangle.Right >= monitorInfo.Monitor.Right - tolerance &&
                    windowRectangle.Bottom >= monitorInfo.Monitor.Bottom - tolerance;
            }
            return sample;
        }
    }

    public sealed class ProcessCpuSample
    {
        public string ProcessName { get; set; }
        public double CpuPercentOneCore { get; set; }
        public long WorkingSetBytes { get; set; }
        public int ProcessCount { get; set; }
    }

    public static class ProcessCpuSampler
    {
        private sealed class ProcessSnapshot
        {
            public string Name;
            public long CpuTicks;
        }

        private sealed class Aggregate
        {
            public string Name;
            public long CpuTicks;
            public long WorkingSetBytes;
            public int ProcessCount;
        }

        private static readonly object SyncRoot = new object();
        private static Dictionary<int, ProcessSnapshot> previous = new Dictionary<int, ProcessSnapshot>();
        private static long previousTimestamp;

        public static void Reset()
        {
            lock (SyncRoot)
            {
                previous = new Dictionary<int, ProcessSnapshot>();
                previousTimestamp = 0;
            }
        }

        public static ProcessCpuSample[] Sample()
        {
            lock (SyncRoot)
            {
                long now = Stopwatch.GetTimestamp();
                double elapsedSeconds = previousTimestamp == 0
                    ? 0.0
                    : (double)(now - previousTimestamp) / Stopwatch.Frequency;
                Dictionary<int, ProcessSnapshot> current = new Dictionary<int, ProcessSnapshot>();
                Dictionary<string, Aggregate> aggregates = new Dictionary<string, Aggregate>(StringComparer.OrdinalIgnoreCase);

                foreach (Process process in Process.GetProcesses())
                {
                    try
                    {
                        string name = process.ProcessName;
                        long cpuTicks = process.TotalProcessorTime.Ticks;
                        long workingSet = process.WorkingSet64;
                        current[process.Id] = new ProcessSnapshot { Name = name, CpuTicks = cpuTicks };

                        Aggregate aggregate;
                        if (!aggregates.TryGetValue(name, out aggregate))
                        {
                            aggregate = new Aggregate { Name = name };
                            aggregates.Add(name, aggregate);
                        }
                        aggregate.ProcessCount++;
                        aggregate.WorkingSetBytes += Math.Max(0, workingSet);

                        ProcessSnapshot old;
                        if (elapsedSeconds > 0.0 && previous.TryGetValue(process.Id, out old) &&
                            String.Equals(old.Name, name, StringComparison.OrdinalIgnoreCase) && cpuTicks >= old.CpuTicks)
                        {
                            aggregate.CpuTicks += cpuTicks - old.CpuTicks;
                        }
                    }
                    catch (InvalidOperationException) { }
                    catch (Win32Exception) { }
                    catch (NotSupportedException) { }
                    finally { process.Dispose(); }
                }

                previous = current;
                previousTimestamp = now;
                if (elapsedSeconds <= 0.0) return new ProcessCpuSample[0];

                List<ProcessCpuSample> result = new List<ProcessCpuSample>();
                foreach (Aggregate aggregate in aggregates.Values)
                {
                    if (aggregate.CpuTicks <= 0) continue;
                    double cpu = aggregate.CpuTicks * 100.0 / TimeSpan.TicksPerSecond / elapsedSeconds;
                    result.Add(new ProcessCpuSample
                    {
                        ProcessName = aggregate.Name,
                        CpuPercentOneCore = Math.Round(Math.Max(0.0, Math.Min(Environment.ProcessorCount * 100.0, cpu)), 1),
                        WorkingSetBytes = aggregate.WorkingSetBytes,
                        ProcessCount = aggregate.ProcessCount
                    });
                }
                result.Sort(delegate(ProcessCpuSample left, ProcessCpuSample right)
                {
                    return right.CpuPercentOneCore.CompareTo(left.CpuPercentOneCore);
                });
                return result.ToArray();
            }
        }
    }

    public static class BatteryTelemetry
    {
        private static readonly Guid BatteryInterfaceGuid = new Guid("72631e54-78A4-11d0-bcf7-00aa00b7b32a");
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
        private struct SP_DEVICE_INTERFACE_DATA
        {
            public int Size;
            public Guid InterfaceClassGuid;
            public int Flags;
            public IntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BATTERY_WAIT_STATUS
        {
            public uint BatteryTag;
            public uint Timeout;
            public uint PowerState;
            public uint LowCapacity;
            public uint HighCapacity;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BATTERY_STATUS
        {
            public uint PowerState;
            public uint Capacity;
            public uint Voltage;
            public int Rate;
        }

        public sealed class BatterySample
        {
            public bool Available { get; set; }
            public int BatteryCount { get; set; }
            public double SignedRateWatts { get; set; }
            public double DischargeWatts { get; set; }
            public double ChargeWatts { get; set; }
            public uint RemainingCapacityMwh { get; set; }
            public uint VoltageMv { get; set; }
            public string Error { get; set; }
        }

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SetupDiGetClassDevs(ref Guid classGuid, IntPtr enumerator, IntPtr parentWindow, uint flags);

        [DllImport("setupapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiEnumDeviceInterfaces(IntPtr deviceInfoSet, IntPtr deviceInfoData,
            ref Guid interfaceClassGuid, uint memberIndex, ref SP_DEVICE_INTERFACE_DATA interfaceData);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr deviceInfoSet,
            ref SP_DEVICE_INTERFACE_DATA interfaceData, IntPtr detailData, uint detailDataSize,
            out uint requiredSize, IntPtr deviceInfoData);

        [DllImport("setupapi.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiDestroyDeviceInfoList(IntPtr deviceInfoSet);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(string fileName, uint desiredAccess, uint shareMode,
            IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeviceIoControl(SafeFileHandle device, uint controlCode,
            ref uint inputBuffer, uint inputSize, out uint outputBuffer, uint outputSize,
            out uint bytesReturned, IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeviceIoControl(SafeFileHandle device, uint controlCode,
            ref BATTERY_WAIT_STATUS inputBuffer, uint inputSize, out BATTERY_STATUS outputBuffer,
            uint outputSize, out uint bytesReturned, IntPtr overlapped);

        private static string GetDevicePath(IntPtr set, ref SP_DEVICE_INTERFACE_DATA interfaceData)
        {
            uint required;
            SetupDiGetDeviceInterfaceDetail(set, ref interfaceData, IntPtr.Zero, 0, out required, IntPtr.Zero);
            if (required == 0) return String.Empty;
            IntPtr buffer = Marshal.AllocHGlobal((int)required);
            try
            {
                Marshal.WriteInt32(buffer, IntPtr.Size == 8 ? 8 : 4 + Marshal.SystemDefaultCharSize);
                if (!SetupDiGetDeviceInterfaceDetail(set, ref interfaceData, buffer, required, out required, IntPtr.Zero))
                    return String.Empty;
                // SP_DEVICE_INTERFACE_DETAIL_DATA_W starts its variable-length UTF-16
                // device path immediately after the DWORD cbSize field on both x86 and
                // x64. The x64 cbSize value is 8 because the native structure itself is
                // aligned, but the first character remains at byte offset 4.
                return Marshal.PtrToStringUni(IntPtr.Add(buffer, 4)) ?? String.Empty;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        public static BatterySample Read()
        {
            BatterySample result = new BatterySample();
            result.Error = String.Empty;
            Guid batteryGuid = BatteryInterfaceGuid;
            IntPtr set = SetupDiGetClassDevs(ref batteryGuid, IntPtr.Zero, IntPtr.Zero, DigcfPresent | DigcfDeviceInterface);
            if (set == new IntPtr(-1))
            {
                result.Error = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                return result;
            }
            try
            {
                long signedRateMilliwatts = 0;
                ulong capacity = 0;
                ulong voltage = 0;
                uint index = 0;
                while (true)
                {
                    SP_DEVICE_INTERFACE_DATA interfaceData = new SP_DEVICE_INTERFACE_DATA();
                    interfaceData.Size = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                    if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref batteryGuid, index++, ref interfaceData))
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error != ErrorNoMoreItems && String.IsNullOrEmpty(result.Error))
                            result.Error = new Win32Exception(error).Message;
                        break;
                    }
                    string path = GetDevicePath(set, ref interfaceData);
                    if (String.IsNullOrEmpty(path)) continue;
                    using (SafeFileHandle handle = CreateFile(path, GenericRead | GenericWrite,
                        FileShareRead | FileShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero))
                    {
                        if (handle.IsInvalid) continue;
                        uint wait = 0;
                        uint tag;
                        uint returned;
                        if (!DeviceIoControl(handle, IoctlBatteryQueryTag, ref wait, sizeof(uint), out tag,
                            sizeof(uint), out returned, IntPtr.Zero) || tag == 0) continue;
                        BATTERY_WAIT_STATUS query = new BATTERY_WAIT_STATUS();
                        query.BatteryTag = tag;
                        BATTERY_STATUS status;
                        if (!DeviceIoControl(handle, IoctlBatteryQueryStatus, ref query,
                            (uint)Marshal.SizeOf(typeof(BATTERY_WAIT_STATUS)), out status,
                            (uint)Marshal.SizeOf(typeof(BATTERY_STATUS)), out returned, IntPtr.Zero)) continue;
                        result.BatteryCount++;
                        if (status.Rate != Int32.MinValue) signedRateMilliwatts += status.Rate;
                        if (status.Capacity != UInt32.MaxValue) capacity += status.Capacity;
                        if (status.Voltage != UInt32.MaxValue) voltage += status.Voltage;
                    }
                }
                result.Available = result.BatteryCount > 0;
                result.SignedRateWatts = Math.Round(signedRateMilliwatts / 1000.0, 2);
                result.DischargeWatts = Math.Round(Math.Max(0.0, -result.SignedRateWatts), 2);
                result.ChargeWatts = Math.Round(Math.Max(0.0, result.SignedRateWatts), 2);
                result.RemainingCapacityMwh = capacity > UInt32.MaxValue ? UInt32.MaxValue : (uint)capacity;
                result.VoltageMv = result.BatteryCount > 0 ? (uint)(voltage / (ulong)result.BatteryCount) : 0;
                return result;
            }
            catch (Exception exception)
            {
                result.Error = exception.Message;
                return result;
            }
            finally { SetupDiDestroyDeviceInfoList(set); }
        }
    }

    public static class GpuTelemetry
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LUID { public uint LowPart; public int HighPart; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DXGI_ADAPTER_DESC1
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
            public uint VendorId;
            public uint DeviceId;
            public uint SubSysId;
            public uint Revision;
            public UIntPtr DedicatedVideoMemory;
            public UIntPtr DedicatedSystemMemory;
            public UIntPtr SharedSystemMemory;
            public LUID AdapterLuid;
            public uint Flags;
        }

        [ComImport, Guid("29038F61-3839-4626-91FD-086879011A05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDXGIAdapter1
        {
            [PreserveSig] int SetPrivateData(ref Guid name, uint dataSize, IntPtr data);
            [PreserveSig] int SetPrivateDataInterface(ref Guid name, IntPtr unknown);
            [PreserveSig] int GetPrivateData(ref Guid name, ref uint dataSize, IntPtr data);
            [PreserveSig] int GetParent(ref Guid interfaceId, out IntPtr parent);
            [PreserveSig] int EnumOutputs(uint output, out IntPtr outputInterface);
            [PreserveSig] int GetDesc(IntPtr description);
            [PreserveSig] int CheckInterfaceSupport(ref Guid interfaceName, out long userModeDriverVersion);
            [PreserveSig] int GetDesc1(out DXGI_ADAPTER_DESC1 description);
        }

        [ComImport, Guid("770AAE78-F26F-4DBA-A829-253C83D1B387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDXGIFactory1
        {
            [PreserveSig] int SetPrivateData(ref Guid name, uint dataSize, IntPtr data);
            [PreserveSig] int SetPrivateDataInterface(ref Guid name, IntPtr unknown);
            [PreserveSig] int GetPrivateData(ref Guid name, ref uint dataSize, IntPtr data);
            [PreserveSig] int GetParent(ref Guid interfaceId, out IntPtr parent);
            [PreserveSig] int EnumAdapters(uint adapter, out IntPtr adapterInterface);
            [PreserveSig] int MakeWindowAssociation(IntPtr windowHandle, uint flags);
            [PreserveSig] int GetWindowAssociation(out IntPtr windowHandle);
            [PreserveSig] int CreateSwapChain(IntPtr device, IntPtr description, out IntPtr swapChain);
            [PreserveSig] int CreateSoftwareAdapter(IntPtr module, out IntPtr adapter);
            [PreserveSig] int EnumAdapters1(uint adapter, out IDXGIAdapter1 adapterInterface);
            [PreserveSig] bool IsCurrent();
        }

        public sealed class GpuConsumer
        {
            public int ProcessId { get; set; }
            public string ProcessName { get; set; }
            public double UtilizationPercent { get; set; }
            public long DedicatedBytes { get; set; }
            public string AdapterName { get; set; }
            public bool Discrete { get; set; }
        }

        public sealed class GpuSample
        {
            public long Sequence { get; set; }
            public long SampledAtUtcTicks { get; set; }
            public bool Available { get; set; }
            public double TotalUtilizationPercent { get; set; }
            public double DiscreteUtilizationPercent { get; set; }
            public long DiscreteDedicatedBytes { get; set; }
            public bool DiscreteActive { get; set; }
            public GpuConsumer[] Consumers { get; set; }
            public string Error { get; set; }
        }

        private sealed class AdapterInfo
        {
            public string Name;
            public bool Discrete;
        }

        private static readonly object SyncRoot = new object();
        private static readonly Dictionary<string, PerformanceCounter> EngineCounters = new Dictionary<string, PerformanceCounter>(StringComparer.OrdinalIgnoreCase);
        private static readonly Dictionary<string, long> MemoryBytes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        private static DateTime lastCounterRefresh = DateTime.MinValue;
        private static DateTime lastMemoryRefresh = DateTime.MinValue;
        private static Dictionary<string, AdapterInfo> adapters;
        private static GpuSample latestSample = new GpuSample { Consumers = new GpuConsumer[0], Error = "GPU telemetry is starting." };
        private static Thread worker;
        private static readonly AutoResetEvent StopEvent = new AutoResetEvent(false);
        private static volatile bool stopRequested;
        private static int sampleIntervalMilliseconds = 10000;
        private static long sampleSequence;
        private static readonly Regex InstancePattern = new Regex(
            @"pid_(?<pid>\d+)_luid_0x(?<high>[0-9a-f]+)_0x(?<low>[0-9a-f]+)_phys_\d+_eng_\d+_engtype_(?<type>.+)$",
            RegexOptions.IgnoreCase | RegexOptions.Compiled);

        [DllImport("dxgi.dll", PreserveSig = true)]
        private static extern int CreateDXGIFactory1(ref Guid interfaceId, [MarshalAs(UnmanagedType.Interface)] out IDXGIFactory1 factory);

        private static string LuidKey(int high, uint low)
        {
            return ((uint)high).ToString("x8") + ":" + low.ToString("x8");
        }

        private static Dictionary<string, AdapterInfo> ReadAdapters()
        {
            Dictionary<string, AdapterInfo> result = new Dictionary<string, AdapterInfo>(StringComparer.OrdinalIgnoreCase);
            Guid id = typeof(IDXGIFactory1).GUID;
            IDXGIFactory1 factory;
            if (CreateDXGIFactory1(ref id, out factory) < 0 || factory == null) return result;
            try
            {
                for (uint index = 0; ; index++)
                {
                    IDXGIAdapter1 adapter;
                    int code = factory.EnumAdapters1(index, out adapter);
                    if (code != 0 || adapter == null) break;
                    try
                    {
                        DXGI_ADAPTER_DESC1 description;
                        if (adapter.GetDesc1(out description) == 0)
                        {
                            ulong dedicated = description.DedicatedVideoMemory.ToUInt64();
                            bool software = (description.Flags & 2) != 0;
                            result[LuidKey(description.AdapterLuid.HighPart, description.AdapterLuid.LowPart)] = new AdapterInfo
                            {
                                Name = description.Description ?? String.Empty,
                                Discrete = !software && dedicated >= 1024UL * 1024UL * 1024UL
                            };
                        }
                    }
                    finally { Marshal.FinalReleaseComObject(adapter); }
                }
            }
            finally { Marshal.FinalReleaseComObject(factory); }
            return result;
        }

        private static void RefreshCounters()
        {
            if ((DateTime.UtcNow - lastCounterRefresh).TotalSeconds < 15 && EngineCounters.Count > 0) return;
            PerformanceCounterCategory category = new PerformanceCounterCategory("GPU Engine");
            HashSet<string> current = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string name in category.GetInstanceNames())
            {
                if (Regex.IsMatch(name, @"engtype_(3D|Compute|Cuda|VideoEncode|VideoDecode)$", RegexOptions.IgnoreCase))
                    current.Add(name);
            }
            List<string> removed = new List<string>();
            foreach (string name in EngineCounters.Keys) if (!current.Contains(name)) removed.Add(name);
            foreach (string name in removed) { EngineCounters[name].Dispose(); EngineCounters.Remove(name); }
            foreach (string name in current)
            {
                if (!EngineCounters.ContainsKey(name))
                {
                    PerformanceCounter counter = new PerformanceCounter("GPU Engine", "Utilization Percentage", name, true);
                    try { counter.NextValue(); EngineCounters[name] = counter; }
                    catch { counter.Dispose(); }
                }
            }
            lastCounterRefresh = DateTime.UtcNow;
        }

        private static GpuSample SampleCore()
        {
            GpuSample result = new GpuSample { Consumers = new GpuConsumer[0], Error = String.Empty };
            lock (SyncRoot)
            {
                try
                {
                    if (adapters == null) adapters = ReadAdapters();
                    RefreshCounters();
                    Dictionary<string, GpuConsumer> consumers = new Dictionary<string, GpuConsumer>(StringComparer.OrdinalIgnoreCase);
                    foreach (KeyValuePair<string, PerformanceCounter> entry in EngineCounters)
                    {
                        Match match = InstancePattern.Match(entry.Key);
                        if (!match.Success) continue;
                        string engineType = match.Groups["type"].Value;
                        if (!Regex.IsMatch(engineType, "^(3D|Compute|Cuda|VideoEncode|VideoDecode|Copy)", RegexOptions.IgnoreCase)) continue;
                        double value;
                        try { value = Math.Max(0.0, entry.Value.NextValue()); }
                        catch { continue; }
                        int processId;
                        uint high;
                        uint low;
                        if (!Int32.TryParse(match.Groups["pid"].Value, out processId) ||
                            !UInt32.TryParse(match.Groups["high"].Value, System.Globalization.NumberStyles.HexNumber, null, out high) ||
                            !UInt32.TryParse(match.Groups["low"].Value, System.Globalization.NumberStyles.HexNumber, null, out low)) continue;
                        string luid = LuidKey(unchecked((int)high), low);
                        AdapterInfo adapter;
                        if (!adapters.TryGetValue(luid, out adapter)) adapter = new AdapterInfo { Name = "Unknown adapter", Discrete = false };
                        string key = processId.ToString() + ":" + luid;
                        GpuConsumer consumer;
                        if (!consumers.TryGetValue(key, out consumer))
                        {
                            string processName = "pid " + processId.ToString();
                            try { using (Process process = Process.GetProcessById(processId)) { processName = process.ProcessName; } } catch { }
                            consumer = new GpuConsumer { ProcessId = processId, ProcessName = processName, AdapterName = adapter.Name, Discrete = adapter.Discrete };
                            consumers[key] = consumer;
                        }
                        consumer.UtilizationPercent += value;
                        result.TotalUtilizationPercent += value;
                        if (adapter.Discrete) result.DiscreteUtilizationPercent += value;
                    }

                    if ((DateTime.UtcNow - lastMemoryRefresh).TotalSeconds >= 30)
                    {
                        try
                        {
                            MemoryBytes.Clear();
                            PerformanceCounterCategory memoryCategory = new PerformanceCounterCategory("GPU Process Memory");
                            foreach (string instance in memoryCategory.GetInstanceNames())
                            {
                                Match match = Regex.Match(instance, @"pid_(?<pid>\d+)_luid_0x(?<high>[0-9a-f]+)_0x(?<low>[0-9a-f]+)_phys_\d+$", RegexOptions.IgnoreCase);
                                if (!match.Success) continue;
                                uint high;
                                uint low;
                                if (!UInt32.TryParse(match.Groups["high"].Value, System.Globalization.NumberStyles.HexNumber, null, out high) ||
                                    !UInt32.TryParse(match.Groups["low"].Value, System.Globalization.NumberStyles.HexNumber, null, out low)) continue;
                                string luid = LuidKey(unchecked((int)high), low);
                                AdapterInfo adapter;
                                if (!adapters.TryGetValue(luid, out adapter) || !adapter.Discrete) continue;
                                long bytes;
                                using (PerformanceCounter counter = new PerformanceCounter("GPU Process Memory", "Dedicated Usage", instance, true))
                                {
                                    try { bytes = Math.Max(0L, counter.RawValue); } catch { continue; }
                                }
                                MemoryBytes[instance] = bytes;
                            }
                            lastMemoryRefresh = DateTime.UtcNow;
                        }
                        catch { }
                    }
                    foreach (KeyValuePair<string, long> memory in MemoryBytes)
                    {
                        Match match = Regex.Match(memory.Key, @"pid_(?<pid>\d+)_luid_0x(?<high>[0-9a-f]+)_0x(?<low>[0-9a-f]+)_phys_\d+$", RegexOptions.IgnoreCase);
                        if (!match.Success) continue;
                        int processId;
                        uint high;
                        uint low;
                        if (!Int32.TryParse(match.Groups["pid"].Value, out processId) ||
                            !UInt32.TryParse(match.Groups["high"].Value, System.Globalization.NumberStyles.HexNumber, null, out high) ||
                            !UInt32.TryParse(match.Groups["low"].Value, System.Globalization.NumberStyles.HexNumber, null, out low)) continue;
                        string luid = LuidKey(unchecked((int)high), low);
                        AdapterInfo adapter;
                        if (!adapters.TryGetValue(luid, out adapter) || !adapter.Discrete) continue;
                        string key = processId.ToString() + ":" + luid;
                        GpuConsumer consumer;
                        if (!consumers.TryGetValue(key, out consumer))
                        {
                            string processName = "pid " + processId.ToString();
                            try { using (Process process = Process.GetProcessById(processId)) { processName = process.ProcessName; } } catch { }
                            consumer = new GpuConsumer { ProcessId = processId, ProcessName = processName, AdapterName = adapter.Name, Discrete = true };
                            consumers[key] = consumer;
                        }
                        consumer.DedicatedBytes = memory.Value;
                        result.DiscreteDedicatedBytes += memory.Value;
                    }

                    List<GpuConsumer> ordered = new List<GpuConsumer>(consumers.Values);
                    ordered.Sort(delegate(GpuConsumer left, GpuConsumer right)
                    {
                        int utilization = right.UtilizationPercent.CompareTo(left.UtilizationPercent);
                        return utilization != 0 ? utilization : right.DedicatedBytes.CompareTo(left.DedicatedBytes);
                    });
                    result.TotalUtilizationPercent = Math.Round(Math.Min(100.0, result.TotalUtilizationPercent), 1);
                    result.DiscreteUtilizationPercent = Math.Round(Math.Min(100.0, result.DiscreteUtilizationPercent), 1);
                    result.DiscreteActive = result.DiscreteUtilizationPercent >= 0.5 || result.DiscreteDedicatedBytes >= 64L * 1024L * 1024L;
                    result.Consumers = ordered.ToArray();
                    result.Available = true;
                }
                catch (Exception exception) { result.Error = exception.Message; }
                result.Sequence = Interlocked.Increment(ref sampleSequence);
                result.SampledAtUtcTicks = DateTime.UtcNow.Ticks;
                return result;
            }
        }

        private static GpuSample CreateErrorSample(Exception exception)
        {
            return new GpuSample
            {
                Sequence = Interlocked.Increment(ref sampleSequence),
                SampledAtUtcTicks = DateTime.UtcNow.Ticks,
                Consumers = new GpuConsumer[0],
                Error = exception.Message
            };
        }

        public static GpuSample Read()
        {
            GpuSample sample = SampleCore();
            latestSample = sample;
            return sample;
        }

        public static GpuSample ReadLatest()
        {
            return latestSample;
        }

        public static void Start(int intervalMilliseconds)
        {
            lock (SyncRoot)
            {
                SetInterval(intervalMilliseconds);
                if (worker != null && worker.IsAlive) return;
                stopRequested = false;
                worker = new Thread(delegate()
                {
                    while (!stopRequested)
                    {
                        try { latestSample = SampleCore(); }
                        catch (Exception exception) { latestSample = CreateErrorSample(exception); }
                        StopEvent.WaitOne(Volatile.Read(ref sampleIntervalMilliseconds));
                    }
                });
                worker.IsBackground = true;
                worker.Name = "OpenSynapse GPU telemetry";
                worker.Start();
            }
        }

        public static void SetInterval(int intervalMilliseconds)
        {
            int normalized = Math.Max(2000, intervalMilliseconds);
            int previous = Interlocked.Exchange(ref sampleIntervalMilliseconds, normalized);
            Thread thread = worker;
            if (previous != normalized && thread != null && thread.IsAlive) StopEvent.Set();
        }

        public static int GetInterval()
        {
            return Volatile.Read(ref sampleIntervalMilliseconds);
        }

        public static void Stop()
        {
            stopRequested = true;
            StopEvent.Set();
            Thread thread = worker;
            if (thread != null && thread.IsAlive) thread.Join(1500);
            worker = null;
        }
    }

    public static class AppIdentity
    {
        public const string DefaultAppId = "OpenSynapse.Desktop";
        private const uint GPS_READWRITE = 0x00000002;
        private const ushort VT_LPWSTR = 31;

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct PROPERTYKEY
        {
            public Guid fmtid;
            public uint pid;

            public PROPERTYKEY(Guid formatId, uint propertyId)
            {
                fmtid = formatId;
                pid = propertyId;
            }
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct PROPVARIANT
        {
            [FieldOffset(0)] public ushort vt;
            [FieldOffset(8)] public IntPtr pointerValue;

            public static PROPVARIANT FromString(string value)
            {
                PROPVARIANT variant = new PROPVARIANT();
                variant.vt = VT_LPWSTR;
                variant.pointerValue = Marshal.StringToCoTaskMemUni(value);
                return variant;
            }
        }

        [ComImport]
        [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore
        {
            [PreserveSig] int GetCount(out uint propertyCount);
            [PreserveSig] int GetAt(uint propertyIndex, out PROPERTYKEY key);
            [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
            [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
            [PreserveSig] int Commit();
        }

        private static readonly PROPERTYKEY AppUserModelIdKey = new PROPERTYKEY(
            new Guid("9F4C2855-9F79-4B39-A8D0-E1D35B9C9091"), 5);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int GetCurrentProcessExplicitAppUserModelID(out IntPtr appId);

        [DllImport("shell32.dll", PreserveSig = true)]
        private static extern int SHGetPropertyStoreForWindow(
            IntPtr windowHandle, ref Guid interfaceId, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore propertyStore);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHGetPropertyStoreFromParsingName(
            string path, IntPtr bindContext, uint flags, ref Guid interfaceId,
            [MarshalAs(UnmanagedType.Interface)] out IPropertyStore propertyStore);

        [DllImport("ole32.dll", PreserveSig = true)]
        private static extern int PropVariantClear(ref PROPVARIANT value);

        private static void ThrowIfFailed(int result, string operation)
        {
            if (result < 0)
                throw new COMException(operation + " failed.", result);
        }

        private static void SetStoreAppId(IPropertyStore store, string appId)
        {
            PROPVARIANT value = PROPVARIANT.FromString(appId);
            try
            {
                PROPERTYKEY key = AppUserModelIdKey;
                ThrowIfFailed(store.SetValue(ref key, ref value), "IPropertyStore.SetValue");
                ThrowIfFailed(store.Commit(), "IPropertyStore.Commit");
            }
            finally
            {
                PropVariantClear(ref value);
                if (store != null && Marshal.IsComObject(store)) Marshal.FinalReleaseComObject(store);
            }
        }

        private static string GetStoreAppId(IPropertyStore store)
        {
            PROPVARIANT value;
            PROPERTYKEY key = AppUserModelIdKey;
            try
            {
                ThrowIfFailed(store.GetValue(ref key, out value), "IPropertyStore.GetValue");
                try
                {
                    if (value.vt != VT_LPWSTR || value.pointerValue == IntPtr.Zero) return String.Empty;
                    return Marshal.PtrToStringUni(value.pointerValue) ?? String.Empty;
                }
                finally { PropVariantClear(ref value); }
            }
            finally
            {
                if (store != null && Marshal.IsComObject(store)) Marshal.FinalReleaseComObject(store);
            }
        }

        public static string SetCurrentProcessAppId(string appId)
        {
            if (String.IsNullOrWhiteSpace(appId)) throw new ArgumentException("AppUserModelID is required.", "appId");
            ThrowIfFailed(SetCurrentProcessExplicitAppUserModelID(appId), "SetCurrentProcessExplicitAppUserModelID");
            return GetCurrentProcessAppId();
        }

        public static string GetCurrentProcessAppId()
        {
            IntPtr value;
            int result = GetCurrentProcessExplicitAppUserModelID(out value);
            if (result < 0 || value == IntPtr.Zero) return String.Empty;
            try { return Marshal.PtrToStringUni(value) ?? String.Empty; }
            finally { Marshal.FreeCoTaskMem(value); }
        }

        public static void SetWindowAppId(IntPtr windowHandle, string appId)
        {
            if (windowHandle == IntPtr.Zero) throw new ArgumentException("A valid window handle is required.", "windowHandle");
            Guid interfaceId = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            ThrowIfFailed(SHGetPropertyStoreForWindow(windowHandle, ref interfaceId, out store), "SHGetPropertyStoreForWindow");
            SetStoreAppId(store, appId);
        }

        public static string GetWindowAppId(IntPtr windowHandle)
        {
            if (windowHandle == IntPtr.Zero) return String.Empty;
            Guid interfaceId = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            ThrowIfFailed(SHGetPropertyStoreForWindow(windowHandle, ref interfaceId, out store), "SHGetPropertyStoreForWindow");
            return GetStoreAppId(store);
        }

        public static void SetShortcutAppId(string shortcutPath, string appId)
        {
            if (String.IsNullOrWhiteSpace(shortcutPath)) throw new ArgumentException("Shortcut path is required.", "shortcutPath");
            Guid interfaceId = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            ThrowIfFailed(SHGetPropertyStoreFromParsingName(shortcutPath, IntPtr.Zero, GPS_READWRITE,
                ref interfaceId, out store), "SHGetPropertyStoreFromParsingName");
            SetStoreAppId(store, appId);
        }

        public static string GetShortcutAppId(string shortcutPath)
        {
            if (String.IsNullOrWhiteSpace(shortcutPath)) return String.Empty;
            Guid interfaceId = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            ThrowIfFailed(SHGetPropertyStoreFromParsingName(shortcutPath, IntPtr.Zero, 0,
                ref interfaceId, out store), "SHGetPropertyStoreFromParsingName");
            return GetStoreAppId(store);
        }
    }

    public static class HighDpi
    {
        private static readonly IntPtr PerMonitorAwareV2 = new IntPtr(-4);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        [DllImport("shcore.dll")]
        private static extern int SetProcessDpiAwareness(int value);

        [DllImport("shcore.dll", EntryPoint = "GetProcessDpiAwareness")]
        private static extern int NativeGetProcessDpiAwareness(IntPtr processHandle, out int value);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetProcessDPIAware();

        public static int GetProcessAwareness(IntPtr processHandle)
        {
            try
            {
                int value;
                return NativeGetProcessDpiAwareness(processHandle, out value) == 0 ? value : -1;
            }
            catch { return -1; }
        }

        public static string EnablePerMonitorV2()
        {
            try
            {
                if (SetProcessDpiAwarenessContext(PerMonitorAwareV2))
                    return "PerMonitorV2";
            }
            catch (EntryPointNotFoundException) { }
            catch (DllNotFoundException) { }

            try
            {
                int result = SetProcessDpiAwareness(2);
                if (result == 0)
                    return "PerMonitorV1";
                if (GetProcessAwareness(IntPtr.Zero) == 2)
                    return "PerMonitor";
            }
            catch (EntryPointNotFoundException) { }
            catch (DllNotFoundException) { }

            try
            {
                if (SetProcessDPIAware())
                    return "SystemAware";
            }
            catch { }
            return "Unaware";
        }
    }

    public static class DisplayChangeSignal
    {
        private static EventHandler displayHandler;
        private static int started;
        private static int version;

        public static int Version
        {
            get { return Interlocked.CompareExchange(ref version, 0, 0); }
        }

        private static void MarkChanged()
        {
            Interlocked.Increment(ref version);
        }

        public static void Start()
        {
            if (Interlocked.Exchange(ref started, 1) != 0)
                return;

            displayHandler = delegate(object sender, EventArgs args) { MarkChanged(); };
            SystemEvents.DisplaySettingsChanged += displayHandler;
        }

        public static void Stop()
        {
            if (Interlocked.Exchange(ref started, 0) == 0)
                return;
            SystemEvents.DisplaySettingsChanged -= displayHandler;
        }
    }

    public static class PowerChangeSignal
    {
        private static PowerModeChangedEventHandler powerHandler;
        private static SessionSwitchEventHandler sessionHandler;
        private static int started;
        private static int version;
        private static int eventCount;
        private static int coalescedEventCount;
        private static long lastAcceptedTimestamp;
        private static int sessionLocked;
        private static int suspended;
        private static int wakeVersion;
        private const int DebounceMilliseconds = 3000;

        public static int Version
        {
            get { return Interlocked.CompareExchange(ref version, 0, 0); }
        }

        public static int EventCount
        {
            get { return Interlocked.CompareExchange(ref eventCount, 0, 0); }
        }

        public static int CoalescedEventCount
        {
            get { return Interlocked.CompareExchange(ref coalescedEventCount, 0, 0); }
        }

        public static bool SessionLocked
        {
            get { return Interlocked.CompareExchange(ref sessionLocked, 0, 0) != 0; }
        }

        public static bool IsSuspended
        {
            get { return Interlocked.CompareExchange(ref suspended, 0, 0) != 0; }
        }

        public static int WakeVersion
        {
            get { return Interlocked.CompareExchange(ref wakeVersion, 0, 0); }
        }

        private static void MarkWake()
        {
            Interlocked.Exchange(ref suspended, 0);
            Interlocked.Increment(ref wakeVersion);
        }

        private static void MarkPowerChanged()
        {
            Interlocked.Increment(ref eventCount);
            long now = Stopwatch.GetTimestamp();
            long previous = Interlocked.Read(ref lastAcceptedTimestamp);
            double elapsedMilliseconds = previous == 0
                ? Double.MaxValue
                : ((double)(now - previous) * 1000.0) / Stopwatch.Frequency;
            if (elapsedMilliseconds < DebounceMilliseconds)
            {
                Interlocked.Increment(ref coalescedEventCount);
                return;
            }
            Interlocked.Exchange(ref lastAcceptedTimestamp, now);
            Interlocked.Increment(ref version);
        }

        public static void Start()
        {
            if (Interlocked.Exchange(ref started, 1) != 0)
                return;

            powerHandler = delegate(object sender, PowerModeChangedEventArgs args)
            {
                if (args.Mode == PowerModes.Suspend)
                    Interlocked.Exchange(ref suspended, 1);
                else if (args.Mode == PowerModes.Resume)
                {
                    MarkWake();
                    MarkPowerChanged();
                }
                else if (args.Mode == PowerModes.StatusChange)
                    MarkPowerChanged();
            };
            sessionHandler = delegate(object sender, SessionSwitchEventArgs args)
            {
                if (args.Reason == SessionSwitchReason.SessionLock)
                    Interlocked.Exchange(ref sessionLocked, 1);
                else if (args.Reason == SessionSwitchReason.SessionUnlock ||
                    args.Reason == SessionSwitchReason.SessionLogon ||
                    args.Reason == SessionSwitchReason.ConsoleConnect ||
                    args.Reason == SessionSwitchReason.RemoteConnect)
                {
                    Interlocked.Exchange(ref sessionLocked, 0);
                    // Modern Standby does not reliably raise PowerModeChanged on all
                    // systems. Unlock/connect is therefore also a display-wake edge.
                    MarkWake();
                }
            };
            SystemEvents.PowerModeChanged += powerHandler;
            SystemEvents.SessionSwitch += sessionHandler;
        }

        public static void Stop()
        {
            if (Interlocked.Exchange(ref started, 0) == 0)
                return;
            SystemEvents.PowerModeChanged -= powerHandler;
            SystemEvents.SessionSwitch -= sessionHandler;
        }
    }

    public static class DisplayWakeManager
    {
        private const uint ES_DISPLAY_REQUIRED = 0x00000002;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint SetThreadExecutionState(uint esFlags);

        public static bool RequestWake()
        {
            // Without ES_CONTINUOUS this is a one-shot display-idle reset. It does
            // not retain a power request or change the configured display timeout.
            return SetThreadExecutionState(ES_DISPLAY_REQUIRED) != 0;
        }
    }

    public sealed class DisplayScaleInfo
    {
        public uint AdapterLowPart { get; internal set; }
        public int AdapterHighPart { get; internal set; }
        public uint SourceId { get; internal set; }
        public uint OutputTechnology { get; internal set; }
        public string GdiDeviceName { get; internal set; }
        public bool IsInternal { get; internal set; }
        public int MinimumPercent { get; internal set; }
        public int CurrentPercent { get; internal set; }
        public int RecommendedPercent { get; internal set; }
        public int MaximumPercent { get; internal set; }

        public string Key
        {
            get { return AdapterHighPart + ":" + AdapterLowPart + ":" + SourceId; }
        }

        public string Role
        {
            get { return IsInternal ? "Internal" : "External"; }
        }
    }

    public static class DisplayScaling
    {
        private const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
        private const uint QDC_VIRTUAL_MODE_AWARE = 0x00000010;
        private const int ERROR_SUCCESS = 0;
        private const int ERROR_INSUFFICIENT_BUFFER = 122;
        private const int DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = -3;
        private const int DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = -4;
        private const int DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1;

        private static readonly int[] DpiValues =
        {
            100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500
        };

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID
        {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_RATIONAL
        {
            public uint Numerator;
            public uint Denominator;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct POINTL
        {
            public int x;
            public int y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECTL
        {
            public int left;
            public int top;
            public int right;
            public int bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_2DREGION
        {
            public uint cx;
            public uint cy;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_SOURCE_INFO
        {
            public LUID adapterId;
            public uint id;
            public uint modeInfoIdx;
            public uint statusFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_TARGET_INFO
        {
            public LUID adapterId;
            public uint id;
            public uint modeInfoIdx;
            public uint outputTechnology;
            public uint rotation;
            public uint scaling;
            public DISPLAYCONFIG_RATIONAL refreshRate;
            public uint scanLineOrdering;
            [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable;
            public uint statusFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_INFO
        {
            public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
            public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
            public uint flags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO
        {
            public ulong pixelRate;
            public DISPLAYCONFIG_RATIONAL hSyncFreq;
            public DISPLAYCONFIG_RATIONAL vSyncFreq;
            public DISPLAYCONFIG_2DREGION activeSize;
            public DISPLAYCONFIG_2DREGION totalSize;
            public uint videoStandard;
            public uint scanLineOrdering;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_TARGET_MODE
        {
            public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_SOURCE_MODE
        {
            public uint width;
            public uint height;
            public uint pixelFormat;
            public POINTL position;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_DESKTOP_IMAGE_INFO
        {
            public POINTL PathSourceSize;
            public RECTL DesktopImageRegion;
            public RECTL DesktopImageClip;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct DISPLAYCONFIG_MODE_INFO_UNION
        {
            [FieldOffset(0)] public DISPLAYCONFIG_TARGET_MODE targetMode;
            [FieldOffset(0)] public DISPLAYCONFIG_SOURCE_MODE sourceMode;
            [FieldOffset(0)] public DISPLAYCONFIG_DESKTOP_IMAGE_INFO desktopImageInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_MODE_INFO
        {
            public uint infoType;
            public uint id;
            public LUID adapterId;
            public DISPLAYCONFIG_MODE_INFO_UNION modeInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_DEVICE_INFO_HEADER
        {
            public int type;
            public uint size;
            public LUID adapterId;
            public uint id;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public int minScaleRel;
            public int curScaleRel;
            public int maxScaleRel;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_SOURCE_DPI_SCALE_SET
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public int scaleRel;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DISPLAYCONFIG_SOURCE_DEVICE_NAME
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
        }

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(
            uint flags,
            out uint numPathArrayElements,
            out uint numModeInfoArrayElements);

        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(
            uint flags,
            ref uint numPathArrayElements,
            [Out] DISPLAYCONFIG_PATH_INFO[] pathArray,
            ref uint numModeInfoArrayElements,
            [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
            IntPtr currentTopologyId);

        [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
        private static extern int DisplayConfigGetDpiInfo(
            ref DISPLAYCONFIG_SOURCE_DPI_SCALE_GET requestPacket);

        [DllImport("user32.dll", EntryPoint = "DisplayConfigSetDeviceInfo")]
        private static extern int DisplayConfigSetDpiInfo(
            ref DISPLAYCONFIG_SOURCE_DPI_SCALE_SET requestPacket);

        [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
        private static extern int DisplayConfigGetSourceName(
            ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

        private static bool IsBuiltIn(uint outputTechnology)
        {
            return outputTechnology == 6u || outputTechnology == 11u ||
                   outputTechnology == 13u || outputTechnology == 0x80000000u;
        }

        private static int ValueAtRelativeIndex(int recommendedIndex, int relativeIndex)
        {
            int index = recommendedIndex + relativeIndex;
            if (index < 0 || index >= DpiValues.Length)
                throw new InvalidOperationException("Windows returned an unknown DPI scale index.");
            return DpiValues[index];
        }

        private static DISPLAYCONFIG_SOURCE_DPI_SCALE_GET GetDpiPacket(
            LUID adapterId, uint sourceId)
        {
            DISPLAYCONFIG_SOURCE_DPI_SCALE_GET packet = new DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
            packet.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE;
            packet.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
            packet.header.adapterId = adapterId;
            packet.header.id = sourceId;

            int result = DisplayConfigGetDpiInfo(ref packet);
            if (result != ERROR_SUCCESS)
                throw new Win32Exception(result, "Cannot read per-monitor DPI scaling.");
            return packet;
        }

        private static string GetSourceName(LUID adapterId, uint sourceId)
        {
            DISPLAYCONFIG_SOURCE_DEVICE_NAME packet = new DISPLAYCONFIG_SOURCE_DEVICE_NAME();
            packet.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            packet.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DEVICE_NAME));
            packet.header.adapterId = adapterId;
            packet.header.id = sourceId;
            packet.viewGdiDeviceName = String.Empty;
            return DisplayConfigGetSourceName(ref packet) == ERROR_SUCCESS
                ? packet.viewGdiDeviceName ?? String.Empty
                : String.Empty;
        }

        public static DisplayScaleInfo[] GetActiveDisplays()
        {
            const uint flags = QDC_ONLY_ACTIVE_PATHS | QDC_VIRTUAL_MODE_AWARE;
            for (int attempt = 0; attempt < 5; attempt++)
            {
                uint pathCount;
                uint modeCount;
                int result = GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount);
                if (result != ERROR_SUCCESS)
                    throw new Win32Exception(result, "Cannot size the active display configuration.");

                DISPLAYCONFIG_PATH_INFO[] paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
                DISPLAYCONFIG_MODE_INFO[] modes = new DISPLAYCONFIG_MODE_INFO[modeCount];
                result = QueryDisplayConfig(
                    flags, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
                if (result == ERROR_INSUFFICIENT_BUFFER)
                    continue;
                if (result != ERROR_SUCCESS)
                    throw new Win32Exception(result, "Cannot query the active display configuration.");

                List<DisplayScaleInfo> displays = new List<DisplayScaleInfo>();
                HashSet<string> seenSources = new HashSet<string>(StringComparer.Ordinal);
                for (int i = 0; i < pathCount; i++)
                {
                    DISPLAYCONFIG_PATH_INFO path = paths[i];
                    string key = path.sourceInfo.adapterId.HighPart + ":" +
                                 path.sourceInfo.adapterId.LowPart + ":" + path.sourceInfo.id;
                    if (!seenSources.Add(key))
                        continue;

                    DISPLAYCONFIG_SOURCE_DPI_SCALE_GET dpi =
                        GetDpiPacket(path.sourceInfo.adapterId, path.sourceInfo.id);
                    int recommendedIndex = -dpi.minScaleRel;
                    if (recommendedIndex < 0 || recommendedIndex >= DpiValues.Length)
                        throw new InvalidOperationException("Windows returned an unknown recommended DPI index.");

                    DisplayScaleInfo info = new DisplayScaleInfo();
                    info.AdapterLowPart = path.sourceInfo.adapterId.LowPart;
                    info.AdapterHighPart = path.sourceInfo.adapterId.HighPart;
                    info.SourceId = path.sourceInfo.id;
                    info.OutputTechnology = path.targetInfo.outputTechnology;
                    info.GdiDeviceName = GetSourceName(path.sourceInfo.adapterId, path.sourceInfo.id);
                    info.IsInternal = IsBuiltIn(path.targetInfo.outputTechnology);
                    info.MinimumPercent = ValueAtRelativeIndex(recommendedIndex, dpi.minScaleRel);
                    info.CurrentPercent = ValueAtRelativeIndex(recommendedIndex, dpi.curScaleRel);
                    info.RecommendedPercent = DpiValues[recommendedIndex];
                    info.MaximumPercent = ValueAtRelativeIndex(recommendedIndex, dpi.maxScaleRel);
                    displays.Add(info);
                }
                return displays.ToArray();
            }
            throw new Win32Exception(ERROR_INSUFFICIENT_BUFFER,
                "Display topology kept changing while it was being queried.");
        }

        public static bool SetScale(DisplayScaleInfo display, int desiredPercent)
        {
            int desiredIndex = Array.IndexOf(DpiValues, desiredPercent);
            if (desiredIndex < 0)
                throw new ArgumentOutOfRangeException("desiredPercent", "Unsupported DPI scale.");

            LUID adapterId = new LUID();
            adapterId.LowPart = display.AdapterLowPart;
            adapterId.HighPart = display.AdapterHighPart;
            DISPLAYCONFIG_SOURCE_DPI_SCALE_GET current = GetDpiPacket(adapterId, display.SourceId);
            int recommendedIndex = -current.minScaleRel;
            int desiredRelative = desiredIndex - recommendedIndex;

            if (desiredRelative < current.minScaleRel || desiredRelative > current.maxScaleRel)
                throw new ArgumentOutOfRangeException(
                    "desiredPercent",
                    desiredPercent + "% is outside this display's supported range.");

            if (current.curScaleRel == desiredRelative)
                return false;

            DISPLAYCONFIG_SOURCE_DPI_SCALE_SET packet = new DISPLAYCONFIG_SOURCE_DPI_SCALE_SET();
            packet.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE;
            packet.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_SET));
            packet.header.adapterId = adapterId;
            packet.header.id = display.SourceId;
            packet.scaleRel = desiredRelative;

            int result = DisplayConfigSetDpiInfo(ref packet);
            if (result != ERROR_SUCCESS)
                throw new Win32Exception(result, "Cannot set per-monitor DPI scaling.");
            return true;
        }
    }

    public sealed class DisplayModeInfo
    {
        public string DeviceName { get; internal set; }
        public string FriendlyName { get; internal set; }
        public string DeviceId { get; internal set; }
        public string DeviceKey { get; internal set; }
        public string MonitorName { get; internal set; }
        public string MonitorDeviceId { get; internal set; }
        public string MonitorDeviceKey { get; internal set; }
        public int Width { get; internal set; }
        public int Height { get; internal set; }
        public int BitsPerPixel { get; internal set; }
        public int Frequency { get; internal set; }
        public int PositionX { get; internal set; }
        public int PositionY { get; internal set; }
        public int Orientation { get; internal set; }
        public bool IsPrimary { get; internal set; }
    }

    public static class DisplayModeManager
    {
        private const int ENUM_CURRENT_SETTINGS = -1;
        private const int DISP_CHANGE_SUCCESSFUL = 0;
        private const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x1;
        private const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x4;
        private const int DM_POSITION = 0x00000020;
        private const int DM_DISPLAYORIENTATION = 0x00000080;
        private const int DM_BITSPERPEL = 0x00040000;
        private const int DM_PELSWIDTH = 0x00080000;
        private const int DM_PELSHEIGHT = 0x00100000;
        private const int DM_DISPLAYFREQUENCY = 0x00400000;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplayDevices(
            string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplaySettingsEx(
            string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode, uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int ChangeDisplaySettingsEx(
            string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW")]
        private static extern int ChangeDisplaySettingsExReset(
            string lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

        private static DEVMODE NewMode()
        {
            DEVMODE mode = new DEVMODE();
            mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            return mode;
        }

        private static List<DISPLAY_DEVICE> GetActiveDevices()
        {
            List<DISPLAY_DEVICE> devices = new List<DISPLAY_DEVICE>();
            for (uint index = 0; ; index++)
            {
                DISPLAY_DEVICE device = new DISPLAY_DEVICE();
                device.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
                if (!EnumDisplayDevices(null, index, ref device, 0))
                    break;
                if ((device.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) != 0)
                    devices.Add(device);
            }
            return devices;
        }

        public static DisplayModeInfo[] GetActiveDisplays()
        {
            List<DisplayModeInfo> result = new List<DisplayModeInfo>();
            foreach (DISPLAY_DEVICE device in GetActiveDevices())
            {
                DEVMODE current = NewMode();
                if (!EnumDisplaySettingsEx(device.DeviceName, ENUM_CURRENT_SETTINGS, ref current, 0))
                    continue;
                DisplayModeInfo info = new DisplayModeInfo();
                info.DeviceName = device.DeviceName;
                info.FriendlyName = device.DeviceString;
                info.DeviceId = device.DeviceID;
                info.DeviceKey = device.DeviceKey;
                DISPLAY_DEVICE monitor = new DISPLAY_DEVICE();
                monitor.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
                if (EnumDisplayDevices(device.DeviceName, 0, ref monitor, 0))
                {
                    info.MonitorName = monitor.DeviceString ?? String.Empty;
                    info.MonitorDeviceId = monitor.DeviceID ?? String.Empty;
                    info.MonitorDeviceKey = monitor.DeviceKey ?? String.Empty;
                }
                else
                {
                    info.MonitorName = String.Empty;
                    info.MonitorDeviceId = String.Empty;
                    info.MonitorDeviceKey = String.Empty;
                }
                info.Width = current.dmPelsWidth;
                info.Height = current.dmPelsHeight;
                info.BitsPerPixel = current.dmBitsPerPel;
                info.Frequency = current.dmDisplayFrequency;
                info.PositionX = current.dmPositionX;
                info.PositionY = current.dmPositionY;
                info.Orientation = current.dmDisplayOrientation;
                info.IsPrimary = (device.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0;
                result.Add(info);
            }
            return result.ToArray();
        }

        private static int ApplyFrequency(DISPLAY_DEVICE device, bool maximum, int targetHz, bool requireExact)
        {
            DEVMODE current = NewMode();
            if (!EnumDisplaySettingsEx(device.DeviceName, ENUM_CURRENT_SETTINGS, ref current, 0))
                return 0;

            List<DEVMODE> candidates = new List<DEVMODE>();
            for (int index = 0; ; index++)
            {
                DEVMODE candidate = NewMode();
                if (!EnumDisplaySettingsEx(device.DeviceName, index, ref candidate, 0))
                    break;
                if (candidate.dmPelsWidth == current.dmPelsWidth &&
                    candidate.dmPelsHeight == current.dmPelsHeight &&
                    candidate.dmBitsPerPel == current.dmBitsPerPel &&
                    candidate.dmDisplayFrequency > 1)
                {
                    candidates.Add(candidate);
                }
            }
            if (candidates.Count == 0)
                return 0;

            DEVMODE selected = candidates[0];
            if (maximum)
            {
                foreach (DEVMODE candidate in candidates)
                    if (candidate.dmDisplayFrequency > selected.dmDisplayFrequency)
                        selected = candidate;
            }
            else if (requireExact)
            {
                bool foundExact = false;
                foreach (DEVMODE candidate in candidates)
                {
                    if (Math.Abs(candidate.dmDisplayFrequency - targetHz) <= 1)
                    {
                        if (!foundExact || Math.Abs(candidate.dmDisplayFrequency - targetHz) < Math.Abs(selected.dmDisplayFrequency - targetHz))
                            selected = candidate;
                        foundExact = true;
                    }
                }
                if (!foundExact)
                    throw new InvalidOperationException(device.DeviceName + " does not expose " + targetHz + " Hz at the current resolution and color depth.");
            }
            else
            {
                bool foundAtOrBelow = false;
                foreach (DEVMODE candidate in candidates)
                {
                    if (candidate.dmDisplayFrequency <= targetHz + 1)
                    {
                        if (!foundAtOrBelow || candidate.dmDisplayFrequency > selected.dmDisplayFrequency)
                            selected = candidate;
                        foundAtOrBelow = true;
                    }
                }
                if (!foundAtOrBelow)
                {
                    foreach (DEVMODE candidate in candidates)
                        if (candidate.dmDisplayFrequency < selected.dmDisplayFrequency)
                            selected = candidate;
                }
            }

            if (selected.dmDisplayFrequency == current.dmDisplayFrequency)
                return 0;
            int change = ChangeDisplaySettingsEx(device.DeviceName, ref selected, IntPtr.Zero, 0, IntPtr.Zero);
            if (change != DISP_CHANGE_SUCCESSFUL)
                throw new Win32Exception(change, "Cannot change refresh rate for " + device.DeviceName + ".");
            return 1;
        }

        public static int ApplyMaximumRefresh()
        {
            int changed = 0;
            foreach (DISPLAY_DEVICE device in GetActiveDevices())
                changed += ApplyFrequency(device, true, 60, false);
            return changed;
        }

        public static int ApplyMaximumRefresh(string[] deviceNames)
        {
            if (deviceNames == null || deviceNames.Length == 0)
                return 0;
            HashSet<string> selected = new HashSet<string>(deviceNames, StringComparer.OrdinalIgnoreCase);
            int changed = 0;
            foreach (DISPLAY_DEVICE device in GetActiveDevices())
                if (selected.Contains(device.DeviceName))
                    changed += ApplyFrequency(device, true, 60, false);
            return changed;
        }

        public static int ApplyQuietRefresh(int targetHz)
        {
            int changed = 0;
            foreach (DISPLAY_DEVICE device in GetActiveDevices())
                changed += ApplyFrequency(device, false, targetHz, false);
            return changed;
        }

        public static int ApplyFixedRefresh(int targetHz)
        {
            return ApplyFixedRefresh(targetHz, null);
        }

        public static int ApplyFixedRefresh(int targetHz, string[] deviceNames)
        {
            List<DISPLAY_DEVICE> devices = GetActiveDevices();
            if (deviceNames != null)
            {
                HashSet<string> selected = new HashSet<string>(deviceNames, StringComparer.OrdinalIgnoreCase);
                devices = devices.FindAll(delegate(DISPLAY_DEVICE device) { return selected.Contains(device.DeviceName); });
            }
            foreach (DISPLAY_DEVICE device in devices)
            {
                DEVMODE current = NewMode();
                if (!EnumDisplaySettingsEx(device.DeviceName, ENUM_CURRENT_SETTINGS, ref current, 0))
                    continue;
                bool supported = false;
                for (int index = 0; ; index++)
                {
                    DEVMODE candidate = NewMode();
                    if (!EnumDisplaySettingsEx(device.DeviceName, index, ref candidate, 0))
                        break;
                    if (candidate.dmPelsWidth == current.dmPelsWidth &&
                        candidate.dmPelsHeight == current.dmPelsHeight &&
                        candidate.dmBitsPerPel == current.dmBitsPerPel &&
                        Math.Abs(candidate.dmDisplayFrequency - targetHz) <= 1)
                    {
                        supported = true;
                        break;
                    }
                }
                if (!supported)
                    throw new InvalidOperationException(device.DeviceName + " does not expose " + targetHz + " Hz at the current resolution and color depth.");
            }

            int changed = 0;
            foreach (DISPLAY_DEVICE device in devices)
                changed += ApplyFrequency(device, false, targetHz, true);
            return changed;
        }

        public static int[] GetSupportedRefreshRates(string deviceName)
        {
            DISPLAY_DEVICE selectedDevice = new DISPLAY_DEVICE();
            bool found = false;
            foreach (DISPLAY_DEVICE device in GetActiveDevices())
            {
                if (String.Equals(device.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase))
                {
                    selectedDevice = device;
                    found = true;
                    break;
                }
            }
            if (!found)
                return new int[0];

            DEVMODE current = NewMode();
            if (!EnumDisplaySettingsEx(selectedDevice.DeviceName, ENUM_CURRENT_SETTINGS, ref current, 0))
                return new int[0];
            SortedSet<int> rates = new SortedSet<int>();
            for (int index = 0; ; index++)
            {
                DEVMODE candidate = NewMode();
                if (!EnumDisplaySettingsEx(selectedDevice.DeviceName, index, ref candidate, 0))
                    break;
                if (candidate.dmPelsWidth == current.dmPelsWidth &&
                    candidate.dmPelsHeight == current.dmPelsHeight &&
                    candidate.dmBitsPerPel == current.dmBitsPerPel &&
                    candidate.dmDisplayFrequency > 1)
                    rates.Add(candidate.dmDisplayFrequency);
            }
            return new List<int>(rates).ToArray();
        }

        public static bool RestoreMode(string deviceName, int width, int height, int bitsPerPixel,
            int frequency, int positionX, int positionY, int orientation)
        {
            DISPLAY_DEVICE selectedDevice = new DISPLAY_DEVICE();
            bool foundDevice = false;
            foreach (DISPLAY_DEVICE device in GetActiveDevices())
            {
                if (!String.Equals(device.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase))
                    continue;
                selectedDevice = device;
                foundDevice = true;
                break;
            }
            if (!foundDevice)
                throw new InvalidOperationException(deviceName + " is not an active display.");

            DEVMODE current = NewMode();
            if (!EnumDisplaySettingsEx(selectedDevice.DeviceName, ENUM_CURRENT_SETTINGS, ref current, 0))
                throw new Win32Exception("Cannot read the current display mode for " + deviceName + ".");
            if (current.dmPelsWidth == width && current.dmPelsHeight == height &&
                current.dmBitsPerPel == bitsPerPixel && Math.Abs(current.dmDisplayFrequency - frequency) <= 1 &&
                current.dmPositionX == positionX && current.dmPositionY == positionY &&
                current.dmDisplayOrientation == orientation)
                return false;

            DEVMODE selected = NewMode();
            bool foundMode = false;
            for (int index = 0; ; index++)
            {
                DEVMODE candidate = NewMode();
                if (!EnumDisplaySettingsEx(selectedDevice.DeviceName, index, ref candidate, 0))
                    break;
                if (candidate.dmPelsWidth == width && candidate.dmPelsHeight == height &&
                    candidate.dmBitsPerPel == bitsPerPixel && Math.Abs(candidate.dmDisplayFrequency - frequency) <= 1)
                {
                    selected = candidate;
                    foundMode = true;
                    break;
                }
            }
            if (!foundMode)
                throw new InvalidOperationException(deviceName + " no longer exposes its captured display mode.");

            selected.dmPositionX = positionX;
            selected.dmPositionY = positionY;
            selected.dmDisplayOrientation = orientation;
            selected.dmFields |= DM_POSITION | DM_DISPLAYORIENTATION | DM_BITSPERPEL |
                DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
            int change = ChangeDisplaySettingsEx(selectedDevice.DeviceName, ref selected, IntPtr.Zero, 0, IntPtr.Zero);
            if (change != DISP_CHANGE_SUCCESSFUL)
                throw new Win32Exception(change, "Cannot restore the captured mode for " + deviceName + ".");

            DEVMODE verified = NewMode();
            if (!EnumDisplaySettingsEx(selectedDevice.DeviceName, ENUM_CURRENT_SETTINGS, ref verified, 0) ||
                verified.dmPelsWidth != width || verified.dmPelsHeight != height ||
                verified.dmBitsPerPel != bitsPerPixel || Math.Abs(verified.dmDisplayFrequency - frequency) > 1 ||
                verified.dmPositionX != positionX || verified.dmPositionY != positionY ||
                verified.dmDisplayOrientation != orientation)
                throw new InvalidOperationException("Windows accepted but did not retain the captured mode for " + deviceName + ".");
            return true;
        }

        public static void RestoreRegistryModes()
        {
            foreach (DISPLAY_DEVICE device in GetActiveDevices())
                ChangeDisplaySettingsExReset(device.DeviceName, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        }
    }

    public sealed class DynamicRefreshInfo
    {
        public string Key { get; internal set; }
        public string GdiDeviceName { get; internal set; }
        public bool IsInternal { get; internal set; }
        public bool InternalDisplayActive { get; internal set; }
        public bool Supported { get; internal set; }
        public bool Enabled { get; internal set; }
        public int BaseFrequency { get; internal set; }
        public int BoostFrequency { get; internal set; }
        public string Message { get; internal set; }
    }

    public static class DynamicRefreshManager
    {
        private const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
        private const uint QDC_VIRTUAL_MODE_AWARE = 0x00000010;
        private const uint QDC_VIRTUAL_REFRESH_RATE_AWARE = 0x00000040;
        private const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x00000020;
        private const uint SDC_VALIDATE = 0x00000040;
        private const uint SDC_APPLY = 0x00000080;
        private const uint SDC_SAVE_TO_DATABASE = 0x00000200;
        private const uint SDC_ALLOW_CHANGES = 0x00000400;
        private const uint SDC_VIRTUAL_MODE_AWARE = 0x00008000;
        private const uint SDC_VIRTUAL_REFRESH_RATE_AWARE = 0x00020000;
        private const uint DISPLAYCONFIG_PATH_SUPPORT_VIRTUAL_MODE = 0x00000008;
        private const uint DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE = 0x00000010;
        private const uint DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL = 0x80000000;
        private const uint DISPLAYCONFIG_PATH_MODE_IDX_INVALID = 0x0000ffff;
        private const uint DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1;
        private const int ERROR_SUCCESS = 0;
        private const int ERROR_INSUFFICIENT_BUFFER = 122;

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID { public uint LowPart; public int HighPart; }
        [StructLayout(LayoutKind.Sequential)]
        private struct RATIONAL { public uint Numerator; public uint Denominator; }
        [StructLayout(LayoutKind.Sequential)]
        private struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
        [StructLayout(LayoutKind.Sequential)]
        private struct PATH_TARGET
        {
            public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology;
            public uint rotation; public uint scaling; public RATIONAL refreshRate; public uint scanLineOrdering;
            [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable; public uint statusFlags;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct PATH_INFO { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }
        [StructLayout(LayoutKind.Sequential)]
        private struct POINTL { public int x; public int y; }
        [StructLayout(LayoutKind.Sequential)]
        private struct RECTL { public int left; public int top; public int right; public int bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct REGION { public uint cx; public uint cy; }
        [StructLayout(LayoutKind.Sequential)]
        private struct SIGNAL
        {
            public ulong pixelRate; public RATIONAL hSyncFreq; public RATIONAL vSyncFreq;
            public REGION activeSize; public REGION totalSize; public uint videoStandard; public uint scanLineOrdering;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct TARGET_MODE { public SIGNAL signal; }
        [StructLayout(LayoutKind.Sequential)]
        private struct SOURCE_MODE { public uint width; public uint height; public uint pixelFormat; public POINTL position; }
        [StructLayout(LayoutKind.Sequential)]
        private struct DESKTOP_IMAGE { public POINTL size; public RECTL region; public RECTL clip; }
        [StructLayout(LayoutKind.Explicit)]
        private struct MODE_UNION
        {
            [FieldOffset(0)] public TARGET_MODE target;
            [FieldOffset(0)] public SOURCE_MODE source;
            [FieldOffset(0)] public DESKTOP_IMAGE image;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct MODE_INFO { public uint type; public uint id; public LUID adapterId; public MODE_UNION data; }
        [StructLayout(LayoutKind.Sequential)]
        private struct DEVICE_INFO_HEADER { public uint type; public uint size; public LUID adapterId; public uint id; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct SOURCE_DEVICE_NAME
        {
            public DEVICE_INFO_HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
        }

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] PATH_INFO[] pathArray,
            ref uint modes, [Out] MODE_INFO[] modeArray, IntPtr topology);
        [DllImport("user32.dll")]
        private static extern int SetDisplayConfig(uint pathCount, [In] PATH_INFO[] paths,
            uint modeCount, [In] MODE_INFO[] modes, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int DisplayConfigGetDeviceInfo(ref SOURCE_DEVICE_NAME requestPacket);

        private static void Query(out PATH_INFO[] paths, out MODE_INFO[] modes)
        {
            uint flags = QDC_ONLY_ACTIVE_PATHS | QDC_VIRTUAL_MODE_AWARE | QDC_VIRTUAL_REFRESH_RATE_AWARE;
            for (int attempt = 0; attempt < 5; attempt++)
            {
                uint pathCount;
                uint modeCount;
                int result = GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount);
                if (result != ERROR_SUCCESS)
                    throw new Win32Exception(result, "Cannot size display paths for dynamic refresh.");
                PATH_INFO[] pathBuffer = new PATH_INFO[pathCount];
                MODE_INFO[] modeBuffer = new MODE_INFO[modeCount];
                result = QueryDisplayConfig(flags, ref pathCount, pathBuffer, ref modeCount, modeBuffer, IntPtr.Zero);
                if (result == ERROR_INSUFFICIENT_BUFFER)
                    continue;
                if (result != ERROR_SUCCESS)
                    throw new Win32Exception(result, "Cannot query display paths for dynamic refresh.");
                paths = new PATH_INFO[pathCount];
                modes = new MODE_INFO[modeCount];
                Array.Copy(pathBuffer, paths, pathCount);
                Array.Copy(modeBuffer, modes, modeCount);
                return;
            }
            throw new Win32Exception(ERROR_INSUFFICIENT_BUFFER, "Display paths kept changing.");
        }

        private static bool IsInternal(PATH_INFO path)
        {
            uint technology = path.targetInfo.outputTechnology;
            return technology == 6u || technology == 11u || technology == 13u ||
                technology == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL;
        }

        private static string PathKey(PATH_INFO path)
        {
            return path.targetInfo.adapterId.HighPart + ":" + path.targetInfo.adapterId.LowPart + ":" +
                path.targetInfo.id;
        }

        private static string GetSourceName(PATH_INFO path)
        {
            SOURCE_DEVICE_NAME packet = new SOURCE_DEVICE_NAME();
            packet.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            packet.header.size = (uint)Marshal.SizeOf(typeof(SOURCE_DEVICE_NAME));
            packet.header.adapterId = path.sourceInfo.adapterId;
            packet.header.id = path.sourceInfo.id;
            packet.viewGdiDeviceName = String.Empty;
            return DisplayConfigGetDeviceInfo(ref packet) == ERROR_SUCCESS
                ? packet.viewGdiDeviceName ?? String.Empty
                : String.Empty;
        }

        private static string[] GetDisplayDeviceNames(bool internalDisplay)
        {
            PATH_INFO[] paths;
            MODE_INFO[] modes;
            Query(out paths, out modes);
            HashSet<string> names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (PATH_INFO path in paths)
            {
                if (IsInternal(path) != internalDisplay)
                    continue;
                string name = GetSourceName(path);
                if (!String.IsNullOrWhiteSpace(name))
                    names.Add(name);
            }
            string[] result = new string[names.Count];
            names.CopyTo(result);
            return result;
        }

        public static int ApplyExternalMaximumRefresh()
        {
            return DisplayModeManager.ApplyMaximumRefresh(GetDisplayDeviceNames(false));
        }

        public static int ApplyInternalFixedRefresh(int targetHz)
        {
            return DisplayModeManager.ApplyFixedRefresh(targetHz, GetDisplayDeviceNames(true));
        }

        public static int ApplyProfileRefresh(int internalTargetHz)
        {
            int changed = ApplyExternalMaximumRefresh();
            changed += ApplyInternalFixedRefresh(internalTargetHz);
            return changed;
        }

        private static int RationalHz(RATIONAL value)
        {
            if (value.Denominator == 0)
                return 0;
            return (int)Math.Round((double)value.Numerator / value.Denominator);
        }

        private static int TargetModeHz(PATH_INFO path, MODE_INFO[] modes)
        {
            uint index = (path.flags & DISPLAYCONFIG_PATH_SUPPORT_VIRTUAL_MODE) != 0
                ? ((path.targetInfo.modeInfoIdx >> 16) & 0xffffu)
                : path.targetInfo.modeInfoIdx;
            if (index == DISPLAYCONFIG_PATH_MODE_IDX_INVALID || index >= modes.Length || modes[index].type != 2)
                return 0;
            return RationalHz(modes[index].data.target.signal.vSyncFreq);
        }

        public static DynamicRefreshInfo[] GetStatuses()
        {
            PATH_INFO[] paths;
            MODE_INFO[] modes;
            Query(out paths, out modes);
            List<DynamicRefreshInfo> result = new List<DynamicRefreshInfo>();
            foreach (PATH_INFO path in paths)
            {
                DynamicRefreshInfo info = new DynamicRefreshInfo();
                info.Key = PathKey(path);
                info.GdiDeviceName = GetSourceName(path);
                info.IsInternal = IsInternal(path);
                info.InternalDisplayActive = info.IsInternal;
                info.Supported = (path.flags & DISPLAYCONFIG_PATH_SUPPORT_VIRTUAL_MODE) != 0;
                info.Enabled = (path.flags & DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE) != 0;
                info.BaseFrequency = RationalHz(path.targetInfo.refreshRate);
                info.BoostFrequency = TargetModeHz(path, modes);
                info.Message = info.Supported ? "Windows dynamic refresh is available." :
                    "The active path does not advertise virtual refresh support.";
                result.Add(info);
            }
            return result.ToArray();
        }

        public static DynamicRefreshInfo GetStatus()
        {
            foreach (DynamicRefreshInfo item in GetStatuses())
                if (item.IsInternal) return item;
            return new DynamicRefreshInfo
            {
                Key = String.Empty,
                GdiDeviceName = String.Empty,
                Message = "No active internal display path."
            };
        }

        public static bool RestoreStatus(string gdiDeviceName, bool enabled, int baseFrequency, int boostFrequency)
        {
            if (String.IsNullOrWhiteSpace(gdiDeviceName))
                throw new ArgumentException("A display device name is required.", "gdiDeviceName");
            DynamicRefreshInfo previous = null;
            foreach (DynamicRefreshInfo item in GetStatuses())
                if (String.Equals(item.GdiDeviceName, gdiDeviceName, StringComparison.OrdinalIgnoreCase)) { previous = item; break; }
            bool changed = previous == null || previous.Enabled != enabled ||
                (baseFrequency > 1 && Math.Abs(previous.BaseFrequency - baseFrequency) > 1) ||
                (enabled && boostFrequency > 1 && Math.Abs(previous.BoostFrequency - boostFrequency) > 1);
            if (enabled && boostFrequency > 1)
                DisplayModeManager.ApplyFixedRefresh(boostFrequency, new[] { gdiDeviceName });

            PATH_INFO[] paths;
            MODE_INFO[] modes;
            Query(out paths, out modes);
            bool found = false;
            for (int index = 0; index < paths.Length; index++)
            {
                PATH_INFO path = paths[index];
                if (!String.Equals(GetSourceName(path), gdiDeviceName, StringComparison.OrdinalIgnoreCase))
                    continue;
                found = true;
                bool currentEnabled = (path.flags & DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE) != 0;
                if (enabled && (path.flags & DISPLAYCONFIG_PATH_SUPPORT_VIRTUAL_MODE) == 0)
                    throw new InvalidOperationException(gdiDeviceName + " no longer supports Windows dynamic refresh.");
                if (enabled) path.flags |= DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE;
                else path.flags &= ~DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE;
                int requestedFrequency = enabled ? baseFrequency : (boostFrequency > 1 ? boostFrequency : baseFrequency);
                if (requestedFrequency > 1)
                {
                    path.targetInfo.refreshRate.Numerator = (uint)requestedFrequency;
                    path.targetInfo.refreshRate.Denominator = 1;
                }
                paths[index] = path;
                break;
            }
            if (!found)
                throw new InvalidOperationException(gdiDeviceName + " is not an active display path.");

            uint flags = SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES | SDC_SAVE_TO_DATABASE |
                SDC_VIRTUAL_MODE_AWARE | SDC_VIRTUAL_REFRESH_RATE_AWARE;
            int result = SetDisplayConfig((uint)paths.Length, paths, (uint)modes.Length, modes, flags);
            if (result != ERROR_SUCCESS)
                throw new Win32Exception(result, "Cannot restore dynamic refresh for " + gdiDeviceName + ".");

            DynamicRefreshInfo verified = null;
            foreach (DynamicRefreshInfo item in GetStatuses())
                if (String.Equals(item.GdiDeviceName, gdiDeviceName, StringComparison.OrdinalIgnoreCase)) { verified = item; break; }
            if (verified == null || verified.Enabled != enabled ||
                (baseFrequency > 1 && Math.Abs(verified.BaseFrequency - baseFrequency) > 1) ||
                (enabled && boostFrequency > 1 && Math.Abs(verified.BoostFrequency - boostFrequency) > 1))
                throw new InvalidOperationException("Windows accepted but did not retain the captured dynamic refresh state for " + gdiDeviceName + ".");
            return changed;
        }

        public static bool ValidateNativeDynamic()
        {
            PATH_INFO[] paths;
            MODE_INFO[] modes;
            Query(out paths, out modes);
            bool found = false;
            for (int index = 0; index < paths.Length; index++)
            {
                if (!IsInternal(paths[index]))
                    continue;
                if ((paths[index].flags & DISPLAYCONFIG_PATH_SUPPORT_VIRTUAL_MODE) == 0)
                    return false;
                PATH_INFO path = paths[index];
                path.flags |= DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE;
                path.targetInfo.refreshRate.Numerator = 60;
                path.targetInfo.refreshRate.Denominator = 1;
                paths[index] = path;
                found = true;
            }
            if (!found)
                return false;
            uint flags = SDC_VALIDATE | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES |
                SDC_VIRTUAL_MODE_AWARE | SDC_VIRTUAL_REFRESH_RATE_AWARE;
            return SetDisplayConfig((uint)paths.Length, paths, (uint)modes.Length, modes, flags) == ERROR_SUCCESS;
        }

        public static int EnableNativeDynamic()
        {
            DynamicRefreshInfo before = GetStatus();
            if (!before.InternalDisplayActive)
                throw new InvalidOperationException("The internal display is not active; dynamic refresh was not applied.");
            if (!before.Supported)
                throw new InvalidOperationException("The internal display path does not support Windows dynamic refresh.");

            int changed = ApplyExternalMaximumRefresh();
            if (before.Enabled && Math.Abs(before.BaseFrequency - 60) <= 1 && before.BoostFrequency > 60)
                return changed;
            changed += DisplayModeManager.ApplyMaximumRefresh(GetDisplayDeviceNames(true));
            PATH_INFO[] paths;
            MODE_INFO[] modes;
            Query(out paths, out modes);
            for (int index = 0; index < paths.Length; index++)
            {
                if (!IsInternal(paths[index]))
                    continue;
                PATH_INFO path = paths[index];
                path.flags |= DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE;
                path.targetInfo.refreshRate.Numerator = 60;
                path.targetInfo.refreshRate.Denominator = 1;
                paths[index] = path;
            }
            uint flags = SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES | SDC_SAVE_TO_DATABASE |
                SDC_VIRTUAL_MODE_AWARE | SDC_VIRTUAL_REFRESH_RATE_AWARE;
            int result = SetDisplayConfig((uint)paths.Length, paths, (uint)modes.Length, modes, flags);
            if (result != ERROR_SUCCESS)
                throw new Win32Exception(result, "Cannot enable Windows dynamic refresh.");
            DynamicRefreshInfo after = GetStatus();
            if (!after.Enabled || Math.Abs(after.BaseFrequency - 60) > 1 || after.BoostFrequency <= 60)
            {
                try { Disable(); } catch { }
                try { DisplayModeManager.ApplyMaximumRefresh(GetDisplayDeviceNames(true)); } catch { }
                throw new InvalidOperationException("Windows accepted the request but did not report a valid native dynamic refresh range.");
            }
            return changed + 1;
        }

        public static bool Validate60To120()
        {
            return ValidateNativeDynamic();
        }

        public static int Enable60To120()
        {
            throw new InvalidOperationException("Exact 60-to-120 Hz native DRR is not exposed by this panel path. Use fixed 120 Hz or native dynamic refresh instead.");
        }

        public static int Disable()
        {
            PATH_INFO[] paths;
            MODE_INFO[] modes;
            Query(out paths, out modes);
            bool changed = false;
            for (int index = 0; index < paths.Length; index++)
            {
                if (!IsInternal(paths[index]) || (paths[index].flags & DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE) == 0)
                    continue;
                PATH_INFO path = paths[index];
                path.flags &= ~DISPLAYCONFIG_PATH_BOOST_REFRESH_RATE;
                int physicalHz = TargetModeHz(path, modes);
                if (physicalHz > 0)
                {
                    path.targetInfo.refreshRate.Numerator = (uint)physicalHz;
                    path.targetInfo.refreshRate.Denominator = 1;
                }
                paths[index] = path;
                changed = true;
            }
            if (!changed)
                return 0;
            uint flags = SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES | SDC_SAVE_TO_DATABASE |
                SDC_VIRTUAL_MODE_AWARE | SDC_VIRTUAL_REFRESH_RATE_AWARE;
            int result = SetDisplayConfig((uint)paths.Length, paths, (uint)modes.Length, modes, flags);
            if (result != ERROR_SUCCESS)
                throw new Win32Exception(result, "Cannot disable Windows dynamic refresh.");
            return 1;
        }
    }

    public sealed class AdvancedColorInfo
    {
        public string Key { get; internal set; }
        public string GdiDeviceName { get; internal set; }
        public bool Supported { get; internal set; }
        public bool Enabled { get; internal set; }
        public uint BitsPerColorChannel { get; internal set; }
    }

    public static class AdvancedColorManager
    {
        private const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
        private const uint QDC_VIRTUAL_MODE_AWARE = 0x00000010;
        private const int ERROR_SUCCESS = 0;
        private const int ERROR_INSUFFICIENT_BUFFER = 122;
        private const int GET_ADVANCED_COLOR_INFO = 9;
        private const int SET_ADVANCED_COLOR_STATE = 10;
        private const int GET_SOURCE_NAME = 1;
        private static readonly Dictionary<string, bool> OriginalStates =
            new Dictionary<string, bool>(StringComparer.Ordinal);

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID
        {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RATIONAL { public uint Numerator; public uint Denominator; }
        [StructLayout(LayoutKind.Sequential)]
        private struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
        [StructLayout(LayoutKind.Sequential)]
        private struct PATH_TARGET
        {
            public LUID adapterId; public uint id; public uint modeInfoIdx; public uint outputTechnology;
            public uint rotation; public uint scaling; public RATIONAL refreshRate; public uint scanLineOrdering;
            [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable; public uint statusFlags;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct PATH_INFO { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }
        [StructLayout(LayoutKind.Sequential)]
        private struct POINTL { public int x; public int y; }
        [StructLayout(LayoutKind.Sequential)]
        private struct RECTL { public int left; public int top; public int right; public int bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct REGION { public uint cx; public uint cy; }
        [StructLayout(LayoutKind.Sequential)]
        private struct SIGNAL
        {
            public ulong pixelRate; public RATIONAL hSyncFreq; public RATIONAL vSyncFreq;
            public REGION activeSize; public REGION totalSize; public uint videoStandard; public uint scanLineOrdering;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct TARGET_MODE { public SIGNAL signal; }
        [StructLayout(LayoutKind.Sequential)]
        private struct SOURCE_MODE { public uint width; public uint height; public uint pixelFormat; public POINTL position; }
        [StructLayout(LayoutKind.Sequential)]
        private struct DESKTOP_IMAGE { public POINTL size; public RECTL region; public RECTL clip; }
        [StructLayout(LayoutKind.Explicit)]
        private struct MODE_UNION
        {
            [FieldOffset(0)] public TARGET_MODE target;
            [FieldOffset(0)] public SOURCE_MODE source;
            [FieldOffset(0)] public DESKTOP_IMAGE image;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct MODE_INFO { public uint type; public uint id; public LUID adapterId; public MODE_UNION data; }
        [StructLayout(LayoutKind.Sequential)]
        private struct HEADER { public int type; public uint size; public LUID adapterId; public uint id; }
        [StructLayout(LayoutKind.Sequential)]
        private struct COLOR_GET
        {
            public HEADER header;
            public uint value;
            public uint colorEncoding;
            public uint bitsPerColorChannel;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct COLOR_SET { public HEADER header; public uint value; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct SOURCE_NAME
        {
            public HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
        }

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] PATH_INFO[] pathArray,
            ref uint modes, [Out] MODE_INFO[] modeArray, IntPtr topology);
        [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
        private static extern int GetColorInfo(ref COLOR_GET packet);
        [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
        private static extern int GetSourceInfo(ref SOURCE_NAME packet);
        [DllImport("user32.dll", EntryPoint = "DisplayConfigSetDeviceInfo")]
        private static extern int SetColorInfo(ref COLOR_SET packet);

        private static PATH_INFO[] GetPaths()
        {
            uint flags = QDC_ONLY_ACTIVE_PATHS | QDC_VIRTUAL_MODE_AWARE;
            for (int attempt = 0; attempt < 5; attempt++)
            {
                uint pathCount;
                uint modeCount;
                int result = GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount);
                if (result != ERROR_SUCCESS)
                    throw new Win32Exception(result, "Cannot size display paths for advanced color.");
                PATH_INFO[] paths = new PATH_INFO[pathCount];
                MODE_INFO[] modes = new MODE_INFO[modeCount];
                result = QueryDisplayConfig(flags, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
                if (result == ERROR_INSUFFICIENT_BUFFER)
                    continue;
                if (result != ERROR_SUCCESS)
                    throw new Win32Exception(result, "Cannot query display paths for advanced color.");
                if (pathCount == paths.Length)
                    return paths;
                PATH_INFO[] trimmed = new PATH_INFO[pathCount];
                Array.Copy(paths, trimmed, pathCount);
                return trimmed;
            }
            throw new Win32Exception(ERROR_INSUFFICIENT_BUFFER, "Display paths kept changing.");
        }

        private static string Key(PATH_TARGET target)
        {
            return target.adapterId.HighPart + ":" + target.adapterId.LowPart + ":" + target.id;
        }

        private static string SourceName(PATH_SOURCE source)
        {
            SOURCE_NAME packet = new SOURCE_NAME();
            packet.header.type = GET_SOURCE_NAME;
            packet.header.size = (uint)Marshal.SizeOf(typeof(SOURCE_NAME));
            packet.header.adapterId = source.adapterId;
            packet.header.id = source.id;
            packet.viewGdiDeviceName = String.Empty;
            return GetSourceInfo(ref packet) == ERROR_SUCCESS
                ? packet.viewGdiDeviceName ?? String.Empty
                : String.Empty;
        }

        private static bool TryGet(PATH_TARGET target, out COLOR_GET packet)
        {
            packet = new COLOR_GET();
            packet.header.type = GET_ADVANCED_COLOR_INFO;
            packet.header.size = (uint)Marshal.SizeOf(typeof(COLOR_GET));
            packet.header.adapterId = target.adapterId;
            packet.header.id = target.id;
            return GetColorInfo(ref packet) == ERROR_SUCCESS;
        }

        private static bool Set(PATH_TARGET target, bool enabled)
        {
            COLOR_GET current;
            if (!TryGet(target, out current) || (current.value & 1u) == 0)
                return false;
            bool isEnabled = (current.value & 2u) != 0;
            if (isEnabled == enabled)
                return false;
            COLOR_SET packet = new COLOR_SET();
            packet.header.type = SET_ADVANCED_COLOR_STATE;
            packet.header.size = (uint)Marshal.SizeOf(typeof(COLOR_SET));
            packet.header.adapterId = target.adapterId;
            packet.header.id = target.id;
            packet.value = enabled ? 1u : 0u;
            int result = SetColorInfo(ref packet);
            if (result != ERROR_SUCCESS)
                throw new Win32Exception(result, "Cannot change advanced color state.");
            return true;
        }

        public static AdvancedColorInfo[] GetStatus()
        {
            List<AdvancedColorInfo> result = new List<AdvancedColorInfo>();
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (PATH_INFO path in GetPaths())
            {
                string key = Key(path.targetInfo);
                if (!seen.Add(key))
                    continue;
                COLOR_GET packet;
                if (!TryGet(path.targetInfo, out packet))
                    continue;
                AdvancedColorInfo info = new AdvancedColorInfo();
                info.Key = key;
                info.GdiDeviceName = SourceName(path.sourceInfo);
                info.Supported = (packet.value & 1u) != 0;
                info.Enabled = (packet.value & 2u) != 0;
                info.BitsPerColorChannel = packet.bitsPerColorChannel;
                result.Add(info);
            }
            return result.ToArray();
        }

        public static int CaptureAndDisable()
        {
            int changed = 0;
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (PATH_INFO path in GetPaths())
            {
                string key = Key(path.targetInfo);
                if (!seen.Add(key))
                    continue;
                COLOR_GET packet;
                if (!TryGet(path.targetInfo, out packet) || (packet.value & 1u) == 0)
                    continue;
                bool enabled = (packet.value & 2u) != 0;
                if (!OriginalStates.ContainsKey(key))
                    OriginalStates.Add(key, enabled);
                if (enabled && Set(path.targetInfo, false))
                    changed++;
            }
            return changed;
        }

        public static bool SetEnabled(string key, bool enabled)
        {
            foreach (PATH_INFO path in GetPaths())
            {
                if (!String.Equals(Key(path.targetInfo), key, StringComparison.Ordinal))
                    continue;
                bool changed = Set(path.targetInfo, enabled);
                COLOR_GET verified;
                if (!TryGet(path.targetInfo, out verified) || ((verified.value & 2u) != 0) != enabled)
                    throw new InvalidOperationException("Windows accepted but did not retain the requested advanced color state for " + key + ".");
                return changed;
            }
            return false;
        }

        public static int RestoreCaptured()
        {
            int changed = 0;
            foreach (PATH_INFO path in GetPaths())
            {
                string key = Key(path.targetInfo);
                bool original;
                if (OriginalStates.TryGetValue(key, out original) && Set(path.targetInfo, original))
                    changed++;
            }
            OriginalStates.Clear();
            return changed;
        }
    }

    public sealed class ColorProfileInfo
    {
        public string GdiDeviceName { get; internal set; }
        public string ProfilePath { get; internal set; }
        public bool Available { get; internal set; }
        public string Error { get; internal set; }
    }

    public static class ColorProfileManager
    {
        private const int ICM_ON = 2;

        [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr CreateDC(string driver, string device, string output, IntPtr initData);
        [DllImport("gdi32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteDC(IntPtr deviceContext);
        [DllImport("gdi32.dll")]
        private static extern int SetICMMode(IntPtr deviceContext, int mode);
        [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetICMProfileW")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetICMProfile(IntPtr deviceContext, ref uint length, StringBuilder fileName);
        [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "SetICMProfileW")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetICMProfile(IntPtr deviceContext, string fileName);

        private static ColorProfileInfo ReadOne(string deviceName)
        {
            ColorProfileInfo result = new ColorProfileInfo
            {
                GdiDeviceName = deviceName,
                ProfilePath = String.Empty,
                Error = String.Empty
            };
            IntPtr context = CreateDC("DISPLAY", deviceName, null, IntPtr.Zero);
            if (context == IntPtr.Zero)
            {
                result.Error = "CreateDC failed: " + Marshal.GetLastWin32Error();
                return result;
            }
            try
            {
                SetICMMode(context, ICM_ON);
                uint length = 0;
                GetICMProfile(context, ref length, null);
                if (length == 0) length = 1024;
                StringBuilder profile = new StringBuilder((int)length + 1);
                if (!GetICMProfile(context, ref length, profile))
                {
                    result.Error = "GetICMProfile failed: " + Marshal.GetLastWin32Error();
                    return result;
                }
                result.ProfilePath = profile.ToString();
                result.Available = !String.IsNullOrWhiteSpace(result.ProfilePath);
                return result;
            }
            finally { DeleteDC(context); }
        }

        public static ColorProfileInfo[] GetStatus()
        {
            List<ColorProfileInfo> result = new List<ColorProfileInfo>();
            foreach (DisplayModeInfo display in DisplayModeManager.GetActiveDisplays())
                result.Add(ReadOne(display.DeviceName));
            return result.ToArray();
        }

        public static bool SetProfile(string deviceName, string profilePath)
        {
            if (String.IsNullOrWhiteSpace(deviceName))
                throw new ArgumentException("A display device name is required.", "deviceName");
            if (String.IsNullOrWhiteSpace(profilePath) || !File.Exists(profilePath))
                throw new FileNotFoundException("The captured ICC profile is unavailable.", profilePath);
            ColorProfileInfo before = ReadOne(deviceName);
            if (before.Available && String.Equals(before.ProfilePath, profilePath, StringComparison.OrdinalIgnoreCase))
                return false;

            IntPtr context = CreateDC("DISPLAY", deviceName, null, IntPtr.Zero);
            if (context == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open the display color context for " + deviceName + ".");
            try
            {
                SetICMMode(context, ICM_ON);
                if (!SetICMProfile(context, profilePath))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot restore the ICC profile for " + deviceName + ".");
            }
            finally { DeleteDC(context); }

            ColorProfileInfo verified = ReadOne(deviceName);
            if (!verified.Available || !String.Equals(verified.ProfilePath, profilePath, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Windows accepted but did not retain the ICC profile for " + deviceName + ".");
            return true;
        }
    }

    public sealed class PhysicalMonitorBrightnessInfo
    {
        public string GdiDeviceName { get; internal set; }
        public int PhysicalIndex { get; internal set; }
        public string Description { get; internal set; }
        public bool Supported { get; internal set; }
        public uint Minimum { get; internal set; }
        public uint Current { get; internal set; }
        public uint Maximum { get; internal set; }
        public int CurrentPercent { get; internal set; }
        public string Error { get; internal set; }
    }

    public static class PhysicalMonitorBrightnessManager
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int left;
            public int top;
            public int right;
            public int bottom;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct MONITORINFOEX
        {
            public uint cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string szDevice;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct PHYSICAL_MONITOR
        {
            public IntPtr hPhysicalMonitor;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string szPhysicalMonitorDescription;
        }

        private delegate bool MonitorEnumProc(IntPtr monitor, IntPtr hdc, IntPtr monitorRect, IntPtr data);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clipRect, MonitorEnumProc callback, IntPtr data);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFOEX info);
        [DllImport("dxva2.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out uint count);
        [DllImport("dxva2.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, uint count, [Out] PHYSICAL_MONITOR[] physicalMonitors);
        [DllImport("dxva2.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyPhysicalMonitors(uint count, PHYSICAL_MONITOR[] physicalMonitors);
        [DllImport("dxva2.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMonitorBrightness(IntPtr physicalMonitor, out uint minimum, out uint current, out uint maximum);
        [DllImport("dxva2.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetMonitorBrightness(IntPtr physicalMonitor, uint value);

        private static int ToPercent(uint minimum, uint current, uint maximum)
        {
            if (maximum <= minimum) return 0;
            double percent = (current - minimum) * 100.0 / (maximum - minimum);
            return (int)Math.Round(Math.Max(0.0, Math.Min(100.0, percent)));
        }

        private static PhysicalMonitorBrightnessInfo ReadOne(string deviceName, int index, PHYSICAL_MONITOR monitor)
        {
            PhysicalMonitorBrightnessInfo result = new PhysicalMonitorBrightnessInfo
            {
                GdiDeviceName = deviceName ?? String.Empty,
                PhysicalIndex = index,
                Description = monitor.szPhysicalMonitorDescription ?? String.Empty,
                Error = String.Empty
            };
            uint minimum;
            uint current;
            uint maximum;
            if (!GetMonitorBrightness(monitor.hPhysicalMonitor, out minimum, out current, out maximum))
            {
                result.Error = "DDC/CI brightness is unavailable: " + Marshal.GetLastWin32Error();
                return result;
            }
            result.Supported = true;
            result.Minimum = minimum;
            result.Current = current;
            result.Maximum = maximum;
            result.CurrentPercent = ToPercent(minimum, current, maximum);
            return result;
        }

        public static PhysicalMonitorBrightnessInfo[] GetStatus()
        {
            List<PhysicalMonitorBrightnessInfo> result = new List<PhysicalMonitorBrightnessInfo>();
            MonitorEnumProc callback = delegate(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data)
            {
                MONITORINFOEX info = new MONITORINFOEX();
                info.cbSize = (uint)Marshal.SizeOf(typeof(MONITORINFOEX));
                string deviceName = GetMonitorInfo(monitor, ref info) ? info.szDevice ?? String.Empty : String.Empty;
                uint count;
                if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out count) || count == 0)
                {
                    result.Add(new PhysicalMonitorBrightnessInfo
                    {
                        GdiDeviceName = deviceName,
                        PhysicalIndex = -1,
                        Description = String.Empty,
                        Error = "No DDC/CI physical monitor endpoint: " + Marshal.GetLastWin32Error()
                    });
                    return true;
                }
                PHYSICAL_MONITOR[] physical = new PHYSICAL_MONITOR[count];
                if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical))
                {
                    result.Add(new PhysicalMonitorBrightnessInfo
                    {
                        GdiDeviceName = deviceName,
                        PhysicalIndex = -1,
                        Description = String.Empty,
                        Error = "Cannot enumerate DDC/CI monitor endpoints: " + Marshal.GetLastWin32Error()
                    });
                    return true;
                }
                try
                {
                    for (int index = 0; index < physical.Length; index++)
                        result.Add(ReadOne(deviceName, index, physical[index]));
                }
                finally { DestroyPhysicalMonitors(count, physical); }
                return true;
            };
            if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot enumerate physical monitors.");
            GC.KeepAlive(callback);
            return result.ToArray();
        }

        public static bool SetBrightness(string gdiDeviceName, int physicalIndex, uint value)
        {
            if (String.IsNullOrWhiteSpace(gdiDeviceName))
                throw new ArgumentException("A display device name is required.", "gdiDeviceName");
            bool found = false;
            bool changed = false;
            Exception failure = null;
            MonitorEnumProc callback = delegate(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data)
            {
                MONITORINFOEX info = new MONITORINFOEX();
                info.cbSize = (uint)Marshal.SizeOf(typeof(MONITORINFOEX));
                if (!GetMonitorInfo(monitor, ref info) ||
                    !String.Equals(info.szDevice, gdiDeviceName, StringComparison.OrdinalIgnoreCase)) return true;
                uint count;
                if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out count) || physicalIndex < 0 || physicalIndex >= count)
                {
                    failure = new InvalidOperationException("The captured DDC/CI brightness endpoint is no longer available for " + gdiDeviceName + ".");
                    return false;
                }
                PHYSICAL_MONITOR[] physical = new PHYSICAL_MONITOR[count];
                if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical))
                {
                    failure = new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open the DDC/CI brightness endpoint for " + gdiDeviceName + ".");
                    return false;
                }
                try
                {
                    found = true;
                    uint minimum;
                    uint current;
                    uint maximum;
                    if (!GetMonitorBrightness(physical[physicalIndex].hPhysicalMonitor, out minimum, out current, out maximum))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot read the DDC/CI brightness endpoint for " + gdiDeviceName + ".");
                    uint target = Math.Max(minimum, Math.Min(maximum, value));
                    if (current == target) return false;
                    if (!SetMonitorBrightness(physical[physicalIndex].hPhysicalMonitor, target))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot restore DDC/CI brightness for " + gdiDeviceName + ".");
                    uint verified;
                    if (!GetMonitorBrightness(physical[physicalIndex].hPhysicalMonitor, out minimum, out verified, out maximum) || verified != target)
                        throw new InvalidOperationException("The monitor accepted but did not retain DDC/CI brightness for " + gdiDeviceName + ".");
                    changed = true;
                }
                catch (Exception exception) { failure = exception; }
                finally { DestroyPhysicalMonitors(count, physical); }
                return false;
            };
            bool enumerationCompleted = EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
            if (!enumerationCompleted && !found && failure == null)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot enumerate physical monitors.");
            GC.KeepAlive(callback);
            if (failure != null) throw failure;
            if (!found) throw new InvalidOperationException("The captured display is no longer active: " + gdiDeviceName + ".");
            return changed;
        }
    }

    public sealed class ThermalZoneSample
    {
        public string Name { get; internal set; }
        public double TemperatureC { get; internal set; }
        public long ThrottleReasons { get; internal set; }
        public bool Throttled { get { return ThrottleReasons != 0; } }
    }

    public sealed class HardwareTelemetrySample
    {
        public bool Available { get; internal set; }
        public long SampledAtUtcTicks { get; internal set; }
        public ThermalZoneSample[] ThermalZones { get; internal set; }
        public double MaximumTemperatureC { get; internal set; }
        public bool ThermalThrottlingDetected { get; internal set; }
        public double CpuActualFrequencyMhz { get; internal set; }
        public double CpuPercentMaximumFrequency { get; internal set; }
        public bool NpuAvailable { get; internal set; }
        public double NpuUtilizationPercent { get; internal set; }
        public string NpuCounterSet { get; internal set; }
        public string Error { get; internal set; }
    }

    public static class HardwareTelemetry
    {
        private static readonly object SyncRoot = new object();
        private static bool npuDiscoveryComplete;
        private static string npuCategoryName = String.Empty;
        private static string npuCounterName = String.Empty;

        private static double ReadCounter(string category, string counter, string instance)
        {
            using (PerformanceCounter value = new PerformanceCounter(category, counter, instance, true))
                return value.NextValue();
        }

        private static void DiscoverNpuCounter()
        {
            if (npuDiscoveryComplete) return;
            npuDiscoveryComplete = true;
            try
            {
                foreach (PerformanceCounterCategory category in PerformanceCounterCategory.GetCategories())
                {
                    if (!Regex.IsMatch(category.CategoryName, @"(^|\b)(NPU|Neural|AI Engine)(\b|$)", RegexOptions.IgnoreCase))
                        continue;
                    string[] instances = category.GetInstanceNames();
                    PerformanceCounter[] counters = instances.Length > 0
                        ? category.GetCounters(instances[0])
                        : category.GetCounters();
                    try
                    {
                        foreach (PerformanceCounter counter in counters)
                        {
                            if (Regex.IsMatch(counter.CounterName, @"utili[sz]ation|%.*(usage|time)", RegexOptions.IgnoreCase))
                            {
                                npuCategoryName = category.CategoryName;
                                npuCounterName = counter.CounterName;
                                return;
                            }
                        }
                    }
                    finally { foreach (PerformanceCounter counter in counters) counter.Dispose(); }
                }
            }
            catch { }
        }

        public static HardwareTelemetrySample Read()
        {
            lock (SyncRoot)
            {
                HardwareTelemetrySample result = new HardwareTelemetrySample
                {
                    SampledAtUtcTicks = DateTime.UtcNow.Ticks,
                    ThermalZones = new ThermalZoneSample[0],
                    NpuCounterSet = String.Empty,
                    Error = String.Empty
                };
                List<string> errors = new List<string>();
                try
                {
                    PerformanceCounterCategory category = new PerformanceCounterCategory("Thermal Zone Information");
                    List<ThermalZoneSample> zones = new List<ThermalZoneSample>();
                    foreach (string instance in category.GetInstanceNames())
                    {
                        try
                        {
                            double rawTemperature = ReadCounter("Thermal Zone Information", "High Precision Temperature", instance);
                            long reasons = (long)Math.Round(ReadCounter("Thermal Zone Information", "Throttle Reasons", instance));
                            double celsius = Math.Round(rawTemperature / 10.0 - 273.15, 1);
                            if (celsius < -100 || celsius > 200) continue;
                            ThermalZoneSample zone = new ThermalZoneSample
                            {
                                Name = instance,
                                TemperatureC = celsius,
                                ThrottleReasons = reasons
                            };
                            zones.Add(zone);
                            result.MaximumTemperatureC = Math.Max(result.MaximumTemperatureC, celsius);
                            result.ThermalThrottlingDetected |= zone.Throttled;
                        }
                        catch (Exception exception) { errors.Add(instance + ": " + exception.Message); }
                    }
                    result.ThermalZones = zones.ToArray();
                }
                catch (Exception exception) { errors.Add("thermal: " + exception.Message); }

                try { result.CpuActualFrequencyMhz = Math.Round(ReadCounter("Processor Information", "Actual Frequency", "_Total"), 1); }
                catch (Exception exception) { errors.Add("cpu frequency: " + exception.Message); }
                try { result.CpuPercentMaximumFrequency = Math.Round(ReadCounter("Processor Information", "% of Maximum Frequency", "_Total"), 1); }
                catch (Exception exception) { errors.Add("cpu maximum frequency: " + exception.Message); }

                DiscoverNpuCounter();
                if (!String.IsNullOrWhiteSpace(npuCategoryName))
                {
                    result.NpuCounterSet = npuCategoryName + "\\" + npuCounterName;
                    try
                    {
                        PerformanceCounterCategory category = new PerformanceCounterCategory(npuCategoryName);
                        double maximum = 0;
                        string[] instances = category.GetInstanceNames();
                        if (instances.Length == 0)
                            maximum = ReadCounter(npuCategoryName, npuCounterName, String.Empty);
                        else
                            foreach (string instance in instances)
                                maximum = Math.Max(maximum, ReadCounter(npuCategoryName, npuCounterName, instance));
                        result.NpuAvailable = true;
                        result.NpuUtilizationPercent = Math.Round(Math.Min(100.0, Math.Max(0.0, maximum)), 1);
                    }
                    catch (Exception exception) { errors.Add("npu: " + exception.Message); }
                }
                result.Available = result.ThermalZones.Length > 0 || result.CpuActualFrequencyMhz > 0 || result.NpuAvailable;
                result.Error = String.Join("; ", errors.ToArray());
                return result;
            }
        }
    }

    public sealed class RazerMouseDevice
    {
        public int VendorId { get; internal set; }
        public int ProductId { get; internal set; }
        public string Name { get; internal set; }
        public string Connection { get; internal set; }
        public string FirmwareVersion { get; internal set; }
        public string SerialNumber { get; internal set; }
        public int? DpiX { get; internal set; }
        public int? DpiY { get; internal set; }
        public int? PollingRate { get; internal set; }
        public int? BatteryPercent { get; internal set; }
        public bool? IsCharging { get; internal set; }
    }

    /// <summary>
    /// Supported HID feature-report access for the Razer DeathAdder V3 Pro.
    /// This talks only to the standard HID control collection exposed by the
    /// device/receiver. It does not install or replace a kernel-mode driver.
    /// </summary>
    public static class RazerMouse
    {
        private const ushort VendorId = 0x1532;
        private const ushort ControlUsagePage = 0x000C;
        private const uint GenericRead = 0x80000000;
        private const uint GenericWrite = 0x40000000;
        private const uint ShareRead = 0x00000001;
        private const uint ShareWrite = 0x00000002;
        private const uint OpenExisting = 3;
        private const uint PresentDeviceInterfaces = 0x12;

        private static readonly Dictionary<ushort, string> SupportedProducts =
            new Dictionary<ushort, string>
            {
                { 0x00B6, "Razer DeathAdder V3 Pro (Wired)" },
                { 0x00B7, "Razer DeathAdder V3 Pro (Wireless)" },
                { 0x00C2, "Razer DeathAdder V3 Pro (Wired Alt)" },
                { 0x00C3, "Razer DeathAdder V3 Pro (Wireless Alt)" }
            };

        public static RazerMouseDevice[] GetDevices()
        {
            List<RazerMouseDevice> devices = new List<RazerMouseDevice>();
            foreach (HidEndpoint endpoint in Enumerate())
            {
                try { devices.Add(ReadSnapshot(endpoint)); }
                catch { devices.Add(ToDevice(endpoint)); }
            }
            return devices.ToArray();
        }

        public static void SetDpi(int x, int y)
        {
            SetDpi(x, y, -1);
        }

        public static void SetDpi(int x, int y, int productId)
        {
            if (x < 100 || x > 30000 || y < 100 || y > 30000)
                throw new ArgumentOutOfRangeException("x", "DeathAdder V3 Pro DPI must be between 100 and 30000.");
            WithDevice(productId, delegate(RazerTransport transport)
            {
                transport.Send(delegate(byte transactionId) { return BuildSetDpi(transactionId, x, y); });
            });
        }

        public static void SetPollingRate(int hertz)
        {
            SetPollingRate(hertz, -1);
        }

        public static void SetPollingRate(int hertz, int productId)
        {
            if (hertz != 125 && hertz != 500 && hertz != 1000)
                throw new ArgumentOutOfRangeException("hertz", "DeathAdder V3 Pro supports 125, 500, or 1000 Hz on the standard receiver.");
            WithDevice(productId, delegate(RazerTransport transport)
            {
                transport.Send(delegate(byte transactionId) { return BuildSetPollingRate(transactionId, hertz); });
            });
        }

        private static RazerMouseDevice ReadSnapshot(HidEndpoint endpoint)
        {
            using (RazerTransport transport = new RazerTransport(endpoint))
            {
                byte[] firmware = transport.TryQuery(BuildGetFirmware);
                byte[] serial = transport.TryQuery(BuildGetSerial);
                byte[] polling = transport.TryQuery(BuildGetPollingRate);
                byte[] dpi = transport.TryQuery(BuildGetDpi);
                byte[] battery = transport.TryQuery(BuildGetBattery);
                byte[] charging = transport.TryQuery(BuildGetCharging);
                RazerMouseDevice device = ToDevice(endpoint);
                device.FirmwareVersion = firmware == null ? null : String.Format("v{0}.{1}", firmware[8], firmware[9]);
                device.SerialNumber = serial == null
                    ? null
                    : Encoding.ASCII.GetString(serial, 8, Math.Min(22, serial.Length - 8)).TrimEnd('\0', ' ');
                device.DpiX = dpi == null ? (int?)null : (dpi[9] << 8) | dpi[10];
                device.DpiY = dpi == null ? (int?)null : (dpi[11] << 8) | dpi[12];
                device.PollingRate = polling == null ? (int?)null : DecodePolling(polling[8]);
                device.BatteryPercent = battery == null
                    ? (int?)null
                    : (int)Math.Round(battery[9] * 100.0 / 255.0);
                device.IsCharging = charging == null ? (bool?)null : charging[9] != 0;
                return device;
            }
        }

        private static RazerMouseDevice ToDevice(HidEndpoint endpoint)
        {
            return new RazerMouseDevice
            {
                VendorId = VendorId,
                ProductId = endpoint.ProductId,
                Name = endpoint.Name,
                Connection = IsWireless(endpoint.ProductId) ? "Wireless" : "Wired"
            };
        }

        private static bool IsWireless(ushort productId)
        {
            return productId == 0x00B7 || productId == 0x00C3;
        }

        private static int DecodePolling(byte code)
        {
            if (code == 0x01) return 1000;
            if (code == 0x02) return 500;
            if (code == 0x08) return 125;
            return 0;
        }

        private static void WithDevice(int productId, Action<RazerTransport> action)
        {
            HidEndpoint selected = null;
            foreach (HidEndpoint endpoint in Enumerate())
            {
                if (productId >= 0 && endpoint.ProductId != productId) continue;
                if (selected == null || (!IsWireless(selected.ProductId) && IsWireless(endpoint.ProductId)))
                    selected = endpoint;
            }
            if (selected == null)
                throw new InvalidOperationException("No supported DeathAdder V3 Pro control interface is connected.");
            using (RazerTransport transport = new RazerTransport(selected))
                action(transport);
        }

        private static HidEndpoint[] Enumerate()
        {
            Guid hidGuid;
            HidD_GetHidGuid(out hidGuid);
            IntPtr set = SetupDiGetClassDevs(ref hidGuid, null, IntPtr.Zero, PresentDeviceInterfaces);
            if (set == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            Dictionary<ushort, HidEndpoint> endpoints = new Dictionary<ushort, HidEndpoint>();
            try
            {
                SP_DEVICE_INTERFACE_DATA item = new SP_DEVICE_INTERFACE_DATA();
                item.Size = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                for (uint index = 0; SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hidGuid, index, ref item); index++)
                {
                    uint required;
                    SetupDiGetDeviceInterfaceDetail(set, ref item, IntPtr.Zero, 0, out required, IntPtr.Zero);
                    if (required == 0) continue;
                    IntPtr detail = Marshal.AllocHGlobal((int)required);
                    try
                    {
                        Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                        if (!SetupDiGetDeviceInterfaceDetail(set, ref item, detail, required, out required, IntPtr.Zero))
                            continue;
                        string path = Marshal.PtrToStringUni(IntPtr.Add(detail, 4));
                        if (String.IsNullOrWhiteSpace(path)) continue;
                        using (SafeFileHandle handle = Open(path, 0))
                        {
                            if (handle.IsInvalid) continue;
                            HIDD_ATTRIBUTES attributes = new HIDD_ATTRIBUTES();
                            attributes.Size = Marshal.SizeOf(typeof(HIDD_ATTRIBUTES));
                            string defaultName;
                            if (!HidD_GetAttributes(handle, ref attributes)
                                || attributes.VendorId != VendorId
                                || !SupportedProducts.TryGetValue(attributes.ProductId, out defaultName)
                                || GetUsagePage(handle) != ControlUsagePage)
                                continue;
                            string name = GetProductName(handle);
                            if (String.IsNullOrWhiteSpace(name)) name = defaultName;
                            if (!endpoints.ContainsKey(attributes.ProductId))
                                endpoints.Add(attributes.ProductId, new HidEndpoint(path, attributes.ProductId, name));
                        }
                    }
                    finally { Marshal.FreeHGlobal(detail); }
                }
            }
            finally { SetupDiDestroyDeviceInfoList(set); }
            HidEndpoint[] result = new HidEndpoint[endpoints.Count];
            endpoints.Values.CopyTo(result, 0);
            return result;
        }

        private static ushort GetUsagePage(SafeFileHandle handle)
        {
            IntPtr data;
            if (!HidD_GetPreparsedData(handle, out data)) return 0;
            try
            {
                HIDP_CAPS caps;
                return HidP_GetCaps(data, out caps) >= 0 ? caps.UsagePage : (ushort)0;
            }
            finally { HidD_FreePreparsedData(data); }
        }

        private static string GetProductName(SafeFileHandle handle)
        {
            byte[] buffer = new byte[256];
            return HidD_GetProductString(handle, buffer, buffer.Length)
                ? Encoding.Unicode.GetString(buffer).TrimEnd('\0')
                : null;
        }

        private static SafeFileHandle Open(string path, uint access)
        {
            return CreateFile(path, access, ShareRead | ShareWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        }

        private static byte[] BuildGetFirmware(byte transactionId) { return Build(transactionId, 0x00, 0x81, 0x02, null); }
        private static byte[] BuildGetSerial(byte transactionId) { return Build(transactionId, 0x00, 0x82, 0x16, null); }
        private static byte[] BuildGetPollingRate(byte transactionId) { return Build(transactionId, 0x00, 0x85, 0x01, null); }
        private static byte[] BuildGetDpi(byte transactionId) { return Build(transactionId, 0x04, 0x85, 0x07, new byte[] { 0x01 }); }
        private static byte[] BuildGetBattery(byte transactionId) { return Build(transactionId, 0x07, 0x80, 0x02, null); }
        private static byte[] BuildGetCharging(byte transactionId) { return Build(transactionId, 0x07, 0x84, 0x02, null); }

        private static byte[] BuildSetDpi(byte transactionId, int x, int y)
        {
            return Build(transactionId, 0x04, 0x05, 0x07, new byte[]
            {
                0x01,
                (byte)(x >> 8), (byte)x,
                (byte)(y >> 8), (byte)y,
                0x00, 0x00
            });
        }

        private static byte[] BuildSetPollingRate(byte transactionId, int hertz)
        {
            byte code = hertz == 1000 ? (byte)0x01 : hertz == 500 ? (byte)0x02 : (byte)0x08;
            return Build(transactionId, 0x00, 0x05, 0x01, new byte[] { code });
        }

        private static byte[] Build(byte transactionId, byte commandClass, byte commandId, byte dataSize, byte[] arguments)
        {
            if (dataSize > 80 || (arguments != null && arguments.Length > dataSize))
                throw new ArgumentException("Arguments must fit inside the Razer report data size.", "arguments");
            byte[] report = new byte[90];
            report[1] = transactionId;
            report[5] = dataSize;
            report[6] = commandClass;
            report[7] = commandId;
            if (arguments != null) Array.Copy(arguments, 0, report, 8, arguments.Length);
            report[88] = CalculateChecksum(report);
            return report;
        }

        private static byte CalculateChecksum(byte[] report)
        {
            if (report == null || report.Length != 90)
                throw new ArgumentException("Razer reports are exactly 90 bytes.", "report");
            byte checksum = 0;
            for (int index = 2; index < 88; index++) checksum ^= report[index];
            return checksum;
        }

        private static void ValidateResponse(byte[] request, byte[] response)
        {
            if (response == null || response.Length != 90 || response[0] != 0x02)
                throw new InvalidDataException(String.Format(
                    "Razer command failed with status 0x{0:X2}.",
                    response == null || response.Length == 0 ? 0 : response[0]));
            if (CalculateChecksum(response) != response[88])
                throw new InvalidDataException("Razer response checksum is invalid.");
            if (request[1] != response[1] || request[6] != response[6] || request[7] != response[7])
                throw new InvalidDataException("Razer response does not match the request.");
        }

        private sealed class HidEndpoint
        {
            public readonly string Path;
            public readonly ushort ProductId;
            public readonly string Name;

            public HidEndpoint(string path, ushort productId, string name)
            {
                Path = path;
                ProductId = productId;
                Name = name;
            }
        }

        private sealed class RazerTransport : IDisposable
        {
            private readonly SafeFileHandle handle;
            private byte transactionId;

            public RazerTransport(HidEndpoint endpoint)
            {
                handle = Open(endpoint.Path, GenericRead | GenericWrite);
                if (handle.IsInvalid)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open Razer HID control interface.");
            }

            public byte[] TryQuery(Func<byte, byte[]> command)
            {
                try { return Send(command); }
                catch { return null; }
            }

            public byte[] Send(Func<byte, byte[]> command)
            {
                byte[] request = command(NextTransactionId());
                for (int attempt = 0; attempt <= 10; attempt++)
                {
                    byte[] outgoing = new byte[91];
                    Array.Copy(request, 0, outgoing, 1, request.Length);
                    if (!HidD_SetFeature(handle, outgoing, outgoing.Length))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot write the Razer HID feature report.");
                    byte[] incoming = new byte[91];
                    if (!HidD_GetFeature(handle, incoming, incoming.Length))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot read the Razer HID feature report.");
                    byte[] response = new byte[90];
                    Array.Copy(incoming, 1, response, 0, response.Length);
                    if (response[0] == 0x01)
                    {
                        Thread.Sleep(16);
                        continue;
                    }
                    ValidateResponse(request, response);
                    return response;
                }
                throw new TimeoutException("Razer device remained busy after 10 retries.");
            }

            private byte NextTransactionId()
            {
                if (transactionId == 31) transactionId = 0;
                return transactionId++;
            }

            public void Dispose()
            {
                handle.Dispose();
            }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SP_DEVICE_INTERFACE_DATA
        {
            public int Size;
            public Guid InterfaceClassGuid;
            public int Flags;
            public UIntPtr Reserved;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HIDD_ATTRIBUTES
        {
            public int Size;
            public ushort VendorId;
            public ushort ProductId;
            public ushort VersionNumber;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct HIDP_CAPS
        {
            public ushort Usage;
            public ushort UsagePage;
            public ushort InputReportByteLength;
            public ushort OutputReportByteLength;
            public ushort FeatureReportByteLength;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
            public ushort[] Reserved;
            public ushort NumberLinkCollectionNodes;
            public ushort NumberInputButtonCaps;
            public ushort NumberInputValueCaps;
            public ushort NumberInputDataIndices;
            public ushort NumberOutputButtonCaps;
            public ushort NumberOutputValueCaps;
            public ushort NumberOutputDataIndices;
            public ushort NumberFeatureButtonCaps;
            public ushort NumberFeatureValueCaps;
            public ushort NumberFeatureDataIndices;
        }

        [DllImport("hid.dll")]
        private static extern void HidD_GetHidGuid(out Guid guid);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_GetAttributes(SafeFileHandle handle, ref HIDD_ATTRIBUTES attributes);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_GetProductString(SafeFileHandle handle, byte[] buffer, int length);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_GetPreparsedData(SafeFileHandle handle, out IntPtr data);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_FreePreparsedData(IntPtr data);

        [DllImport("hid.dll")]
        private static extern int HidP_GetCaps(IntPtr data, out HIDP_CAPS caps);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_SetFeature(SafeFileHandle handle, byte[] data, int length);

        [DllImport("hid.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool HidD_GetFeature(SafeFileHandle handle, byte[] data, int length);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SetupDiGetClassDevs(
            ref Guid guid,
            string enumerator,
            IntPtr parent,
            uint flags);

        [DllImport("setupapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiEnumDeviceInterfaces(
            IntPtr set,
            IntPtr device,
            ref Guid guid,
            uint index,
            ref SP_DEVICE_INTERFACE_DATA data);

        [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiGetDeviceInterfaceDetail(
            IntPtr set,
            ref SP_DEVICE_INTERFACE_DATA data,
            IntPtr detail,
            uint detailSize,
            out uint required,
            IntPtr deviceInfo);

        [DllImport("setupapi.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string name,
            uint access,
            uint share,
            IntPtr security,
            uint creation,
            uint flags,
            IntPtr template);
    }
}
