namespace CydLAN.Protocol;

/// <summary>
/// Constants mirrored from lanmessenger/lanmessenger lmc/src/definitions.h.
/// Upstream LAN Messenger is the compatibility source of truth.
/// </summary>
public static class ProtocolDefinitions
{
    public const string ApplicationMarker = "lmcmessage";
    public const string Delimiter = "||";
    public const string UpstreamVersion = "1.2.39";

    public static class Datagram
    {
        public const string Broadcast = "BRDCST";
        public const string PublicKey = "PUBKEY";
        public const string Handshake = "HNDSHK";
        public const string Message = "MESSAG";
    }

    public static class Message
    {
        public const string Announce = "announce";
        public const string Depart = "depart";
        public const string UserData = "userdata";
        public const string Broadcast = "broadcast";
        public const string Status = "status";
        public const string Avatar = "avatar";
        public const string UserName = "name";
        public const string Ping = "ping";
        public const string Direct = "message";
        public const string Group = "groupmessage";
        public const string Public = "publicmessage";
        public const string File = "file";
        public const string Acknowledge = "acknowledge";
        public const string Failed = "failed";
        public const string Error = "error";
        public const string OldVersion = "oldversion";
        public const string Query = "query";
        public const string Info = "info";
        public const string ChatState = "chatstate";
        public const string Note = "note";
        public const string Folder = "folder";
    }

    public static class Status
    {
        public const string Available = "chat";
        public const string Busy = "busy";
        public const string DoNotDisturb = "dnd";
        public const string BeRightBack = "brb";
        public const string Away = "away";
        public const string Gone = "gone";
    }

    [Flags]
    public enum UserCapabilities : uint
    {
        None = 0,
        File = 0x00000001,
        GroupMessage = 0x00000002,
        Folder = 0x00000004,
    }
}
