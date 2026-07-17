using OpenSynapse.Core;

namespace OpenSynapse.Core.Tests;

[TestClass]
public sealed class DeathAdderProtocolTests
{
    [TestMethod]
    public void SetDpiBuildsValidatedRazerReport()
    {
        var report = DeathAdderProtocol.SetDpi(0x12, 1600, 3200);

        Assert.HasCount(90, report);
        CollectionAssert.AreEqual(
            new byte[] { 0x01, 0x06, 0x40, 0x0C, 0x80, 0x00, 0x00 },
            report[8..15]);
        Assert.AreEqual(0x12, report[1]);
        Assert.AreEqual(0x07, report[5]);
        Assert.AreEqual(0x04, report[6]);
        Assert.AreEqual(0x05, report[7]);
        Assert.AreEqual(DeathAdderProtocol.CalculateChecksum(report), report[88]);
    }

    [DataRow(1000, 0x01)]
    [DataRow(500, 0x02)]
    [DataRow(125, 0x08)]
    [TestMethod]
    public void SetPollingRateUsesLegacyDeathAdderCodes(int hz, int expectedCode)
    {
        var report = DeathAdderProtocol.SetPollingRate(0x01, hz);
        Assert.AreEqual(expectedCode, report[8]);
    }

    [TestMethod]
    public void ValidateResponseRejectsCorruptedPacket()
    {
        var request = DeathAdderProtocol.GetFirmware(0x03);
        var response = request.ToArray();
        response[0] = 0x02;
        response[88] = DeathAdderProtocol.CalculateChecksum(response);
        DeathAdderProtocol.ValidateResponse(request, response);

        response[9] ^= 0x01;
        Assert.Throws<InvalidDataException>(() => DeathAdderProtocol.ValidateResponse(request, response));
    }
}
