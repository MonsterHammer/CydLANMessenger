class_name Definitions

enum DatagramType {
	DT_None = 0,
	DT_Broadcast,
	DT_PublicKey,
	DT_Handshake,
	DT_Message,
	DT_Max
}

const DatagramTypeNames := ["", "BRDCST", "PUBKEY", "HNDSHK", "MESSAG"]

enum MessageType {
	MT_Blank = 0,
	MT_Announce,
	MT_Depart,
	MT_UserData,
	MT_Broadcast,
	MT_Status,
	MT_Avatar,
	MT_UserName,
	MT_Ping,
	MT_Message,
	MT_GroupMessage,
	MT_PublicMessage,
	MT_File,
	MT_Acknowledge,
	MT_Failed,
	MT_Error,
	MT_OldVersion,
	MT_Query,
	MT_Info,
	MT_ChatState,
	MT_Note,
	MT_Folder,
	MT_Group,
	MT_Version,
	MT_WebFailed,
	MT_Refresh,
	MT_Join,
	MT_Leave,
	MT_Max
}

const MessageTypeNames := [
	"", "announce", "depart", "userdata", "broadcast", "status",
	"avatar", "name", "ping", "message", "groupmessage",
	"publicmessage", "file", "acknowledge", "failed", "error",
	"oldversion", "query", "info", "chatstate", "note", "folder",
	"group", "version", "webfailed", "refresh", "join", "leave"
]

enum FileMode {
	FM_Blank = 0,
	FM_Send,
	FM_Receive,
	FM_Max
}

const FileModeNames := ["", "send", "receive"]

enum FileOp {
	FO_Blank = 0,
	FO_Init,
	FO_Request,
	FO_Accept,
	FO_Decline,
	FO_Cancel,
	FO_Progress,
	FO_Error,
	FO_Abort,
	FO_Complete,
	FO_Next,
	FO_Max
}

const FileOpNames := ["", "init", "request", "accept", "decline", "cancel",
	"progress", "error", "abort", "complete", "next"]

enum FileType {
	FT_None = 0,
	FT_Normal,
	FT_Avatar,
	FT_Folder,
	FT_Max
}

const FileTypeNames := ["", "normal", "avatar", "folder"]

enum QueryOp {
	QO_None = 0,
	QO_Get,
	QO_Result,
	QO_Max
}

const QueryOpNames := ["", "get", "result"]

enum GroupMsgOp {
	GMO_None = 0,
	GMO_Request,
	GMO_Join,
	GMO_Message,
	GMO_Leave,
	GMO_Max
}

const GroupMsgOpNames := ["", "request", "join", "message", "leave"]

enum GroupOp {
	GO_None = 0,
	GO_New,
	GO_Rename,
	GO_Move,
	GO_Delete,
	GO_Max
}

enum StatusType {
	StatusTypeOnline = 0,
	StatusTypeBusy,
	StatusTypeOffline,
	StatusTypeAway,
	StatusTypeMax
}

const ST_COUNT := 6
const statusCode := ["chat", "busy", "dnd", "brb", "away", "gone"]
const statusType := [
	StatusType.StatusTypeOnline,
	StatusType.StatusTypeBusy,
	StatusType.StatusTypeBusy,
	StatusType.StatusTypeAway,
	StatusType.StatusTypeAway,
	StatusType.StatusTypeOffline
]

enum UserCap {
	UC_None = 0x00000000,
	UC_File = 0x00000001,
	UC_GroupMessage = 0x00000002,
	UC_Folder = 0x00000004,
	UC_Max = 0xFFFFFFFF
}

enum ChatState {
	CS_Blank = 0,
	CS_Active,
	CS_Composing,
	CS_Paused,
	CS_Inactive,
	CS_Gone,
	CS_Max
}

const ChatStateNames := ["", "active", "composing", "paused", "inactive", "gone"]

const GRP_DEFAULT := "General"
const GRP_DEFAULT_ID := "1CD75C10048C4E65F6082539A32DC111"
const LMC_TRUE := "true"
const LMC_FALSE := "false"
const PROGRESS_TIMEOUT := 1500
const APP_MARKER := "lmcmessage"
const DELIMITER := "||"
const DELIMITER_ESC := "\\|\\|"

# XML node names
const XN_ROOT := "lmcmessage"
const XN_HEAD := "head"
const XN_BODY := "body"
const XN_FROM := "from"
const XN_TO := "to"
const XN_MESSAGEID := "messageid"
const XN_TYPE := "type"
const XN_TIME := "time"
const XN_KEY := "key"
const XN_ADDRESS := "address"
const XN_USERID := "userid"
const XN_NAME := "name"
const XN_VERSION := "version"
const XN_PRESENCE := "presence"
const XN_STATUS := "status"
const XN_AVATAR := "avatar"
const XN_LOGON := "logon"
const XN_HOST := "host"
const XN_OS := "os"
const XN_FIRSTNAME := "firstname"
const XN_LASTNAME := "lastname"
const XN_ABOUT := "about"
const XN_THREAD := "thread"
const XN_MESSAGE := "message"
const XN_GROUPMESSAGE := "groupmessage"
const XN_BROADCAST := "broadcast"
const XN_MODE := "mode"
const XN_FILEOP := "fileop"
const XN_FILETYPE := "filetype"
const XN_FILEID := "fileid"
const XN_FILEPATH := "filepath"
const XN_FILENAME := "filename"
const XN_FILESIZE := "filesize"
const XN_CHATSTATE := "chatstate"
const XN_QUERY := "query"
const XN_QUERYOP := "queryop"
const XN_GROUP := "group"
const XN_FONT := "font"
const XN_COLOR := "color"
const XN_TEMPID := "tempid"
const XN_ERROR := "error"
const XN_GROUPMSGOP := "groupmsgop"
const XN_DESCRIPTION := "description"
const XN_NOTE := "note"
const XN_SILENTMODE := "silentmode"
const XN_PORT := "port"
const XN_CONFIG := "config"
const XN_USERCAPS := "usercaps"
const XN_FOLDERID := "folderid"
const XN_RELPATH := "relpath"
const XN_FILECOUNT := "filecount"
