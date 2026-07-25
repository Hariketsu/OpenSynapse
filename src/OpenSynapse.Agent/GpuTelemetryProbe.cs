using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

/// <summary>
/// Read-only Windows GPU telemetry. The Performance Counter API is sampled on a
/// background thread so Smart Auto and the UI only consume a cached snapshot.
/// </summary>
internal sealed class GpuTelemetryProbe : IDisposable
{
    private readonly object gate = new();
    private readonly Dictionary<string, PerformanceCounter> engineCounters = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, long> memoryBytes = new(StringComparer.OrdinalIgnoreCase);
    private readonly CancellationTokenSource stop = new();
    private readonly Task worker;
    private Dictionary<string, AdapterInfo> adapters = new(StringComparer.OrdinalIgnoreCase);
    private DateTimeOffset lastCounterRefresh = DateTimeOffset.MinValue;
    private DateTimeOffset lastMemoryRefresh = DateTimeOffset.MinValue;
    private TelemetrySample latest = TelemetrySample.Unavailable("GPU telemetry is starting.");

    private static readonly Regex EngineInstancePattern = new(
        @"pid_(?<pid>\d+)_luid_0x(?<high>[0-9a-f]+)_0x(?<low>[0-9a-f]+)_phys_\d+_eng_\d+_engtype_(?<type>.+)$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex MemoryInstancePattern = new(
        @"pid_(?<pid>\d+)_luid_0x(?<high>[0-9a-f]+)_0x(?<low>[0-9a-f]+)_phys_\d+$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public GpuTelemetryProbe()
    {
        latest = SampleCore();
        worker = Task.Run(SampleLoopAsync);
    }

    public TelemetrySample ReadLatest()
    {
        lock (gate) return latest;
    }

    public void Dispose()
    {
        stop.Cancel();
        try { worker.Wait(TimeSpan.FromSeconds(2)); }
        catch (AggregateException) { }
        lock (gate)
        {
            foreach (var counter in engineCounters.Values) counter.Dispose();
            engineCounters.Clear();
        }
        stop.Dispose();
    }

    private async Task SampleLoopAsync()
    {
        while (!stop.IsCancellationRequested)
        {
            TelemetrySample sample;
            try { sample = SampleCore(); }
            catch (Exception ex) { sample = TelemetrySample.Unavailable(ex.Message); }
            lock (gate) latest = sample;
            try { await Task.Delay(TimeSpan.FromSeconds(5), stop.Token); }
            catch (OperationCanceledException) { }
        }
    }

    private TelemetrySample SampleCore()
    {
        lock (gate)
        {
            try
            {
                if (DateTimeOffset.UtcNow - lastCounterRefresh >= TimeSpan.FromSeconds(15))
                {
                    adapters = ReadAdapters();
                    RefreshEngineCounters();
                    lastCounterRefresh = DateTimeOffset.UtcNow;
                }

                var consumers = new Dictionary<string, ConsumerBuilder>(StringComparer.OrdinalIgnoreCase);
                var total = 0d;
                var discrete = 0d;
                foreach (var entry in engineCounters)
                {
                    var match = EngineInstancePattern.Match(entry.Key);
                    if (!match.Success || !IsSupportedEngine(match.Groups["type"].Value)) continue;
                    double value;
                    try { value = Math.Max(0, entry.Value.NextValue()); }
                    catch { continue; }
                    if (!TryParseInstance(match, out var pid, out var luid)) continue;

                    if (!adapters.TryGetValue(luid, out var adapter))
                        adapter = new AdapterInfo("Unknown adapter", false);
                    var key = $"{pid}:{luid}";
                    if (!consumers.TryGetValue(key, out var consumer))
                    {
                        consumer = new ConsumerBuilder(
                            pid,
                            ReadProcessName(pid),
                            adapter.Name,
                            adapter.Discrete);
                        consumers[key] = consumer;
                    }
                    consumer.UtilizationPercent += value;
                    total += value;
                    if (adapter.Discrete) discrete += value;
                }

                RefreshMemoryCounters();
                var discreteDedicatedBytes = 0L;
                foreach (var entry in memoryBytes)
                {
                    var match = MemoryInstancePattern.Match(entry.Key);
                    if (!match.Success || !TryParseInstance(match, out var pid, out var luid)) continue;
                    if (!adapters.TryGetValue(luid, out var adapter) || !adapter.Discrete) continue;
                    var key = $"{pid}:{luid}";
                    if (!consumers.TryGetValue(key, out var consumer))
                    {
                        consumer = new ConsumerBuilder(pid, ReadProcessName(pid), adapter.Name, true);
                        consumers[key] = consumer;
                    }
                    consumer.DedicatedBytes = Math.Max(0, entry.Value);
                    discreteDedicatedBytes += consumer.DedicatedBytes;
                }

                var snapshots = consumers.Values
                    .OrderByDescending(item => item.UtilizationPercent)
                    .ThenByDescending(item => item.DedicatedBytes)
                    .Take(16)
                    .Select(item => new GpuConsumerSnapshot(
                        item.ProcessId,
                        item.ProcessName,
                        item.AdapterName,
                        Math.Round(Math.Max(0, item.UtilizationPercent), 1),
                        item.DedicatedBytes,
                        item.Discrete))
                    .ToArray();
                return new TelemetrySample(
                    adapters.Count > 0,
                    Math.Round(Math.Min(100, total), 1),
                    Math.Round(Math.Min(100, discrete), 1),
                    discreteDedicatedBytes,
                    snapshots,
                    string.Empty);
            }
            catch (Exception ex)
            {
                return TelemetrySample.Unavailable(ex.Message);
            }
        }
    }

    private void RefreshEngineCounters()
    {
        var category = new PerformanceCounterCategory("GPU Engine");
        var current = category.GetInstanceNames()
            .Where(name => EngineInstancePattern.IsMatch(name)
                && IsSupportedEngine(EngineInstancePattern.Match(name).Groups["type"].Value))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var removed in engineCounters.Keys.Where(name => !current.Contains(name)).ToArray())
        {
            engineCounters[removed].Dispose();
            engineCounters.Remove(removed);
        }

        foreach (var name in current)
        {
            if (engineCounters.ContainsKey(name)) continue;
            var counter = new PerformanceCounter("GPU Engine", "Utilization Percentage", name, true);
            try
            {
                _ = counter.NextValue();
                engineCounters[name] = counter;
            }
            catch { counter.Dispose(); }
        }
    }

    private void RefreshMemoryCounters()
    {
        if (DateTimeOffset.UtcNow - lastMemoryRefresh < TimeSpan.FromSeconds(30)) return;
        try
        {
            memoryBytes.Clear();
            var category = new PerformanceCounterCategory("GPU Process Memory");
            foreach (var instance in category.GetInstanceNames())
            {
                var match = MemoryInstancePattern.Match(instance);
                if (!match.Success || !TryParseInstance(match, out _, out var luid)) continue;
                if (!adapters.TryGetValue(luid, out var adapter) || !adapter.Discrete) continue;
                using var counter = new PerformanceCounter("GPU Process Memory", "Dedicated Usage", instance, true);
                try { memoryBytes[instance] = Math.Max(0, counter.RawValue); }
                catch { }
            }
        }
        catch { }
        finally { lastMemoryRefresh = DateTimeOffset.UtcNow; }
    }

    private static bool IsSupportedEngine(string type) =>
        type.Equals("3D", StringComparison.OrdinalIgnoreCase)
        || type.Equals("Compute", StringComparison.OrdinalIgnoreCase)
        || type.Equals("Cuda", StringComparison.OrdinalIgnoreCase)
        || type.Equals("VideoEncode", StringComparison.OrdinalIgnoreCase)
        || type.Equals("VideoDecode", StringComparison.OrdinalIgnoreCase)
        || type.Equals("Copy", StringComparison.OrdinalIgnoreCase);

    private static string ReadProcessName(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            return process.ProcessName;
        }
        catch { return $"pid {processId}"; }
    }

    private static bool TryParseInstance(Match match, out int processId, out string luid)
    {
        processId = 0;
        luid = string.Empty;
        if (!int.TryParse(match.Groups["pid"].Value, out processId)
            || !uint.TryParse(match.Groups["high"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var high)
            || !uint.TryParse(match.Groups["low"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var low))
            return false;
        luid = $"{high:x8}:{low:x8}";
        return true;
    }

    private static Dictionary<string, AdapterInfo> ReadAdapters()
    {
        var result = new Dictionary<string, AdapterInfo>(StringComparer.OrdinalIgnoreCase);
        var interfaceId = typeof(IDXGIFactory1).GUID;
        if (CreateDXGIFactory1(ref interfaceId, out var factory) < 0 || factory is null) return result;
        try
        {
            for (uint index = 0; ; index++)
            {
                if (factory.EnumAdapters1(index, out var adapter) != 0 || adapter is null) break;
                try
                {
                    if (adapter.GetDesc1(out var description) == 0)
                    {
                        var software = (description.Flags & 2) != 0;
                        var discrete = !software && description.DedicatedVideoMemory.ToUInt64() >= 1024UL * 1024UL * 1024UL;
                        result[$"{unchecked((uint)description.AdapterLuid.HighPart):x8}:{description.AdapterLuid.LowPart:x8}"] =
                            new AdapterInfo(description.Description?.TrimEnd('\0') ?? string.Empty, discrete);
                    }
                }
                finally { Marshal.FinalReleaseComObject(adapter); }
            }
        }
        finally { Marshal.FinalReleaseComObject(factory); }
        return result;
    }

    private sealed record AdapterInfo(string Name, bool Discrete);

    private sealed class ConsumerBuilder(int processId, string processName, string adapterName, bool discrete)
    {
        public int ProcessId { get; } = processId;
        public string ProcessName { get; } = processName;
        public string AdapterName { get; } = adapterName;
        public bool Discrete { get; } = discrete;
        public double UtilizationPercent { get; set; }
        public long DedicatedBytes { get; set; }
    }

    internal sealed record TelemetrySample(
        bool Available,
        double TotalUtilizationPercent,
        double DiscreteUtilizationPercent,
        long DiscreteDedicatedBytes,
        IReadOnlyList<GpuConsumerSnapshot> Consumers,
        string Error)
    {
        public static TelemetrySample Unavailable(string error) =>
            new(false, -1, -1, -1, [], error);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DxgiAdapterDescription
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint VendorId;
        public uint DeviceId;
        public uint SubSysId;
        public uint Revision;
        public UIntPtr DedicatedVideoMemory;
        public UIntPtr DedicatedSystemMemory;
        public UIntPtr SharedSystemMemory;
        public Luid AdapterLuid;
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
        [PreserveSig] int GetDesc1(out DxgiAdapterDescription description);
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

    [DllImport("dxgi.dll", PreserveSig = true)]
    private static extern int CreateDXGIFactory1(
        ref Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out IDXGIFactory1 factory);
}
