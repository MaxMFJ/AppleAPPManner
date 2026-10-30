# Pixel Workspace LAN protocol v1

## Transport and pairing

- Discovery: Bonjour service `_pixelworkspace._tcp`; TCP stream, with peer-to-peer enabled.
- Pairing: the operator generates one 32-byte random hex secret and enters it on each participating Mac. A custom secret is accepted at 16 characters minimum; a generated key is recommended. The key is not transmitted.
- Key: `SHA-256(UTF8("PixelWorkspace-v1|" + pairingSecret))`, used as an AES-256-GCM key. Generate a fresh 96-bit GCM nonce for every frame. Authentication failure drops the frame.
- Framing: one UTF-8 JSON envelope per line (`0x0A` delimiter). Receivers buffer partial TCP reads and cap a frame at 1 MiB.
- Recovery: peer discovery remains active; failed outbound connections are retried after three seconds while the Bonjour endpoint remains available. A new connection receives a full snapshot before later deltas.

## Envelope

`protocolVersion` is currently `1`. `nonce`, `ciphertext`, and `tag` are JSON base64 strings (Foundation `Data` encoding). The ciphertext is a UTF-8 JSON message. Unknown versions, malformed frames, and failed authentication are discarded.

```json
{"protocolVersion":1,"nonce":"<base64>","ciphertext":"<base64>","tag":"<base64>"}
```

## Message bodies

Snapshot and incremental messages are JSON objects with an explicit `type`, to keep the payload independent of Swift's synthesized enum encoding.

```json
{"type":"snapshot","payload":{"deviceID":"…","deviceName":"…","capturedAt":"…","apps":[]}}
{"type":"upsert","payload":{"bundleID":"…","name":"…","pid":123,"department":"开发","isFrontmost":false,"cpuPercent":null,"memoryBytes":null,"deviceID":"…","updatedAt":"…"}}
{"type":"remove","deviceID":"…","pid":123,"bundleID":"…"}
```

The `apps` array uses the `ProcessRecord` fields shown in the upsert. Dates follow the JSON encoder's default ISO-independent Foundation date representation (seconds from its reference date); implementations should treat these as opaque timestamps and preserve their numeric value. Nullable metrics mean unavailable, never zero. `department` is one of `开发`, `沟通`, `创作`, `系统`, `其他`.

## Security boundary and future clients

The shared secret authenticates peers that know it and encrypts/integrity-protects payloads. Bonjour names and IP addresses are discovery hints, not identities. This MVP has no certificate identity, revocation list, replay window, or per-peer authorization; rotating the shared secret on both sides invalidates old peers. Do not expose the service beyond trusted local networks. A Windows client can implement this wire contract without sharing macOS process APIs or UI.
