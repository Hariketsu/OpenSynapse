using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
using OpenSynapse.Core;

namespace OpenSynapse.Agent;

internal sealed class DeathAdderHid
{
    private const ushort ControlUsagePage = 0x000C;

    public IReadOnlyList<RazerDevice> ReadDevices()
    {
        var devices = new List<RazerDevice>();
        foreach (var hid in Enumerate().GroupBy(item => item.ProductId).Select(group => group.First()))
        {
            try { devices.Add(ReadSnapshot(hid)); }
            catch { devices.Add(ToDevice(hid)); }
        }
        return devices;
    }

    public void SetDpi(int x, int y, int? productId = null) => WithDevice(
        productId,
        transport => transport.Send(tx => DeathAdderProtocol.SetDpi(tx, x, y)));

    public void SetPollingRate(int hz, int? productId = null) => WithDevice(
        productId,
        transport => transport.Send(tx => DeathAdderProtocol.SetPollingRate(tx, hz)));

    private static RazerDevice ReadSnapshot(HidEndpoint endpoint)
    {
        using var transport = new RazerTransport(endpoint);
        var firmware = transport.TryQuery(DeathAdderProtocol.GetFirmware);
        var serial = transport.TryQuery(DeathAdderProtocol.GetSerial);
        var polling = transport.TryQuery(DeathAdderProtocol.GetPollingRate);
        var dpi = transport.TryQuery(DeathAdderProtocol.GetDpi);
        var battery = transport.TryQuery(DeathAdderProtocol.GetBattery);
        var charging = transport.TryQuery(DeathAdderProtocol.GetCharging);
        return new RazerDevice(
            DeathAdderProtocol.VendorId,
            endpoint.ProductId,
            endpoint.Name,
            endpoint.ProductId is 0x00B7 or 0x00C3 ? "Wireless" : "Wired",
            firmware is null ? null : $"v{firmware[8]}.{firmware[9]}",
            serial is null ? null : Encoding.ASCII.GetString(serial, 8, 22).TrimEnd('\0', ' '),
            dpi is null ? null : (dpi[9] << 8) | dpi[10],
            dpi is null ? null : (dpi[11] << 8) | dpi[12],
            polling is null ? null : DecodePolling(polling[8]),
            battery is null ? null : (int)Math.Round(battery[9] * 100d / 255d),
            charging is null ? null : charging[9] != 0);
    }

    private void WithDevice(int? productId, Action<RazerTransport> action)
    {
        var endpoint = Enumerate()
            .Where(item => productId is null || item.ProductId == productId)
            .OrderByDescending(item => item.ProductId is 0x00B7 or 0x00C3)
            .FirstOrDefault()
            ?? throw new InvalidOperationException("No supported DeathAdder V3 Pro control interface is connected.");
        using var transport = new RazerTransport(endpoint);
        action(transport);
    }

    private static int DecodePolling(byte code) => code switch
    {
        0x01 => 1000,
        0x02 => 500,
        0x08 => 125,
        _ => 0
    };

    private static RazerDevice ToDevice(HidEndpoint endpoint) => new(
        DeathAdderProtocol.VendorId,
        endpoint.ProductId,
        endpoint.Name,
        endpoint.ProductId is 0x00B7 or 0x00C3 ? "Wireless" : "Wired");

    private static IReadOnlyList<HidEndpoint> Enumerate()
    {
        HidD_GetHidGuid(out var hidGuid);
        var set = SetupDiGetClassDevs(ref hidGuid, null, IntPtr.Zero, 0x12);
        if (set == new IntPtr(-1)) throw new Win32Exception();
        var result = new List<HidEndpoint>();
        try
        {
            var item = new SP_DEVICE_INTERFACE_DATA { Size = Marshal.SizeOf<SP_DEVICE_INTERFACE_DATA>() };
            for (uint index = 0; SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hidGuid, index, ref item); index++)
            {
                SetupDiGetDeviceInterfaceDetail(set, ref item, IntPtr.Zero, 0, out var required, IntPtr.Zero);
                var detail = Marshal.AllocHGlobal((int)required);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!SetupDiGetDeviceInterfaceDetail(set, ref item, detail, required, out _, IntPtr.Zero)) continue;
                    var path = Marshal.PtrToStringUni(detail + 4);
                    if (path is null) continue;
                    using var handle = Open(path, 0);
                    if (handle.IsInvalid) continue;
                    var attributes = new HIDD_ATTRIBUTES { Size = Marshal.SizeOf<HIDD_ATTRIBUTES>() };
                    if (!HidD_GetAttributes(handle, ref attributes)
                        || attributes.VendorId != DeathAdderProtocol.VendorId
                        || !DeathAdderProtocol.SupportedProducts.ContainsKey(attributes.ProductId)
                        || GetUsagePage(handle) != ControlUsagePage)
                        continue;
                    var name = GetProductName(handle) ?? DeathAdderProtocol.SupportedProducts[attributes.ProductId];
                    result.Add(new HidEndpoint(path, attributes.ProductId, name));
                }
                finally { Marshal.FreeHGlobal(detail); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return result;
    }

    private static ushort GetUsagePage(SafeFileHandle handle)
    {
        if (!HidD_GetPreparsedData(handle, out var data)) return 0;
        try
        {
            return HidP_GetCaps(data, out var caps) >= 0 ? caps.UsagePage : (ushort)0;
        }
        finally { HidD_FreePreparsedData(data); }
    }

    private static string? GetProductName(SafeFileHandle handle)
    {
        var buffer = new byte[256];
        return HidD_GetProductString(handle, buffer, buffer.Length)
            ? Encoding.Unicode.GetString(buffer).TrimEnd('\0')
            : null;
    }

    private static SafeFileHandle Open(string path, uint access) => CreateFile(
        path,
        access,
        0x00000001 | 0x00000002,
        IntPtr.Zero,
        3,
        0,
        IntPtr.Zero);

    private sealed record HidEndpoint(string Path, int ProductId, string Name);

    private sealed class RazerTransport : IDisposable
    {
        private readonly SafeFileHandle handle;
        private byte transactionId;

        public RazerTransport(HidEndpoint endpoint)
        {
            handle = Open(endpoint.Path, 0x80000000 | 0x40000000);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open Razer HID control interface.");
        }

        public byte[]? TryQuery(Func<byte, byte[]> command)
        {
            try { return Send(command); }
            catch { return null; }
        }

        public byte[] Send(Func<byte, byte[]> command)
        {
            var request = command(NextTransactionId());
            for (var attempt = 0; attempt <= 10; attempt++)
            {
                var outgoing = new byte[91];
                request.CopyTo(outgoing, 1);
                if (!HidD_SetFeature(handle, outgoing, outgoing.Length)) throw new Win32Exception(Marshal.GetLastWin32Error());
                var incoming = new byte[91];
                if (!HidD_GetFeature(handle, incoming, incoming.Length)) throw new Win32Exception(Marshal.GetLastWin32Error());
                var response = incoming.AsSpan(1, 90).ToArray();
                if (response[0] == 0x01)
                {
                    Thread.Sleep(16);
                    continue;
                }
                DeathAdderProtocol.ValidateResponse(request, response);
                return response;
            }
            throw new TimeoutException("Razer device remained busy after 10 retries.");
        }

        private byte NextTransactionId()
        {
            if (transactionId == 31) transactionId = 0;
            return transactionId++;
        }

        public void Dispose() => handle.Dispose();
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
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
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

    [DllImport("hid.dll")] private static extern void HidD_GetHidGuid(out Guid guid);
    [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_GetAttributes(SafeFileHandle handle, ref HIDD_ATTRIBUTES attributes);
    [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_GetProductString(SafeFileHandle handle, byte[] buffer, int length);
    [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_GetPreparsedData(SafeFileHandle handle, out IntPtr data);
    [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")] private static extern int HidP_GetCaps(IntPtr data, out HIDP_CAPS caps);
    [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_SetFeature(SafeFileHandle handle, byte[] data, int length);
    [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_GetFeature(SafeFileHandle handle, byte[] data, int length);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr SetupDiGetClassDevs(ref Guid guid, string? enumerator, IntPtr parent, uint flags);
    [DllImport("setupapi.dll", SetLastError = true)] private static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr device, ref Guid guid, uint index, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, uint detailSize, out uint required, IntPtr deviceInfo);
    [DllImport("setupapi.dll")] private static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
}
