//
//  PeopleTabView.swift
//
//

import SwiftUI

struct PeopleTabView: View {
    // MARK: Overview
    // This is the "container" version of People UI used in compact layouts.
    // It delegates most list rendering to `PeopleListSections` so iPad sidebar
    // and phone tab share the same logic and stay behaviorally identical.
    @Binding var selectedTab: MainTabView.Tab
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var showPrivateChatSheet = false
    @State private var selectedPeerForChat: PeerID? = nil
    @State private var showVerificationSheet = false

    var body: some View {
        NavigationStack {
            List {
                // Reusable list content also used inside the iPad sidebar.
                PeopleListSections(
                    selectedPrivatePeerID: selectedPeerForChat,
                    onSelectPrivateChat: { peerID in
                        selectedPeerForChat = peerID
                        viewModel.startPrivateChat(with: peerID)
                        showPrivateChatSheet = true
                    }
                )
                .environmentObject(viewModel)
            }
            #if os(iOS)
            // Match the vertical rhythm used in Settings/Locations by adding
            // breathing room between the large navigation title and first row.
            .contentMargins(.top, 20, for: .scrollContent)
            #endif
            .navigationTitle(LanguageManager.shared.localizedString("tabs.people"))
            .navigationBarTitleDisplayMode(.large)
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showVerificationSheet = true }) {
                        Image(systemName: "qrcode.viewfinder")
                            .foregroundColor(Theme.legacyGreen(colorScheme))
                    }
                    .hoverEffect(.highlight)
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showVerificationSheet = true }) {
                        Image(systemName: "qrcode.viewfinder")
                            .foregroundColor(Theme.legacyGreen(colorScheme))
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $showVerificationSheet) {
            VerificationSheetView(isPresented: $showVerificationSheet)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showPrivateChatSheet) {
            if let peerID = selectedPeerForChat {
                PrivateChatSheetView(peerID: peerID)
                    .environmentObject(viewModel)
            }
        }
    }
}

// Reusable "People" sections so we can render identical content in:
// 1) The dedicated People tab (phone/compact), and
// 2) The iPad split-view sidebar.
struct PeopleListSections: View {
    // MARK: Overview
    // This view is intentionally reusable and stateless-ish:
    // - parent injects currently selected private peer (for highlighting),
    // - parent injects search text,
    // - parent injects "open chat" callback (sheet or inline detail).
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @ObservedObject private var favoritesService = FavoritesPersistenceService.shared
    @Environment(\.colorScheme) var colorScheme

    var selectedPrivatePeerID: PeerID?
    var searchText: String = ""
    // Parent decides how private chat opens (sheet vs split detail).
    var onSelectPrivateChat: (PeerID) -> Void

    @State private var showNostrPMAlert = false
    @State private var selectedNostrPerson: GeoPerson? = nil

    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }

    // Total active count depends on channel
    private var totalActiveCount: Int {
        switch locationManager.selectedChannel {
        case .mesh:
            return viewModel.allPeers.filter { $0.isConnected && $0.peerID != viewModel.meshService.myPeerID }.count
        case .location(let ch):
            return viewModel.geohashParticipantCount(for: ch.geohash)
        }
    }

    // Current channel description
    private var channelDescription: String {
        switch locationManager.selectedChannel {
        case .mesh:
            return LanguageManager.shared.localizedString("channels.mesh")
        case .location(let ch):
            return "#\(ch.geohash)"
        }
    }

    private var normalizedSearchText: String {
        // Normalize once so simple contains() matching behaves consistently.
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matchesSearch(_ value: String) -> Bool {
        guard !normalizedSearchText.isEmpty else { return true }
        return value.lowercased().contains(normalizedSearchText)
    }

    // Favorite peers (online mesh peers)
    private var favoritePeers: [BitchatPeer] {
        viewModel.allPeers.filter { peer in
            peer.isConnected &&
            peer.peerID != viewModel.meshService.myPeerID &&
            favoritesService.favorites[peer.noisePublicKey]?.isFavorite == true &&
            matchesSearch(peer.displayName + " " + peer.peerID.id)
        }
    }

    // Non-favorite active mesh peers
    private var otherActiveMeshPeers: [BitchatPeer] {
        viewModel.allPeers.filter { peer in
            peer.isConnected &&
            peer.peerID != viewModel.meshService.myPeerID &&
            favoritesService.favorites[peer.noisePublicKey]?.isFavorite != true &&
            matchesSearch(peer.displayName + " " + peer.peerID.id)
        }
    }

    // Geohash participants (for location channels)
    private var geohashParticipants: [GeoPerson] {
        viewModel.visibleGeohashPeople().filter {
            matchesSearch($0.displayName + " " + $0.id)
        }
    }

    // Check if we're in a geohash channel
    private var isInGeohashChannel: Bool {
        if case .location = locationManager.selectedChannel {
            return true
        }
        return false
    }

    var body: some View {
        Group {
            // Current channel info
            Section {
                HStack {
                    Text(LanguageManager.shared.localizedString("people.current_channel"))
                        .font(.body)
                        .foregroundColor(textColor)
                    Spacer()
                    Text(channelDescription)
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)
                }

                HStack {
                    Text(LanguageManager.shared.localizedString("people.active_count"))
                        .font(.body)
                        .foregroundColor(textColor)
                    Spacer()
                    let activeText = String.localizedStringWithFormat(
                        NSLocalizedString("%d active", comment: "Active peer count"),
                        totalActiveCount
                    )
                    Text(activeText)
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)
                }
            }

            // Favorites section (always show if there are favorites)
            if !favoritePeers.isEmpty {
                Section(header: Text(LanguageManager.shared.localizedString("people.favorites"))) {
                    ForEach(favoritePeers, id: \.peerID) { peer in
                        meshPeerRow(for: peer, isFavorite: true)
                    }
                }
            }

            // Active section - show based on current channel
            // Tutorial note:
            // - In geohash channels, show both geohash users and nearby mesh users.
            // - In mesh channels, show only mesh users.
            if isInGeohashChannel {
                if !geohashParticipants.isEmpty {
                    Section(header: Text(LanguageManager.shared.localizedString("people.active"))) {
                        ForEach(geohashParticipants) { person in
                            geohashPersonRow(for: person)
                        }
                    }
                }

                if !otherActiveMeshPeers.isEmpty {
                    Section(header: Text(LanguageManager.shared.localizedString("people.nearby_mesh"))) {
                        ForEach(otherActiveMeshPeers, id: \.peerID) { peer in
                            meshPeerRow(for: peer, isFavorite: false)
                        }
                    }
                }
            } else {
                if !otherActiveMeshPeers.isEmpty {
                    Section(header: Text(LanguageManager.shared.localizedString("people.active"))) {
                        ForEach(otherActiveMeshPeers, id: \.peerID) { peer in
                            meshPeerRow(for: peer, isFavorite: false)
                        }
                    }
                }
            }

            let noActiveUsers = isInGeohashChannel
                ? (geohashParticipants.isEmpty && otherActiveMeshPeers.isEmpty && favoritePeers.isEmpty)
                : (otherActiveMeshPeers.isEmpty && favoritePeers.isEmpty)

            // Empty-state section appears when there are no rows after filtering.
            if noActiveUsers {
                Section {
                    HStack {
                        Spacer()
                        Text(
                            normalizedSearchText.isEmpty
                                ? LanguageManager.shared.localizedString("people.no_peers")
                                // Fallback text when filter removes all rows.
                                : "No matching people"
                        )
                        .font(.body)
                        .foregroundColor(secondaryTextColor)
                        Spacer()
                    }
                }
            }
        }
        .alert(
            LanguageManager.shared.localizedString("people.nostr_pm_title"),
            isPresented: $showNostrPMAlert
        ) {
            Button(LanguageManager.shared.localizedString("common.ok"), role: .cancel) {}
        } message: {
            Text(LanguageManager.shared.localizedString("people.nostr_pm_message"))
        }
    }

    @ViewBuilder
    private func meshPeerRow(for peer: BitchatPeer, isFavorite: Bool) -> some View {
        let nickname = viewModel.meshService.peerNickname(peerID: peer.peerID) ?? peer.peerID.id.prefix(8).uppercased()
        // Highlight currently opened private chat in iPad sidebar.
        let isSelected = selectedPrivatePeerID == peer.peerID

        HStack {
            Circle()
                .fill(peer.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(String(nickname))
                .font(.body)
                .foregroundColor(Color(peerSeed: "mesh:\(peer.peerID.id.lowercased())", isDark: colorScheme == .dark))
                .lineLimit(1)

            Spacer()

            Button(action: {
                // Star toggles persistent favorite state for quick access.
                viewModel.toggleFavorite(for: peer.peerID, nickname: String(nickname))
            }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)

            Image(systemName: "envelope.fill")
                .foregroundColor(secondaryTextColor)
                .font(.caption)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Theme.accent(colorScheme).opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .onTapGesture {
            // Delegate routing to parent container.
            // Parent decides: sheet (phone) or inline detail (iPad split view).
            onSelectPrivateChat(peer.peerID)
        }
    }

    @ViewBuilder
    private func geohashPersonRow(for person: GeoPerson) -> some View {
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            Text(person.displayName)
                .font(.body)
                .foregroundColor(Color(peerSeed: "nostr:\(person.id.lowercased())", isDark: colorScheme == .dark))
                .lineLimit(1)

            Spacer()

            Image(systemName: "envelope.fill")
                .foregroundColor(secondaryTextColor.opacity(0.5))
                .font(.caption)

            Text(LanguageManager.shared.localizedString("people.via_nostr"))
                .font(.caption2)
                .foregroundColor(secondaryTextColor.opacity(0.6))
        }
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .onTapGesture {
            selectedNostrPerson = person
            showNostrPMAlert = true
        }
    }
}

// MARK: - Private Chat Detail View

struct PrivateChatDetailView: View {
    let peerID: PeerID
    var onClose: (() -> Void)? = nil
    var endChatOnDisappear = false

    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool

    private var textColor: Color {
        Color.orange
    }

    private var secondaryTextColor: Color {
        textColor.opacity(0.8)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var peerNickname: String {
        viewModel.meshService.peerNickname(peerID: peerID) ?? peerID.id.prefix(8).uppercased()
    }

    private var messages: [BitchatMessage] {
        viewModel.privateChats[peerID] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages area auto-scrolls to bottom when new messages arrive.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(messages, id: \.id) { message in
                            privateMessageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                // Composer: same behavior in sheet mode and iPad inline mode.
                TextField(
                    "",
                    text: $messageText,
                    prompt: Text(LanguageManager.shared.localizedString("content.input.message_placeholder"))
                        .foregroundColor(secondaryTextColor.opacity(0.6))
                )
                .textFieldStyle(.plain)
                .font(.bitchatSystem(size: 15, design: .monospaced))
                .foregroundColor(textColor)
                .focused($isTextFieldFocused)
                .submitLabel(.send)
                .onSubmit { sendMessage() }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.7))
                )

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.bitchatSystem(size: 24))
                        .foregroundColor(textColor)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .hoverEffect(.highlight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
        }
        .background(backgroundColor)
        .navigationTitle("@\(peerNickname)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let onClose {
                // Optional close button is only shown when parent supplies onClose.
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundColor(textColor)
                    }
                    .hoverEffect(.highlight)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundColor(textColor)
                    }
                }
                #endif
            }
        }
        .onAppear {
            viewModel.markPrivateMessagesAsRead(from: peerID)
        }
        .onDisappear {
            // In iPad detail mode we explicitly end the active private session on navigation away.
            if endChatOnDisappear {
                viewModel.endPrivateChat()
            }
        }
    }

    @ViewBuilder
    private func privateMessageRow(_ message: BitchatMessage) -> some View {
        let isFromMe = message.sender == viewModel.nickname || message.sender.hasPrefix(viewModel.nickname + "#")

        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
            Text(message.content)
                .font(.bitchatSystem(size: 14, design: .monospaced))
                .foregroundColor(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFromMe ? textColor.opacity(0.2) : Color.gray.opacity(0.2))
                )

            Text(formatTime(message.timestamp))
                .font(.bitchatSystem(size: 10))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messageText = ""
        viewModel.sendPrivateMessage(trimmed, to: peerID)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Private Chat Sheet Wrapper

struct PrivateChatSheetView: View {
    let peerID: PeerID
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            // Reuse the same private chat UI in sheet mode and iPad inline detail.
            PrivateChatDetailView(
                peerID: peerID,
                onClose: {
                    // Close action: end session and dismiss modal.
                    viewModel.endPrivateChat()
                    dismiss()
                }
            )
            .environmentObject(viewModel)
        }
        .onDisappear {
            // Safety cleanup in case dismissal happens without close button.
            viewModel.endPrivateChat()
        }
    }
}

#Preview {
    PeopleTabView(selectedTab: .constant(.people))
        .environmentObject(ChatViewModel(keychain: KeychainManager(), idBridge: NostrIdentityBridge(), identityManager: SecureIdentityStateManager(KeychainManager())))
}
