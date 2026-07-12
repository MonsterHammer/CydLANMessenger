# CydLAN for Windows

Native Windows 11 implementation of CydLAN Messenger.

## Stack

- C# and .NET 8
- WinUI 3
- Windows App SDK
- Mica backdrop and Fluent controls
- Separate protocol library

## Protocol authority

Compatibility behavior must follow the original upstream implementation:

`https://github.com/lanmessenger/lanmessenger`

The Godot implementation is not authoritative.

## Current state

The initial native application shell includes:

- Windows 11 title and connection area
- Fluent navigation rail
- searchable LAN contact list
- online/offline filters
- active conversation layout
- flat message bubbles
- message composer
- user information, files, and history panel
- Mica backdrop when supported
- minimum responsive desktop size
- upstream protocol constants in `CydLAN.Protocol`

The visible contacts and messages are design-preview data until native discovery and transport are connected.

## Planned implementation order

1. Port exact upstream datagram framing and XML serialization.
2. Implement interface selection and UDP announce/depart discovery.
3. Implement TCP peer connections and message acknowledgement.
4. Port RSA/public-key exchange and encrypted handshake behavior.
5. Connect discovered users and live messages to the WinUI view models.
6. Add file, folder, avatar, status, and typing interoperability.
7. Build a two-client compatibility harness against unmodified LAN Messenger 1.2.39.
8. Add tray behavior, notifications, persistence, installer, and signed release packaging.

## Open in Visual Studio

Open:

`WindowsLANMessenger/CydLAN.sln`

Use Visual Studio 2022 with the .NET desktop and Windows App SDK workloads installed.
