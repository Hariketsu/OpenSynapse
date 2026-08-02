// SPDX-License-Identifier: GPL-2.0-only
// Migrated from the PowerPilot 2.0.0 prototype.

using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace PowerPilotNative
{
    public sealed class DisplayScaleInfo
    {
        public uint AdapterLowPart { get; internal set; }
        public int AdapterHighPart { get; internal set; }
        public uint SourceId { get; internal set; }
        public uint OutputTechnology { get; internal set; }
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
        public int Width { get; internal set; }
        public int Height { get; internal set; }
        public int Frequency { get; internal set; }
        public bool IsPrimary { get; internal set; }
    }

    public static class DisplayModeManager
    {
        private const int ENUM_CURRENT_SETTINGS = -1;
        private const int DISP_CHANGE_SUCCESSFUL = 0;
        private const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x1;
        private const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x4;

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
                info.Width = current.dmPelsWidth;
                info.Height = current.dmPelsHeight;
                info.Frequency = current.dmDisplayFrequency;
                info.IsPrimary = (device.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0;
                result.Add(info);
            }
            return result.ToArray();
        }

        private static int ApplyFrequency(DISPLAY_DEVICE device, bool maximum, int quietTarget, bool requireExact = false)
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
                    if (Math.Abs(candidate.dmDisplayFrequency - quietTarget) <= 1)
                    {
                        selected = candidate;
                        foundExact = true;
                        break;
                    }
                }
                if (!foundExact)
                    throw new InvalidOperationException(device.DeviceName + " does not expose " + quietTarget + " Hz at the current resolution and color depth.");
            }
            else
            {
                bool foundAtOrBelow = false;
                foreach (DEVMODE candidate in candidates)
                {
                    if (candidate.dmDisplayFrequency <= quietTarget + 1)
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
                changed += ApplyFrequency(device, true, 60);
            return changed;
        }

        public static int ApplyMaximumRefresh(string[] deviceNames)
        {
            if (deviceNames is null || deviceNames.Length == 0) return 0;
            var selected = new HashSet<string>(deviceNames, StringComparer.OrdinalIgnoreCase);
            var changed = 0;
            foreach (var device in GetActiveDevices())
                if (selected.Contains(device.DeviceName))
                    changed += ApplyFrequency(device, true, 60);
            return changed;
        }

        public static int ApplyFixedRefresh(int targetHz)
        {
            return ApplyFixedRefresh(targetHz, null);
        }

        public static int ApplyFixedRefresh(int targetHz, string[]? deviceNames)
        {
            var devices = GetActiveDevices();
            if (deviceNames is not null)
            {
                var selected = new HashSet<string>(deviceNames, StringComparer.OrdinalIgnoreCase);
                devices = devices.FindAll(device => selected.Contains(device.DeviceName));
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

        public static void RestoreRegistryModes()
        {
            foreach (DISPLAY_DEVICE device in GetActiveDevices())
            {
                int change = ChangeDisplaySettingsExReset(device.DeviceName, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
                if (change != DISP_CHANGE_SUCCESSFUL)
                    throw new Win32Exception(change, "Cannot restore the registry display mode for " + device.DeviceName + ".");
            }
        }
    }

    public sealed class AdvancedColorInfo
    {
        public string Key { get; internal set; }
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

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] PATH_INFO[] pathArray,
            ref uint modes, [Out] MODE_INFO[] modeArray, IntPtr topology);
        [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
        private static extern int GetColorInfo(ref COLOR_GET packet);
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
                if (String.Equals(Key(path.targetInfo), key, StringComparison.Ordinal))
                    return Set(path.targetInfo, enabled);
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
}
