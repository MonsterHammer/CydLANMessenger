using System.Text;
using CydLAN.Protocol;
using Xunit;

namespace CydLAN.Protocol.Tests;

public sealed class ProtocolCodecTests
{
    [Theory]
    [InlineData(LmcDatagramType.Broadcast, "BRDCST")]
    [InlineData(LmcDatagramType.PublicKey, "PUBKEY")]
    [InlineData(LmcDatagramType.Handshake, "HNDSHK")]
    [InlineData(LmcDatagramType.Message, "MESSAG")]
    public void DatagramHeader_IsExactlySixAsciiBytes(LmcDatagramType type, string expected)
    {
        var encoded = LmcDatagramCodec.Encode(type, ReadOnlySpan<byte>.Empty);

        Assert.Equal(6, encoded.Length);
        Assert.Equal(expected, Encoding.ASCII.GetString(encoded));
    }

    [Fact]
    public void Datagram_RoundTripsPayloadWithoutModification()
    {
        var payload = Encoding.UTF8.GetBytes("<lmcmessage><head/><body/></lmcmessage>");
        var encoded = LmcDatagramCodec.Encode(LmcDatagramType.Broadcast, payload);

        Assert.True(LmcDatagramCodec.TryDecode(encoded, out var decoded));
        Assert.NotNull(decoded);
        Assert.Equal(LmcDatagramType.Broadcast, decoded.Type);
        Assert.Equal(payload, decoded.Payload);
    }

    [Fact]
    public void Datagram_RejectsUnknownHeader()
    {
        Assert.False(LmcDatagramCodec.TryDecode("BADHDRpayload"u8, out _));
    }

    [Fact]
    public void XmlMessage_UsesUpstreamRootHeadAndBody()
    {
        var message = new LmcXmlMessage()
            .AddHeader(LmcXmlNode.From, "ALEX-PC")
            .AddHeader(LmcXmlNode.Type, ProtocolDefinitions.Message.Announce)
            .AddData(LmcXmlNode.Name, "Alex PC")
            .AddData(LmcXmlNode.Status, ProtocolDefinitions.Status.Available);

        var xml = message.Serialize();

        Assert.StartsWith("<lmcmessage><head>", xml);
        Assert.Contains("<from>ALEX-PC</from>", xml);
        Assert.Contains("<type>announce</type>", xml);
        Assert.Contains("</head><body>", xml);
        Assert.EndsWith("</body></lmcmessage>", xml);
    }

    [Fact]
    public void XmlMessage_RoundTripsEscapedText()
    {
        var original = new LmcXmlMessage()
            .AddData(LmcXmlNode.Message, "Hello <Cyd> & old LANNIES!");

        Assert.True(LmcXmlMessage.TryParse(original.Serialize(), out var parsed));
        Assert.NotNull(parsed);
        Assert.Equal("Hello <Cyd> & old LANNIES!", parsed.Data(LmcXmlNode.Message));
    }

    [Fact]
    public void XmlMessage_RejectsWrongRoot()
    {
        Assert.False(LmcXmlMessage.TryParse("<message><head/><body/></message>", out _));
    }
}
