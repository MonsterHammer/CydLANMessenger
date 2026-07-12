// Source of truth: https://github.com/lanmessenger/lanmessenger/blob/master/lmc/src/definitions.h
// Do not change these values to match the former Godot client.

const APP_MARKER = 'lmcmessage';
const DELIMITER = '||';

const DatagramType = Object.freeze({
  NONE: '',
  BROADCAST: 'BRDCST',
  PUBLIC_KEY: 'PUBKEY',
  HANDSHAKE: 'HNDSHK',
  MESSAGE: 'MESSAG',
});

const MessageType = Object.freeze({
  ANNOUNCE: 'announce',
  DEPART: 'depart',
  USER_DATA: 'userdata',
  BROADCAST: 'broadcast',
  STATUS: 'status',
  AVATAR: 'avatar',
  USER_NAME: 'name',
  PING: 'ping',
  MESSAGE: 'message',
  GROUP_MESSAGE: 'groupmessage',
  PUBLIC_MESSAGE: 'publicmessage',
  FILE: 'file',
  ACKNOWLEDGE: 'acknowledge',
  FAILED: 'failed',
  ERROR: 'error',
  OLD_VERSION: 'oldversion',
  QUERY: 'query',
  INFO: 'info',
  CHAT_STATE: 'chatstate',
  NOTE: 'note',
  FOLDER: 'folder',
});

const FileOperation = Object.freeze({
  INIT: 'init',
  REQUEST: 'request',
  ACCEPT: 'accept',
  DECLINE: 'decline',
  CANCEL: 'cancel',
  PROGRESS: 'progress',
  ERROR: 'error',
  ABORT: 'abort',
  COMPLETE: 'complete',
  NEXT: 'next',
});

const StatusCode = Object.freeze({
  AVAILABLE: 'chat',
  BUSY: 'busy',
  DO_NOT_DISTURB: 'dnd',
  BE_RIGHT_BACK: 'brb',
  AWAY: 'away',
  GONE: 'gone',
});

const UserCapability = Object.freeze({
  FILE: 0x00000001,
  GROUP_MESSAGE: 0x00000002,
  FOLDER: 0x00000004,
});

module.exports = {
  APP_MARKER,
  DELIMITER,
  DatagramType,
  MessageType,
  FileOperation,
  StatusCode,
  UserCapability,
};
