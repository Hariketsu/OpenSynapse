#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param([string]$ResultPath = '')

$ErrorActionPreference = 'Stop'

trap {
    $failure = [pscustomobject]@{
        Result = 'FAIL'
        Message = $_.Exception.Message
        CompletedAt = (Get-Date).ToString('o')
    }
    if ($ResultPath) {
        [IO.File]::WriteAllText(
            [IO.Path]::GetFullPath($ResultPath),
            ($failure | ConvertTo-Json -Depth 5),
            [Text.UTF8Encoding]::new($false))
    }
    Write-Error $_
    break
}

$nativeSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace OpenSynapseDrrValidation
{
    public sealed class Result
    {
        public string FriendlyName { get; set; }
        public double CurrentVirtualHz { get; set; }
        public uint OriginalFlags { get; set; }
        public bool SupportsVirtualMode { get; set; }
        public bool DynamicBoostEnabled { get; set; }
        public int ValidationCode { get; set; }
        public bool ValidationSucceeded { get; set; }
    }

    public static class Native
    {
        private const uint QDC_ONLY_ACTIVE_PATHS = 0x2;
        private const uint QDC_VIRTUAL_MODE_AWARE = 0x10;
        private const uint QDC_VIRTUAL_REFRESH_RATE_AWARE = 0x40;
        private const uint PATH_SUPPORT_VIRTUAL_MODE = 0x8;
        private const uint PATH_BOOST_REFRESH_RATE = 0x10;
        private const uint OUTPUT_INTERNAL = 0x80000000;
        private const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x20;
        private const uint SDC_VALIDATE = 0x40;
        private const uint SDC_ALLOW_CHANGES = 0x400;
        private const uint SDC_VIRTUAL_MODE_AWARE = 0x8000;
        private const uint SDC_VIRTUAL_REFRESH_RATE_AWARE = 0x20000;
        private const int GET_TARGET_NAME = 2;

        [StructLayout(LayoutKind.Sequential)] private struct Luid { public uint LowPart; public int HighPart; }
        [StructLayout(LayoutKind.Sequential)] private struct Rational { public uint Numerator; public uint Denominator; }
        [StructLayout(LayoutKind.Sequential)] private struct PathSource { public Luid AdapterId; public uint Id; public uint ModeInfoIdx; public uint StatusFlags; }
        [StructLayout(LayoutKind.Sequential)] private struct PathTarget
        {
            public Luid AdapterId;
            public uint Id;
            public uint ModeInfoIdx;
            public uint OutputTechnology;
            public uint Rotation;
            public uint Scaling;
            public Rational RefreshRate;
            public uint ScanLineOrdering;
            [MarshalAs(UnmanagedType.Bool)] public bool TargetAvailable;
            public uint StatusFlags;
        }
        [StructLayout(LayoutKind.Sequential)] private struct PathInfo { public PathSource SourceInfo; public PathTarget TargetInfo; public uint Flags; }
        [StructLayout(LayoutKind.Sequential)] private struct PointL { public int X; public int Y; }
        [StructLayout(LayoutKind.Sequential)] private struct RectL { public int Left; public int Top; public int Right; public int Bottom; }
        [StructLayout(LayoutKind.Sequential)] private struct Region { public uint Width; public uint Height; }
        [StructLayout(LayoutKind.Sequential)] private struct Signal
        {
            public ulong PixelRate;
            public Rational HSyncFrequency;
            public Rational VSyncFrequency;
            public Region ActiveSize;
            public Region TotalSize;
            public uint VideoStandard;
            public uint ScanLineOrdering;
        }
        [StructLayout(LayoutKind.Sequential)] private struct TargetMode { public Signal Signal; }
        [StructLayout(LayoutKind.Sequential)] private struct SourceMode { public uint Width; public uint Height; public uint PixelFormat; public PointL Position; }
        [StructLayout(LayoutKind.Sequential)] private struct DesktopImage { public PointL Size; public RectL Region; public RectL Clip; }
        [StructLayout(LayoutKind.Explicit)] private struct ModeUnion
        {
            [FieldOffset(0)] public TargetMode Target;
            [FieldOffset(0)] public SourceMode Source;
            [FieldOffset(0)] public DesktopImage Image;
        }
        [StructLayout(LayoutKind.Sequential)] private struct ModeInfo { public uint Type; public uint Id; public Luid AdapterId; public ModeUnion Data; }
        [StructLayout(LayoutKind.Sequential)] private struct Header { public int Type; public uint Size; public Luid AdapterId; public uint Id; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct TargetName
        {
            public Header Header;
            public uint Flags;
            public uint OutputTechnology;
            public ushort EdidManufactureId;
            public ushort EdidProductCodeId;
            public uint ConnectorInstance;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string MonitorFriendlyDeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string MonitorDevicePath;
        }

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PathInfo[] pathArray,
            ref uint modeCount, [Out] ModeInfo[] modeArray, IntPtr topology);
        [DllImport("user32.dll")]
        private static extern int SetDisplayConfig(uint pathCount, [In] PathInfo[] pathArray,
            uint modeCount, [In] ModeInfo[] modeArray, uint flags);
        [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
        private static extern int GetTargetName(ref TargetName packet);

        public static Result ValidateInternal60Boost()
        {
            uint queryFlags = QDC_ONLY_ACTIVE_PATHS | QDC_VIRTUAL_MODE_AWARE | QDC_VIRTUAL_REFRESH_RATE_AWARE;
            uint pathCount;
            uint modeCount;
            int error = GetDisplayConfigBufferSizes(queryFlags, out pathCount, out modeCount);
            if (error != 0) throw new Win32Exception(error, "Cannot size the active display configuration.");

            PathInfo[] paths = new PathInfo[pathCount];
            ModeInfo[] modes = new ModeInfo[modeCount];
            error = QueryDisplayConfig(queryFlags, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
            if (error != 0) throw new Win32Exception(error, "Cannot query the active display configuration.");

            int internalIndex = -1;
            for (int index = 0; index < pathCount; index++)
            {
                if (paths[index].TargetInfo.OutputTechnology == OUTPUT_INTERNAL)
                {
                    internalIndex = index;
                    break;
                }
            }
            if (internalIndex < 0) throw new InvalidOperationException("No active internal display path was found.");

            TargetName name = new TargetName();
            name.Header.Type = GET_TARGET_NAME;
            name.Header.Size = (uint)Marshal.SizeOf(typeof(TargetName));
            name.Header.AdapterId = paths[internalIndex].TargetInfo.AdapterId;
            name.Header.Id = paths[internalIndex].TargetInfo.Id;
            GetTargetName(ref name);

            uint originalFlags = paths[internalIndex].Flags;
            Rational originalRefresh = paths[internalIndex].TargetInfo.RefreshRate;
            double currentHz = originalRefresh.Denominator == 0
                ? 0
                : (double)originalRefresh.Numerator / originalRefresh.Denominator;

            paths[internalIndex].TargetInfo.RefreshRate.Numerator = 60;
            paths[internalIndex].TargetInfo.RefreshRate.Denominator = 1;
            paths[internalIndex].Flags |= PATH_BOOST_REFRESH_RATE;

            uint validationFlags = SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_VALIDATE | SDC_ALLOW_CHANGES |
                SDC_VIRTUAL_MODE_AWARE | SDC_VIRTUAL_REFRESH_RATE_AWARE;
            int validationCode = SetDisplayConfig(pathCount, paths, modeCount, modes, validationFlags);

            return new Result
            {
                FriendlyName = name.MonitorFriendlyDeviceName,
                CurrentVirtualHz = currentHz,
                OriginalFlags = originalFlags,
                SupportsVirtualMode = (originalFlags & PATH_SUPPORT_VIRTUAL_MODE) != 0,
                DynamicBoostEnabled = (originalFlags & PATH_BOOST_REFRESH_RATE) != 0,
                ValidationCode = validationCode,
                ValidationSucceeded = validationCode == 0
            };
        }
    }
}
'@

Add-Type -TypeDefinition $nativeSource -Language CSharp
$validation = [OpenSynapseDrrValidation.Native]::ValidateInternal60Boost()
$result = [pscustomobject]@{
    Result = if ($validation.ValidationSucceeded) { 'PASS' } else { 'FAIL' }
    FriendlyName = $validation.FriendlyName
    CurrentVirtualHz = $validation.CurrentVirtualHz
    OriginalFlags = $validation.OriginalFlags
    SupportsVirtualMode = $validation.SupportsVirtualMode
    DynamicBoostEnabledBeforeTest = $validation.DynamicBoostEnabled
    ValidationCode = $validation.ValidationCode
    ValidationSucceeded = $validation.ValidationSucceeded
    ConfigurationApplied = $false
    CompletedAt = (Get-Date).ToString('o')
}

if ($ResultPath) {
    [IO.File]::WriteAllText(
        [IO.Path]::GetFullPath($ResultPath),
        ($result | ConvertTo-Json -Depth 5),
        [Text.UTF8Encoding]::new($false))
}
$result
if (-not $validation.ValidationSucceeded) {
    throw "Windows rejected native DRR validation with code $($validation.ValidationCode)."
}
