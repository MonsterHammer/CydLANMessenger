namespace CydLAN.Protocol;

public sealed record LmcMessageHeader(string Type, long MessageId, string From, string? To);

public static class LmcMessageCodec
{
    public static LmcXmlMessage Create(string type, long messageId, string from, string? to = null, LmcXmlMessage? message = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(type);
        ArgumentException.ThrowIfNullOrWhiteSpace(from);

        message ??= new LmcXmlMessage();
        message.RemoveHeader(LmcXmlNode.Time);
        message.AddHeader(LmcXmlNode.From, from);
        if (!string.IsNullOrWhiteSpace(to))
        {
            message.AddHeader(LmcXmlNode.To, to);
        }
        message.AddHeader(LmcXmlNode.MessageId, messageId.ToString());
        message.AddHeader(LmcXmlNode.Type, type);
        return message;
    }

    public static bool TryRead(string xml, out LmcMessageHeader? header, out LmcXmlMessage? message)
    {
        header = null;
        message = null;
        if (!LmcXmlMessage.TryParse(xml, out var parsed) || parsed is null)
        {
            return false;
        }

        var type = parsed.Header(LmcXmlNode.Type);
        var from = parsed.Header(LmcXmlNode.From);
        var idText = parsed.Header(LmcXmlNode.MessageId);
        if (string.IsNullOrWhiteSpace(type)
            || string.IsNullOrWhiteSpace(from)
            || !long.TryParse(idText, out var id))
        {
            return false;
        }

        header = new LmcMessageHeader(type, id, from, parsed.Header(LmcXmlNode.To));
        message = parsed;
        return true;
    }
}
