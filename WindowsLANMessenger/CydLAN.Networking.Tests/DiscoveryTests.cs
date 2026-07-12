using CydLAN.Networking;
using CydLAN.Protocol;
using System.Net;
using System.Text;
using Xunit;

namespace CydLAN.Networking.Tests;

public sealed class DiscoveryTests
{
    [Theory]
    [InlineData("192.168.1.25", "255.255.255.0", "192.168.1.255")]
    [InlineData("10.20.30.40", "255.255.0.0", "10.20.255.255")]
    [InlineData("172.16.5.9", "255.255.252.0", "172.16.7.255")]
    public void DirectedBroadcast_MatchesUpstreamBitwiseRule(string address, string mask, string expected)
    {
        var result = NetworkAdapterInfo.CalculateDirectedBroadcast(IPAddress.Parse(address), IPAddress.Parse(mask));
        Assert.Equal(expected, result.ToString());
    }

    [Fact]
    public void UserId_IsPhysicalAddressPlusLogonWithoutColons()
    {
        var physicalAddress = System.Net.NetworkInformation.PhysicalAddress.Parse("AA-BB-CC-DD-EE-FF");
        Assert.Equal("AABBCCDDEEFFcyd", LmcDiscoveryService.CreateUserId(physicalAddress, "cyd"));
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
        Assert.Equal(50000, LmcTcpService.DefaultTcpPort);
    }

    [Fact]
    public void CryptoHandshake_ProducesBidirectionalLegacyAesSession()
    {
        using var alice = new LmcCryptoService();
        using var bob = new LmcCryptoService();

        var encryptedSession = alice.CreateEncryptedSession("bob", bob.PublicKeyPem);
        bob.AcceptEncryptedSession("alice", encryptedSession);

        var clear = Encoding.UTF8.GetBytes("Hello old LANNIES from CydLAN!");
        var cipher = alice.Encrypt("bob", clear);
        var recovered = bob.Decrypt("alice", cipher);

        Assert.NotEqual(clear, cipher);
        Assert.Equal(clear, recovered);
    }

    [Fact]
    public void CryptoPublicKey_UsesPkcs1RsaPemExpectedByUpstream()
    {
        using var crypto = new LmcCryptoService();
        var pem = Encoding.ASCII.GetString(crypto.PublicKeyPem);
        Assert.StartsWith("-----BEGIN RSA PUBLIC KEY-----", pem);
        Assert.EndsWith("-----END RSA PUBLIC KEY-----\n", pem);
    }
}
