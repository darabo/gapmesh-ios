import XCTest
@testable import bitchat

final class IpadNavigationStateTests: XCTestCase {
    // Verifies we can save a private-chat destination and restore it exactly.
    func testPrivateChatDestinationRoundTripsThroughPersistencePayload() {
        let peerID = PeerID(str: "mesh:abcdef1234567890")
        let destination = MainTabView.IpadDestination.privateChat(peerID)

        let payload = MainTabView.persistPayload(for: destination)

        XCTAssertEqual(payload.kind, MainTabView.IpadDestinationPersistence.privateChat.rawValue)
        XCTAssertEqual(payload.peerID, peerID.id)

        let restored = MainTabView.destinationFromPersistence(kind: payload.kind, peerID: payload.peerID)

        guard case .privateChat(let restoredPeerID) = restored else {
            XCTFail("Expected privateChat destination")
            return
        }

        XCTAssertEqual(restoredPeerID, peerID)
    }

    // Invalid saved peer IDs should never crash restore; we fall back to public chat.
    func testInvalidPrivateChatPersistenceFallsBackToPublicChat() {
        let restored = MainTabView.destinationFromPersistence(
            kind: MainTabView.IpadDestinationPersistence.privateChat.rawValue,
            peerID: ""
        )

        XCTAssertEqual(restored, .publicChat)
    }

    // Confirms each iPad destination maps to the correct top-level tab state.
    func testTabMappingForEachIpadDestination() {
        XCTAssertEqual(MainTabView.tab(for: .publicChat), .chat)
        XCTAssertEqual(MainTabView.tab(for: .locations), .locations)
        XCTAssertEqual(MainTabView.tab(for: .settings), .settings)
        XCTAssertEqual(MainTabView.tab(for: .privateChat(PeerID(str: "mesh:0123456789abcdef"))), .chat)
    }
}
