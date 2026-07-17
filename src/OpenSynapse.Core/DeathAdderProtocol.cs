namespace OpenSynapse.Core;

public static class DeathAdderProtocol
{
    public const int VendorId = 0x1532;
    public static readonly IReadOnlyDictionary<int, string> SupportedProducts = new Dictionary<int, string>
    {
        [0x00B6] = "Razer DeathAdder V3 Pro (Wired)",
        [0x00B7] = "Razer DeathAdder V3 Pro (Wireless)",
        [0x00C2] = "Razer DeathAdder V3 Pro (Wired Alt)",
        [0x00C3] = "Razer DeathAdder V3 Pro (Wireless Alt)"
    };

    public static byte[] GetFirmware(byte transactionId) => Build(transactionId, 0x00, 0x81, 0x02);
    public static byte[] GetSerial(byte transactionId) => Build(transactionId, 0x00, 0x82, 0x16);
    public static byte[] GetPollingRate(byte transactionId) => Build(transactionId, 0x00, 0x85, 0x01);
    public static byte[] GetDpi(byte transactionId) => Build(transactionId, 0x04, 0x85, 0x07, [0x01]);
    public static byte[] GetBattery(byte transactionId) => Build(transactionId, 0x07, 0x80, 0x02);
    public static byte[] GetCharging(byte transactionId) => Build(transactionId, 0x07, 0x84, 0x02);

    public static byte[] SetDpi(byte transactionId, int x, int y)
    {
        if (x is < 100 or > 30000 || y is < 100 or > 30000)
            throw new ArgumentOutOfRangeException(nameof(x), "DeathAdder V3 Pro DPI must be between 100 and 30000.");
        return Build(transactionId, 0x04, 0x05, 0x07,
        [
            0x01,
            (byte)(x >> 8), (byte)x,
            (byte)(y >> 8), (byte)y,
            0x00, 0x00
        ]);
    }

    public static byte[] SetPollingRate(byte transactionId, int hz)
    {
        var code = hz switch
        {
            1000 => 0x01,
            500 => 0x02,
            125 => 0x08,
            _ => throw new ArgumentOutOfRangeException(nameof(hz), "DeathAdder V3 Pro supports 125, 500, or 1000 Hz on the standard receiver.")
        };
        return Build(transactionId, 0x00, 0x05, 0x01, [(byte)code]);
    }

    public static byte[] Build(byte transactionId, byte commandClass, byte commandId, byte dataSize, ReadOnlySpan<byte> arguments = default)
    {
        if (arguments.Length > dataSize || dataSize > 80)
            throw new ArgumentException("Arguments must fit inside the Razer report data size.", nameof(arguments));
        var report = new byte[90];
        report[1] = transactionId;
        report[5] = dataSize;
        report[6] = commandClass;
        report[7] = commandId;
        arguments.CopyTo(report.AsSpan(8));
        report[88] = CalculateChecksum(report);
        return report;
    }

    public static byte CalculateChecksum(ReadOnlySpan<byte> report)
    {
        if (report.Length != 90) throw new ArgumentException("Razer reports are exactly 90 bytes.", nameof(report));
        byte checksum = 0;
        for (var index = 2; index < 88; index++) checksum ^= report[index];
        return checksum;
    }

    public static void ValidateResponse(ReadOnlySpan<byte> request, ReadOnlySpan<byte> response)
    {
        if (request.Length != 90) throw new ArgumentException("Razer requests are exactly 90 bytes.", nameof(request));
        if (response.Length != 90 || response[0] != 0x02)
            throw new InvalidDataException($"Razer command failed with status 0x{(response.IsEmpty ? 0 : response[0]):X2}.");
        if (CalculateChecksum(response) != response[88])
            throw new InvalidDataException("Razer response checksum is invalid.");
        if (request[1] != response[1] || request[6] != response[6] || request[7] != response[7])
            throw new InvalidDataException("Razer response does not match the request.");
    }
}
