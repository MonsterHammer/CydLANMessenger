using System.Text;

namespace CydLAN.Protocol;

public enum LmcDatagramType
{
    Broadcast,
    PublicKey,
    Handshake,
    Message,
}

public sealed record LmcDatagram(LmcDatagramType Type, byte[] Payload);

public static class LmcDatagramCodec
{
    public const int HeaderLength = 6;

    public static byte[] Encode(LmcDatagramType type, ReadOnlySpan<byte> payload)
    {
        var header = Encoding.ASCII.GetBytes(ToHeader(type));
        var result = new byte[HeaderLength + payload.Length];
        header.CopyTo(result, 0);
        payload.CopyTo(result.AsSpan(HeaderLength));
        return result;
    }

    public static bool TryDecode(ReadOnlySpan<byte> datagram, out LmcDatagram? result)
    {
        result = null;
        if (datagram.Length < HeaderLength)
        {
            return false;
        }

        var header = Encoding.ASCII.GetString(datagram[..HeaderLength]);
        if (!TryParseHeader(header, out var type))
        {
            return false;
        }

        result = new LmcDatagram(type, datagram[HeaderLength..].ToArray());
        return true;
    }

    public static string ToHeader(LmcDatagramType type) => type switch
    {
        LmcDatagramType.Broadcast => ProtocolDefinitions.Datagram.Broadcast,
        LmcDatagramType.PublicKey => ProtocolDefinitions.Datagram.PublicKey,
        LmcDatagramType.Handshake => ProtocolDefinitions.Datagram.Handshake,
        LmcDatagramType.Message => ProtocolDefinitions.Datagram.Message,
        _ => throw new ArgumentOutOfRangeException(nameof(type)),
    };

    public static bool TryParseHeader(string header, out LmcDatagramType type)
    {
        type = header switch
        {
            ProtocolDefinitions.Datagram.Broadcast => LmcDatagramType.Broadcast,
            ProtocolDefinitions.Datagram.PublicKey => LmcDatagramType.PublicKey,
            ProtocolDefinitions.Datagram.Handshake => LmcDatagramType.Handshake,
            ProtocolDefinitions.Datagram.Message => LmcDatagramType.Message,
            _ => default,
        };

        return header is ProtocolDefinitions.Datagram.Broadcast
            or ProtocolDefinitions.Datagram.PublicKey
            or ProtocolDefinitions.Datagram.Handshake
            or ProtocolDefinitions.Datagram.Message;
    }
}
