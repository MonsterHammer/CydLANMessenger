# Protocol Source of Truth

The compatibility source of truth for CydLAN is the original upstream project:

- Repository: `lanmessenger/lanmessenger`
- Branch: `master`
- Upstream application version represented in source: `1.2.39`
- License: GNU GPL v3 or later

The Godot client in this repository is **not** authoritative for protocol behavior. It may be consulted only as a record of a previous implementation attempt.

## Authoritative upstream areas

The Electron client must be implemented and tested against these upstream files and their dependencies:

- `lmc/src/definitions.h` — datagram names, message names, file operations, statuses, capability flags, delimiter and application marker.
- `lmc/src/network.cpp` and network classes — interface selection, UDP discovery, TCP transport and crypto wiring.
- `lmc/src/messaging.cpp` / `messagingproc.cpp` — announce/depart flow, user identity, retries, acknowledgements, status, typing, messages and file operations.
- Upstream XML, crypto, UDP and TCP implementations — exact serialization, framing, encryption and handshake behavior.

## Compatibility rule

When the Godot implementation, prior notes, generated code, or assumptions conflict with upstream LAN Messenger, the upstream implementation wins.

## Required interoperability gate

CydLAN is not considered compatible until it successfully exchanges data with an unmodified upstream LAN Messenger client on separate Windows machines or VMs for:

1. discovery and announce/depart;
2. bidirectional direct messages;
3. status and typing state;
4. acknowledgements and retry behavior;
5. public key and handshake exchange;
6. encrypted message transport;
7. normal file transfer;
8. avatar and user information exchange.
