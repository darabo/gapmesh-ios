//
// BitchatMessage.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Represents a user-visible message in the BitChat system.
/// Handles both broadcast messages and private encrypted messages,
/// with support for mentions, replies, and delivery tracking.
/// - Note: This is the primary data model for chat messages displayed in the UI.
final class BitchatMessage: Codable {
    // Unique identifier for the message (UUID)
    let id: String
    // Nickname of the sender
    let sender: String
    // The text content of the message
    let content: String
    // When the message was created
    let timestamp: Date
    // True if this message is a relay (forwarded from another peer)
    let isRelay: Bool
    // If relayed, this is the nickname of the original sender
    let originalSender: String?
    // True if this is a direct private message (not broadcast)
    let isPrivate: Bool
    // If private, the nickname of the recipient
    let recipientNickname: String?
    // The cryptographic PeerID of the sender (important for private messaging verification)
    let senderPeerID: PeerID?
    // List of nicknames mentioned in the message (e.g. @alice)
    let mentions: [String]?
    // Tracks delivery status (sending, sent, failed) for UI feedback
    var deliveryStatus: DeliveryStatus?
    
    // Cached formatted text (Rich Text) to avoid re-parsing on every render.
    // The key is a combination of "isDarkTheme-isSelfMessage" to handle UI variations.
    // Marked private so it's not serialized.
    private var _cachedFormattedText: [String: AttributedString] = [:]
    
    // Helper to retrieve cached text for UI rendering
    func getCachedFormattedText(isDark: Bool, isSelf: Bool) -> AttributedString? {
        return _cachedFormattedText["\(isDark)-\(isSelf)"]
    }
    
    // Helper to set cached text
    func setCachedFormattedText(_ text: AttributedString, isDark: Bool, isSelf: Bool) {
        _cachedFormattedText["\(isDark)-\(isSelf)"] = text
    }
    
    // Keys used for JSON encoding/decoding via Codable
    enum CodingKeys: String, CodingKey {
        case id, sender, content, timestamp, isRelay, originalSender
        case isPrivate, recipientNickname, senderPeerID, mentions, deliveryStatus
    }
    
    // Memberwise initializer
    init(
        id: String? = nil,
        sender: String,
        content: String,
        timestamp: Date,
        isRelay: Bool,
        originalSender: String? = nil,
        isPrivate: Bool = false,
        recipientNickname: String? = nil,
        senderPeerID: PeerID? = nil,
        mentions: [String]? = nil,
        deliveryStatus: DeliveryStatus? = nil
    ) {
        self.id = id ?? UUID().uuidString
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.isRelay = isRelay
        self.originalSender = originalSender
        self.isPrivate = isPrivate
        self.recipientNickname = recipientNickname
        self.senderPeerID = senderPeerID
        self.mentions = mentions
        // Default delivery status is 'sending' for private messages, nil for broadcasts
        self.deliveryStatus = deliveryStatus ?? (isPrivate ? .sending : nil)
    }
}

// MARK: - Equatable Conformance

extension BitchatMessage: Equatable {
    // Defines equality between two messages.
    // Used by SwiftUI to determine if the view needs updating.
    static func == (lhs: BitchatMessage, rhs: BitchatMessage) -> Bool {
        return lhs.id == rhs.id &&
               lhs.sender == rhs.sender &&
               lhs.content == rhs.content &&
               lhs.timestamp == rhs.timestamp &&
               lhs.isRelay == rhs.isRelay &&
               lhs.originalSender == rhs.originalSender &&
               lhs.isPrivate == rhs.isPrivate &&
               lhs.recipientNickname == rhs.recipientNickname &&
               lhs.senderPeerID == rhs.senderPeerID &&
               lhs.mentions == rhs.mentions &&
               lhs.deliveryStatus == rhs.deliveryStatus
    }
}

// MARK: - Binary encoding

// This extension handles serialization for the Bluetooth Mesh protocol.
// The custom binary format is more compact than JSON, saving bandwidth.
extension BitchatMessage {
    // Converts the message object into a compact byte array.
    func toBinaryPayload() -> Data? {
        var data = Data()
        
        // Message format construction:
        // 1. Flags Byte: Encodes boolean properties and presence of optional fields into a single byte.
        //    - Bit 0: isRelay
        //    - Bit 1: isPrivate
        //    - Bit 2: hasOriginalSender
        //    - Bit 3: hasRecipientNickname
        //    - Bit 4: hasSenderPeerID
        //    - Bit 5: hasMentions
        
        var flags: UInt8 = 0
        if isRelay { flags |= 0x01 }
        if isPrivate { flags |= 0x02 }
        if originalSender != nil { flags |= 0x04 }
        if recipientNickname != nil { flags |= 0x08 }
        if senderPeerID != nil { flags |= 0x10 }
        if mentions != nil && !mentions!.isEmpty { flags |= 0x20 }
        
        data.append(flags)
        
        // 2. Timestamp: 8 bytes, milliseconds since epoch (Big Endian)
        let timestampMillis = UInt64(timestamp.timeIntervalSince1970 * 1000)
        for i in (0..<8).reversed() {
            data.append(UInt8((timestampMillis >> (i * 8)) & 0xFF))
        }
        
        // 3. ID: 1 byte length + UTF8 string bytes (max 255 chars)
        if let idData = id.data(using: .utf8) {
            data.append(UInt8(min(idData.count, 255)))
            data.append(idData.prefix(255))
        } else {
            data.append(0)
        }
        
        // 4. Sender Name: 1 byte length + UTF8 string bytes (max 255 chars)
        if let senderData = sender.data(using: .utf8) {
            data.append(UInt8(min(senderData.count, 255)))
            data.append(senderData.prefix(255))
        } else {
            data.append(0)
        }
        
        // 5. Content: 2 bytes length (max 65535 chars) + UTF8 string bytes
        if let contentData = content.data(using: .utf8) {
            let length = UInt16(min(contentData.count, 65535))
            // Encode length as 2 bytes, big-endian
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(UInt8(length & 0xFF))
            data.append(contentData.prefix(Int(length)))
        } else {
            data.append(contentsOf: [0, 0])
        }
        
        // 6. Optional Fields (only appended if corresponding flag bit is set)

        // Original Sender (for relayed messages)
        if let originalSender = originalSender, let origData = originalSender.data(using: .utf8) {
            data.append(UInt8(min(origData.count, 255)))
            data.append(origData.prefix(255))
        }
        
        // Recipient Nickname (for private messages)
        if let recipientNickname = recipientNickname, let recipData = recipientNickname.data(using: .utf8) {
            data.append(UInt8(min(recipData.count, 255)))
            data.append(recipData.prefix(255))
        }
        
        // Sender PeerID
        if let peerData = senderPeerID?.id.data(using: .utf8) {
            data.append(UInt8(min(peerData.count, 255)))
            data.append(peerData.prefix(255))
        }
        
        // Mentions List
        if let mentions = mentions {
            data.append(UInt8(min(mentions.count, 255))) // Number of mentions
            for mention in mentions.prefix(255) {
                if let mentionData = mention.data(using: .utf8) {
                    data.append(UInt8(min(mentionData.count, 255)))
                    data.append(mentionData.prefix(255))
                } else {
                    data.append(0)
                }
            }
        }
        
        return data
    }
    
    // Reconstructs a BitchatMessage from the custom binary format.
    convenience init?(_ data: Data) {
        // Create an immutable copy to prevent threading issues
        let dataCopy = Data(data)
        
        // Minimum valid payload size check
        guard dataCopy.count >= 13 else {
            return nil
        }
        
        var offset = 0
        
        // Decode Flags
        guard offset < dataCopy.count else {
            return nil
        }
        let flags = dataCopy[offset]; offset += 1
        let isRelay = (flags & 0x01) != 0
        let isPrivate = (flags & 0x02) != 0
        let hasOriginalSender = (flags & 0x04) != 0
        let hasRecipientNickname = (flags & 0x08) != 0
        let hasSenderPeerID = (flags & 0x10) != 0
        let hasMentions = (flags & 0x20) != 0
        
        // Decode Timestamp
        guard offset + 8 <= dataCopy.count else {
            return nil
        }
        let timestampData = dataCopy[offset..<offset+8]
        let timestampMillis = timestampData.reduce(0) { result, byte in
            (result << 8) | UInt64(byte)
        }
        offset += 8
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000.0)
        
        // Decode ID
        guard offset < dataCopy.count else {
            return nil
        }
        let idLength = Int(dataCopy[offset]); offset += 1
        guard offset + idLength <= dataCopy.count else {
            return nil
        }
        let id = String(data: dataCopy[offset..<offset+idLength], encoding: .utf8) ?? UUID().uuidString
        offset += idLength
        
        // Decode Sender
        guard offset < dataCopy.count else {
            return nil
        }
        let senderLength = Int(dataCopy[offset]); offset += 1
        guard offset + senderLength <= dataCopy.count else {
            return nil
        }
        let sender = String(data: dataCopy[offset..<offset+senderLength], encoding: .utf8) ?? "unknown"
        offset += senderLength
        
        // Decode Content
        guard offset + 2 <= dataCopy.count else {
            return nil
        }
        let contentLengthData = dataCopy[offset..<offset+2]
        let contentLength = Int(contentLengthData.reduce(0) { result, byte in
            (result << 8) | UInt16(byte)
        })
        offset += 2
        guard offset + contentLength <= dataCopy.count else {
            return nil
        }
        
        let content = String(data: dataCopy[offset..<offset+contentLength], encoding: .utf8) ?? ""
        offset += contentLength
        
        // Decode Optional Fields
        var originalSender: String?
        if hasOriginalSender && offset < dataCopy.count {
            let length = Int(dataCopy[offset]); offset += 1
            if offset + length <= dataCopy.count {
                originalSender = String(data: dataCopy[offset..<offset+length], encoding: .utf8)
                offset += length
            }
        }
        
        var recipientNickname: String?
        if hasRecipientNickname && offset < dataCopy.count {
            let length = Int(dataCopy[offset]); offset += 1
            if offset + length <= dataCopy.count {
                recipientNickname = String(data: dataCopy[offset..<offset+length], encoding: .utf8)
                offset += length
            }
        }
        
        var senderPeerID: PeerID?
        if hasSenderPeerID && offset < dataCopy.count {
            let length = Int(dataCopy[offset]); offset += 1
            if offset + length <= dataCopy.count {
                senderPeerID = PeerID(data: dataCopy[offset..<offset+length])
                offset += length
            }
        }
        
        // Decode Mentions array
        var mentions: [String]?
        if hasMentions && offset < dataCopy.count {
            let mentionCount = Int(dataCopy[offset]); offset += 1
            if mentionCount > 0 {
                mentions = []
                for _ in 0..<mentionCount {
                    if offset < dataCopy.count {
                        let length = Int(dataCopy[offset]); offset += 1
                        if offset + length <= dataCopy.count {
                            if let mention = String(data: dataCopy[offset..<offset+length], encoding: .utf8) {
                                mentions?.append(mention)
                            }
                            offset += length
                        }
                    }
                }
            }
        }
        
        self.init(
            id: id,
            sender: sender,
            content: content,
            timestamp: timestamp,
            isRelay: isRelay,
            originalSender: originalSender,
            isPrivate: isPrivate,
            recipientNickname: recipientNickname,
            senderPeerID: senderPeerID,
            mentions: mentions
        )
    }
}

// MARK: - Helpers

extension BitchatMessage {
    
    // Formatter for displaying message timestamps (e.g., "14:30:00")
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }
}

extension Array where Element == BitchatMessage {
    /// Utility to clean up a list of messages.
    /// 1. Removes empty messages.
    /// 2. Removes duplicates based on ID.
    /// 3. Sorts by timestamp.
    /// Used when merging message history from different sources (Mesh + Nostr).
    func cleanedAndDeduped() -> [Element] {
        let arr = filter { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        guard arr.count > 1 else {
            return arr
        }
        var seen = Set<String>()
        var dedup: [BitchatMessage] = []
        for m in arr.sorted(by: { $0.timestamp < $1.timestamp }) {
            if !seen.contains(m.id) {
                dedup.append(m)
                seen.insert(m.id)
            }
        }
        return dedup
    }
}
