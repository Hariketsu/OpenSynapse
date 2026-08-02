using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.InteropServices;

namespace PowerPilotNative;

public sealed class DynamicRefreshInfo
{
    public bool InternalDisplayActive { get; internal set; }
    public bool Supported { get; internal set; }
    public bool Enabled { get; internal set; }
    public int BaseFrequency { get; internal set; }
    public int BoostFrequency { get; internal set; }
    public string Message { get; internal set; } = string.Empty;
}

public static class DynamicRefreshManager
{
    private const uint QueryActivePaths = 0x00000002;
    private const uint QueryVirtualModeAware = 0x00000010;
    private const uint QueryVirtualRefreshRateAware = 0x00000040;
    private const uint SetUseSuppliedDisplayConfig = 0x00000020;
    private const uint SetValidate = 0x00000040;
    private const uint SetApply = 0x00000080;
    private const uint SetSaveToDatabase = 0x00000200;
    private const uint SetAllowChanges = 0x00000400;
    private const uint SetVirtualModeAware = 0x00008000;
    private const uint SetVirtualRefreshRateAware = 0x00020000;
    private const uint SupportsVirtualMode = 0x00000008;
    private const uint BoostRefreshRate = 0x00000010;
    private const uint InternalOutput = 0x80000000;
    private const uint InvalidModeIndex = 0x0000ffff;
    private const uint GetSourceName = 1;
    private const int Success = 0;
    private const int InsufficientBuffer = 122;

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid { public uint Low; public int High; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rational { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathSource { public Luid Adapter; public uint Id; public uint ModeIndex; public uint StatusFlags; }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathTarget
    {
        public Luid Adapter;
        public uint Id;
        public uint ModeIndex;
        public uint OutputTechnology;
        public uint Rotation;
        public uint Scaling;
        public Rational RefreshRate;
        public uint ScanLineOrdering;
        [MarshalAs(UnmanagedType.Bool)] public bool TargetAvailable;
        public uint StatusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathInfo { public PathSource Source; public PathTarget Target; public uint Flags; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Region { public uint Width; public uint Height; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Signal
    {
        public ulong PixelRate;
        public Rational HorizontalSync;
        public Rational VerticalSync;
        public Region ActiveSize;
        public Region TotalSize;
        public uint VideoStandard;
        public uint ScanLineOrdering;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TargetMode { public Signal Signal; }

    [StructLayout(LayoutKind.Sequential)]
    private struct SourceMode { public uint Width; public uint Height; public uint PixelFormat; public Point Position; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DesktopImage { public Point Size; public Rect Region; public Rect Clip; }

    [StructLayout(LayoutKind.Explicit)]
    private struct ModeUnion
    {
        [FieldOffset(0)] public TargetMode Target;
        [FieldOffset(0)] public SourceMode Source;
        [FieldOffset(0)] public DesktopImage Image;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ModeInfo { public uint Type; public uint Id; public Luid Adapter; public ModeUnion Data; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceInfoHeader { public uint Type; public uint Size; public Luid Adapter; public uint Id; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SourceDeviceName
    {
        public DeviceInfoHeader Header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string ViewGdiDeviceName;
    }

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(
        uint flags,
        ref uint paths,
        [Out] PathInfo[] pathArray,
        ref uint modes,
        [Out] ModeInfo[] modeArray,
        IntPtr topologyId);

    [DllImport("user32.dll")]
    private static extern int SetDisplayConfig(
        uint paths,
        [In] PathInfo[] pathArray,
        uint modes,
        [In] ModeInfo[] modeArray,
        uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int DisplayConfigGetDeviceInfo(ref SourceDeviceName requestPacket);

    private static void Query(out PathInfo[] paths, out ModeInfo[] modes)
    {
        var flags = QueryActivePaths | QueryVirtualModeAware | QueryVirtualRefreshRateAware;
        for (var attempt = 0; attempt < 5; attempt++)
        {
            var result = GetDisplayConfigBufferSizes(flags, out var pathCount, out var modeCount);
            if (result != Success) throw new Win32Exception(result, "Cannot size display paths for dynamic refresh.");
            var pathBuffer = new PathInfo[pathCount];
            var modeBuffer = new ModeInfo[modeCount];
            result = QueryDisplayConfig(flags, ref pathCount, pathBuffer, ref modeCount, modeBuffer, IntPtr.Zero);
            if (result == InsufficientBuffer) continue;
            if (result != Success) throw new Win32Exception(result, "Cannot query display paths for dynamic refresh.");
            paths = pathBuffer[..(int)pathCount];
            modes = modeBuffer[..(int)modeCount];
            return;
        }
        throw new Win32Exception(InsufficientBuffer, "Display paths kept changing.");
    }

    private static bool IsInternal(PathInfo path) => path.Target.OutputTechnology == InternalOutput;

    private static string[] GetDisplayDeviceNames(bool internalDisplay)
    {
        Query(out var paths, out _);
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in paths)
        {
            if (IsInternal(path) != internalDisplay) continue;
            var packet = new SourceDeviceName
            {
                Header = new DeviceInfoHeader
                {
                    Type = GetSourceName,
                    Size = (uint)Marshal.SizeOf<SourceDeviceName>(),
                    Adapter = path.Source.Adapter,
                    Id = path.Source.Id
                },
                ViewGdiDeviceName = string.Empty
            };
            if (DisplayConfigGetDeviceInfo(ref packet) == Success && !string.IsNullOrWhiteSpace(packet.ViewGdiDeviceName))
                names.Add(packet.ViewGdiDeviceName);
        }
        return names.ToArray();
    }

    public static int ApplyExternalMaximumRefresh() =>
        DisplayModeManager.ApplyMaximumRefresh(GetDisplayDeviceNames(false));

    public static int ApplyProfileRefresh(int internalTargetHz) =>
        ApplyExternalMaximumRefresh()
        + DisplayModeManager.ApplyFixedRefresh(internalTargetHz, GetDisplayDeviceNames(true));

    private static int RationalHz(Rational value) => value.Denominator == 0
        ? 0
        : (int)Math.Round((double)value.Numerator / value.Denominator);

    private static int TargetModeHz(PathInfo path, ModeInfo[] modes)
    {
        var index = (path.Flags & SupportsVirtualMode) != 0
            ? (path.Target.ModeIndex >> 16) & 0xffffu
            : path.Target.ModeIndex;
        return index == InvalidModeIndex || index >= modes.Length || modes[index].Type != 2
            ? 0
            : RationalHz(modes[index].Data.Target.Signal.VerticalSync);
    }

    public static DynamicRefreshInfo GetStatus()
    {
        Query(out var paths, out var modes);
        var info = new DynamicRefreshInfo { Message = "No active internal display path." };
        foreach (var path in paths)
        {
            if (!IsInternal(path)) continue;
            info.InternalDisplayActive = true;
            info.Supported = (path.Flags & SupportsVirtualMode) != 0;
            info.Enabled = (path.Flags & BoostRefreshRate) != 0;
            info.BaseFrequency = RationalHz(path.Target.RefreshRate);
            info.BoostFrequency = TargetModeHz(path, modes);
            info.Message = info.Supported
                ? "Windows dynamic refresh is available."
                : "The active internal path does not advertise virtual refresh support.";
            return info;
        }
        return info;
    }

    public static bool ValidateNativeDynamic()
    {
        Query(out var paths, out var modes);
        var found = false;
        for (var index = 0; index < paths.Length; index++)
        {
            if (!IsInternal(paths[index])) continue;
            if ((paths[index].Flags & SupportsVirtualMode) == 0) return false;
            var path = paths[index];
            path.Flags |= BoostRefreshRate;
            path.Target.RefreshRate = new Rational { Numerator = 60, Denominator = 1 };
            paths[index] = path;
            found = true;
        }
        if (!found) return false;
        var flags = SetValidate | SetUseSuppliedDisplayConfig | SetAllowChanges
            | SetVirtualModeAware | SetVirtualRefreshRateAware;
        return SetDisplayConfig((uint)paths.Length, paths, (uint)modes.Length, modes, flags) == Success;
    }

    public static int EnableNativeDynamic()
    {
        var before = GetStatus();
        if (!before.InternalDisplayActive)
            throw new InvalidOperationException("The internal display is not active; dynamic refresh was not applied.");
        if (!before.Supported)
            throw new InvalidOperationException("The internal display path does not support Windows dynamic refresh.");

        var changed = ApplyExternalMaximumRefresh();
        if (before.Enabled && Math.Abs(before.BaseFrequency - 60) <= 1 && before.BoostFrequency > 60)
            return changed;
        changed += DisplayModeManager.ApplyMaximumRefresh(GetDisplayDeviceNames(true));
        Query(out var paths, out var modes);
        for (var index = 0; index < paths.Length; index++)
        {
            if (!IsInternal(paths[index])) continue;
            var path = paths[index];
            path.Flags |= BoostRefreshRate;
            path.Target.RefreshRate = new Rational { Numerator = 60, Denominator = 1 };
            paths[index] = path;
        }
        var flags = SetApply | SetUseSuppliedDisplayConfig | SetAllowChanges | SetSaveToDatabase
            | SetVirtualModeAware | SetVirtualRefreshRateAware;
        var result = SetDisplayConfig((uint)paths.Length, paths, (uint)modes.Length, modes, flags);
        if (result != Success) throw new Win32Exception(result, "Cannot enable Windows dynamic refresh.");

        var after = GetStatus();
        if (!after.Enabled || Math.Abs(after.BaseFrequency - 60) > 1 || after.BoostFrequency <= 60)
        {
            try { Disable(); } catch { }
            try { DisplayModeManager.ApplyMaximumRefresh(GetDisplayDeviceNames(true)); } catch { }
            throw new InvalidOperationException("Windows accepted the request but did not report a valid native dynamic refresh range.");
        }
        return changed + 1;
    }

    public static int Disable()
    {
        Query(out var paths, out var modes);
        var changed = false;
        for (var index = 0; index < paths.Length; index++)
        {
            if (!IsInternal(paths[index]) || (paths[index].Flags & BoostRefreshRate) == 0) continue;
            var path = paths[index];
            path.Flags &= ~BoostRefreshRate;
            var physicalHz = TargetModeHz(path, modes);
            if (physicalHz > 0) path.Target.RefreshRate = new Rational { Numerator = (uint)physicalHz, Denominator = 1 };
            paths[index] = path;
            changed = true;
        }
        if (!changed) return 0;
        var flags = SetApply | SetUseSuppliedDisplayConfig | SetAllowChanges | SetSaveToDatabase
            | SetVirtualModeAware | SetVirtualRefreshRateAware;
        var result = SetDisplayConfig((uint)paths.Length, paths, (uint)modes.Length, modes, flags);
        if (result != Success) throw new Win32Exception(result, "Cannot disable Windows dynamic refresh.");
        return 1;
    }
}
