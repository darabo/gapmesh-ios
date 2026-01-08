# BitChat Backwards Compatibility

**Gap Mesh** is a fork of [@permissionlesstech/bitchat](https://github.com/permissionlesstech/bitchat) catered to the needs of Iranian users. This document confirms the protocol-level compatibility between the two apps.

## Status: ✅ FULLY COMPATIBLE

Gap Mesh users and BitChat users can communicate with each other over both:
- **Bluetooth Mesh** (local, offline communication)
- **Nostr Relays** (global, internet-based communication)

## Protocol Compatibility Details

### 1. BLE Transport Layer

| Component | Gap Mesh | BitChat | Status |
|-----------|----------|---------|--------|
| Service UUID | `F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C` | Same | ✅ |
| Characteristic UUID | `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D` | Same | ✅ |

### 2. Binary Protocol

| Component | Gap Mesh | BitChat | Status |
|-----------|----------|---------|--------|
| Protocol Version | 1, 2 | Same | ✅ |
| Header Size (v1) | 14 bytes | Same | ✅ |
| Header Size (v2) | 16 bytes | Same | ✅ |
| Padding | PKCS#7 (256/512/1024/2048) | Same | ✅ |
| Compression | zlib | Same | ✅ |

### 3. Message Types

| Type | Value | Description | Status |
|------|-------|-------------|--------|
| `announce` | `0x01` | Peer presence | ✅ |
| `message` | `0x02` | Public chat | ✅ |
| `leave` | `0x03` | Peer departure | ✅ |
| `noiseHandshake` | `0x10` | Encryption setup | ✅ |
| `noiseEncrypted` | `0x11` | Encrypted payloads | ✅ |
| `fragment` | `0x20` | Large messages | ✅ |
| `requestSync` | `0x21` | GCS filter sync | ✅ |
| `fileTransfer` | `0x22` | Binary files | ✅ |

### 4. Noise Protocol

| Component | Gap Mesh | BitChat | Status |
|-----------|----------|---------|--------|
| Protocol | `Noise_XX_25519_ChaChaPoly_SHA256` | Same | ✅ |
| Key Agreement | Curve25519 | Same | ✅ |
| Signing | Ed25519 | Same | ✅ |
| AEAD | ChaCha20-Poly1305 | Same | ✅ |

### 5. Nostr Protocol

| Component | Gap Mesh | BitChat | Status |
|-----------|----------|---------|--------|
| DM Rumor (Kind 14) | NIP-17 | Same | ✅ |
| Seal (Kind 13) | NIP-17 | Same | ✅ |
| Gift Wrap (Kind 1059) | NIP-59 | Same | ✅ |
| Ephemeral Events (Kind 20000) | Geohash channels | Same | ✅ |
| Text Notes (Kind 1) | Location notes | Same | ✅ |
| Encryption | NIP-44 v2 (XChaCha20-Poly1305) | Same | ✅ |
| Embedded Format | `bitchat1:` prefix | Same | ✅ |

### 6. Default Relay List

Both apps use the same default Nostr relays:
- `wss://relay.damus.io`
- `wss://nos.lol`
- `wss://relay.primal.net`
- `wss://offchain.pub`
- `wss://nostr21.com`

### 7. URL Schemes

| Scheme | Gap Mesh | BitChat |
|--------|----------|---------|
| `bitchat://` | ✅ Supported | ✅ Supported |
| `gap://` | ✅ Supported | ❌ Not supported |

Gap Mesh accepts both URL schemes for maximum compatibility.

## Usage Scenarios

### Scenario 1: BLE Mesh Communication
1. Gap user and BitChat user are in BLE range
2. Both apps advertise/scan using the same Service UUID
3. They discover each other and complete Noise XX handshake
4. They can exchange public messages and encrypted private messages
5. Messages relay through the mesh network (max 7 hops)

### Scenario 2: Nostr DM Communication
1. Gap user and BitChat user exchange Nostr public keys (npub)
2. They add each other as favorites
3. Private messages are sent via NIP-17 gift-wrapped events
4. Messages contain embedded `bitchat1:` packets
5. Both apps can decrypt and display the messages

### Scenario 3: Location Channels
1. Both users enable location-based channels
2. Both subscribe to kind 20000 events filtered by geohash
3. Messages appear in both apps' location chat UI

## Non-Breaking Differences

These differences do not affect interoperability:

| Difference | Impact |
|------------|--------|
| App name ("Gap Mash" vs "BitChat") | Display only |
| Bundle ID | App Store differentiation |
| Localization (Farsi support) | UI only |
| Extended URL scheme (`gap://`) | Additive |

## Verification

To verify compatibility:

1. **BLE Test**: Install both apps on two devices, ensure they discover each other and can chat locally
2. **Nostr Test**: Exchange npub keys and verify private messages work in both directions
3. **Protocol Test**: Run the existing unit tests which validate binary encoding/decoding

## Technical Reference

- [BitChat Whitepaper](../WHITEPAPER.md)
- [Binary Protocol](../bitchat/Protocols/BinaryProtocol.swift)
- [Nostr Protocol](../bitchat/Nostr/NostrProtocol.swift)
- [BLE Service](../bitchat/Services/BLE/BLEService.swift)

---

*Last verified: January 2026*
*Gap Mesh commit: Current HEAD*
*BitChat reference: @permissionlesstech/bitchat main branch*
