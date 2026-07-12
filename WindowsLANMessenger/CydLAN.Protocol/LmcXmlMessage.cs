using System.Xml.Linq;

namespace CydLAN.Protocol;

public sealed class LmcXmlMessage
{
    public const string RootName = "lmcmessage";
    public const string HeadName = "head";
    public const string BodyName = "body";

    private readonly XDocument _document;

    public LmcXmlMessage()
    {
        _document = new XDocument(
            new XElement(RootName,
                new XElement(HeadName),
                new XElement(BodyName)));
    }

    private LmcXmlMessage(XDocument document)
    {
        _document = document;
    }

    public bool IsValid => _document.Root?.Name.LocalName == RootName
        && _document.Root.Element(HeadName) is not null
        && _document.Root.Element(BodyName) is not null;

    public LmcXmlMessage AddHeader(string name, string? value)
    {
        AddNode(HeadName, name, value);
        return this;
    }

    public LmcXmlMessage AddData(string name, string? value)
    {
        AddNode(BodyName, name, value);
        return this;
    }

    public string? Header(string name) => GetNode(HeadName, name);
    public string? Data(string name) => GetNode(BodyName, name);

    public bool HeaderExists(string name) => NodeExists(HeadName, name);
    public bool DataExists(string name) => NodeExists(BodyName, name);

    public bool RemoveHeader(string name) => RemoveNode(HeadName, name);
    public bool RemoveData(string name) => RemoveNode(BodyName, name);

    public string Serialize() => _document.ToString(SaveOptions.DisableFormatting);

    public static bool TryParse(string xml, out LmcXmlMessage? message)
    {
        message = null;
        try
        {
            var document = XDocument.Parse(xml, LoadOptions.PreserveWhitespace);
            var candidate = new LmcXmlMessage(document);
            if (!candidate.IsValid)
            {
                return false;
            }

            message = candidate;
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void AddNode(string parentName, string name, string? value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        var parent = _document.Root?.Element(parentName)
            ?? throw new InvalidOperationException($"Missing {parentName} node.");
        parent.Add(new XElement(name, value ?? string.Empty));
    }

    private string? GetNode(string parentName, string name) =>
        _document.Root?.Element(parentName)?.Elements(name).FirstOrDefault()?.Value;

    private bool NodeExists(string parentName, string name) =>
        _document.Root?.Element(parentName)?.Elements(name).Any() == true;

    private bool RemoveNode(string parentName, string name)
    {
        var node = _document.Root?.Element(parentName)?.Elements(name).FirstOrDefault();
        if (node is null)
        {
            return false;
        }

        node.Remove();
        return true;
    }
}

public static class LmcXmlNode
{
    public const string From = "from";
    public const string To = "to";
    public const string MessageId = "messageid";
    public const string Type = "type";
    public const string Time = "time";
    public const string Key = "key";
    public const string Address = "address";
    public const string UserId = "userid";
    public const string Name = "name";
    public const string Version = "version";
    public const string Presence = "presence";
    public const string Status = "status";
    public const string Avatar = "avatar";
    public const string Logon = "logon";
    public const string Host = "host";
    public const string Os = "os";
    public const string Message = "message";
    public const string ChatState = "chatstate";
    public const string Note = "note";
    public const string UserCapabilities = "usercaps";
}
