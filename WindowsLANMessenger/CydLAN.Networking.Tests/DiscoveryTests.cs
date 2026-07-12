using CydLAN.Networking;
using CydLAN.Protocol;
using System.Net;

namespace CydLAN.Networking.Tests;

public sealed class DiscoveryTests
{
    [Theory]
    [InlineData("192.168.1.25", "255.255.255.0", "192.168.1.255")]
    [InlineData("10.20.30.40", "255.255.0.0", "10.20.255.255")]
    [InlineData("172.16.5.9", "255.255.252.0", "172.16.7.255")]
    public void DirectedBroadcast_MatchesUpstreamBitwiseRule(string address, string mask, string expected)
    {
        var result = NetworkAdapterInfo.CalculateDirectedBroadcast(
            IPAddress.Parse(address),
            IPAddress.Parse(mask));

        Assert.Equal(expected, result.ToString());
    }

    [Fact]
    public void UserId_IsPhysicalAddressPlusLogonWithoutColons()
    {
        var physicalAddress = System.Net.NetworkInformation.PhysicalAddress.Parse("AA-BB-CC-DD-EE-FF");

        var id = LmcDiscoveryService.CreateUserId(physicalAddress, "cyd");

        Assert.Equal("AABBCCDDEEFFcyd", id);
    }

    [Theory]
    [InlineData("announce")]
    [InlineData("depart")]
    public void PresencePacket_IsRawUpstreamXml(string type)
    {
        var packet = LmcMessageCodec.Create(type, 1, "AABBCCDDEEFFcyd").Serialize();

        Assert.StartsWith("<lmcmessage><head>", packet);
        Assert.Contains("<from>AABBCCDDEEFFcyd</from>", packet);
        Assert.Contains("<messageid>1</messageid>", packet);
        Assert.Contains($"<type>{type}</type>", packet);
        Assert.DoesNotContain("BRDCST", packet);
    }

    [Fact]
    public void DiscoveryDefaults_MatchUpstreamSettings()
    {
        Assert.Equal(50000, LmcDiscoveryService.DefaultUdpPort);
        Assert.Equal("239.255.100.100", LmcDiscoveryService.DefaultMulticastAddress.ToString());
    }
}
