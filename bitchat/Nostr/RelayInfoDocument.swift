import Foundation

// MARK: - NIP-11 Relay Information Document

/// Codable model representing the NIP-11 Relay Information Document.
/// Fetched via HTTP GET with `Accept: application/nostr+json`.
struct RelayInfoDocument: Codable {
    let name: String?
    let description: String?
    let pubkey: String?
    let contact: String?
    let supportedNips: [Int]?
    let software: String?
    let version: String?
    let limitation: RelayLimitation?
    let retention: [RetentionPolicy]?
    let fees: RelayFees?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case name, description, pubkey, contact
        case supportedNips = "supported_nips"
        case software, version, limitation, retention, fees, icon
    }

    // MARK: - Convenience

    /// Whether this relay requires NIP-42 authentication.
    var requiresAuth: Bool {
        limitation?.authRequired ?? false
    }

    /// Whether this relay charges fees for any operation.
    var requiresPayment: Bool {
        limitation?.paymentRequired ?? false ||
        fees?.hasAnyFee == true
    }

    /// Whether this relay advertises support for a specific NIP.
    func supportsNip(_ nip: Int) -> Bool {
        supportedNips?.contains(nip) ?? false
    }

    /// Human-readable summary of key capabilities.
    var capabilitiesSummary: String {
        var parts: [String] = []
        if let name = name { parts.append("name=\(name)") }
        if let nips = supportedNips, !nips.isEmpty {
            parts.append("nips=\(nips.map { String($0) }.joined(separator: ","))")
        }
        if requiresAuth { parts.append("auth_required") }
        if requiresPayment { parts.append("payment_required") }
        if let maxLen = limitation?.maxMessageLength {
            parts.append("max_msg=\(maxLen)")
        }
        return parts.isEmpty ? "(no info)" : parts.joined(separator: " | ")
    }
}

// MARK: - Limitation

struct RelayLimitation: Codable {
    let maxMessageLength: Int?
    let maxSubscriptions: Int?
    let maxFilters: Int?
    let maxLimit: Int?
    let maxSubidLength: Int?
    let maxEventTags: Int?
    let maxContentLength: Int?
    let minPowDifficulty: Int?
    let authRequired: Bool?
    let paymentRequired: Bool?
    let restrictedWrites: Bool?
    let createdAtLowerLimit: Int?
    let createdAtUpperLimit: Int?

    enum CodingKeys: String, CodingKey {
        case maxMessageLength = "max_message_length"
        case maxSubscriptions = "max_subscriptions"
        case maxFilters = "max_filters"
        case maxLimit = "max_limit"
        case maxSubidLength = "max_subid_length"
        case maxEventTags = "max_event_tags"
        case maxContentLength = "max_content_length"
        case minPowDifficulty = "min_pow_difficulty"
        case authRequired = "auth_required"
        case paymentRequired = "payment_required"
        case restrictedWrites = "restricted_writes"
        case createdAtLowerLimit = "created_at_lower_limit"
        case createdAtUpperLimit = "created_at_upper_limit"
    }
}

// MARK: - Fees

struct RelayFees: Codable {
    let admission: [FeeSchedule]?
    let subscription: [FeeSchedule]?
    let publication: [FeeSchedule]?

    var hasAnyFee: Bool {
        let allFees = (admission ?? []) + (subscription ?? []) + (publication ?? [])
        return allFees.contains { ($0.amount ?? 0) > 0 }
    }
}

struct FeeSchedule: Codable {
    let amount: Int?
    let unit: String?
    let period: Int?
}

// MARK: - Retention

struct RetentionPolicy: Codable {
    let kinds: [Int]?  // nil means "all kinds"
    let time: Int?     // seconds; nil means indefinite
    let count: Int?    // max events kept; nil means unlimited
}
