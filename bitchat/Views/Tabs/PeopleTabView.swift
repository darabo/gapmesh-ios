//
//  PeopleTabView.swift
//  bitchat
//
//  Created by Unlicense
//

import SwiftUI

struct PeopleTabView: View {
    @Binding var selectedTab: MainTabView.Tab
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @ObservedObject private var favoritesService = FavoritesPersistenceService.shared
    @Environment(\.colorScheme) var colorScheme
    
    // State for private chat sheet
    @State private var showPrivateChatSheet = false
    @State private var selectedPeerForChat: PeerID? = nil
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
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
    
    // Favorite peers (online mesh peers)
    private var favoritePeers: [BitchatPeer] {
        viewModel.allPeers.filter { peer in
            peer.isConnected && 
            peer.peerID != viewModel.meshService.myPeerID &&
            favoritesService.favorites[peer.noisePublicKey]?.isFavorite == true
        }
    }
    
    // Non-favorite active mesh peers
    private var otherActiveMeshPeers: [BitchatPeer] {
        viewModel.allPeers.filter { peer in
            peer.isConnected && 
            peer.peerID != viewModel.meshService.myPeerID &&
            favoritesService.favorites[peer.noisePublicKey]?.isFavorite != true
        }
    }
    
    // Geohash participants (for location channels)
    private var geohashParticipants: [GeoPerson] {
        viewModel.visibleGeohashPeople()
    }
    
    // Check if we're in a geohash channel
    private var isInGeohashChannel: Bool {
        if case .location = locationManager.selectedChannel {
            return true
        }
        return false
    }
    
    var body: some View {
        NavigationView {
            List {
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
                if isInGeohashChannel {
                    // Show geohash participants
                    if !geohashParticipants.isEmpty {
                        Section(header: Text(LanguageManager.shared.localizedString("people.active"))) {
                            ForEach(geohashParticipants) { person in
                                geohashPersonRow(for: person)
                            }
                        }
                    }
                    
                    // Also show mesh peers if any
                    if !otherActiveMeshPeers.isEmpty {
                        Section(header: Text(LanguageManager.shared.localizedString("people.nearby_mesh"))) {
                            ForEach(otherActiveMeshPeers, id: \.peerID) { peer in
                                meshPeerRow(for: peer, isFavorite: false)
                            }
                        }
                    }
                } else {
                    // Mesh channel - show mesh peers
                    if !otherActiveMeshPeers.isEmpty {
                        Section(header: Text(LanguageManager.shared.localizedString("people.active"))) {
                            ForEach(otherActiveMeshPeers, id: \.peerID) { peer in
                                meshPeerRow(for: peer, isFavorite: false)
                            }
                        }
                    }
                }
                
                // No peers message
                let noActiveUsers = isInGeohashChannel 
                    ? (geohashParticipants.isEmpty && otherActiveMeshPeers.isEmpty && favoritePeers.isEmpty)
                    : (otherActiveMeshPeers.isEmpty && favoritePeers.isEmpty)
                
                if noActiveUsers {
                    Section {
                        HStack {
                            Spacer()
                            Text(LanguageManager.shared.localizedString("people.no_peers"))
                                .font(.body)
                                .foregroundColor(secondaryTextColor)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(LanguageManager.shared.localizedString("tabs.people"))
            .foregroundColor(textColor)
        }
        .sheet(isPresented: $showPrivateChatSheet) {
            if let peerID = selectedPeerForChat {
                PrivateChatSheetView(peerID: peerID)
                    .environmentObject(viewModel)
            }
        }
    }
    
    // MARK: - Rows
    
    private func meshPeerRow(for peer: BitchatPeer, isFavorite: Bool) -> some View {
        let nickname = viewModel.meshService.peerNickname(peerID: peer.peerID) ?? peer.peerID.id.prefix(8).uppercased()
        
        return HStack {
            // Status indicator
            Circle()
                .fill(peer.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            // Nickname
            Text(String(nickname))
                .font(.body)
                .foregroundColor(textColor)
                .lineLimit(1)
            
            Spacer()
            
            // Favorite button
            Button(action: {
                viewModel.toggleFavorite(for: peer.peerID, nickname: String(nickname))
            }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            
            // Private message icon
            Image(systemName: "envelope.fill")
                .foregroundColor(secondaryTextColor)
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Start private chat with this peer
            selectedPeerForChat = peer.peerID
            viewModel.startPrivateChat(with: peer.peerID)
            showPrivateChatSheet = true
        }
    }
    
    private func geohashPersonRow(for person: GeoPerson) -> some View {
        return HStack {
            // Status indicator (green = active in geohash)
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            
            // Display name
            Text(person.displayName)
                .font(.body)
                .foregroundColor(textColor)
                .lineLimit(1)
            
            Spacer()
            
            // Note: Geohash users can't be favorited or PM'd directly via mesh
            // They use Nostr-based identities
            Text(LanguageManager.shared.localizedString("people.via_nostr"))
                .font(.caption2)
                .foregroundColor(secondaryTextColor.opacity(0.6))
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Private Chat Sheet View

struct PrivateChatSheetView: View {
    let peerID: PeerID
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    private var textColor: Color {
        colorScheme == .dark ? Color.orange : Color.orange
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
        NavigationView {
            VStack(spacing: 0) {
                // Messages
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
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input
                HStack(spacing: 8) {
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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
            }
            .background(backgroundColor)
            .navigationTitle("@\(peerNickname)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { 
                        viewModel.endPrivateChat()
                        dismiss() 
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(textColor)
                    }
                }
            }
        }
        .onAppear {
            viewModel.markPrivateMessagesAsRead(from: peerID)
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

#Preview {
    PeopleTabView(selectedTab: .constant(.people))
        .environmentObject(ChatViewModel(keychain: KeychainManager(), idBridge: NostrIdentityBridge(), identityManager: SecureIdentityStateManager(KeychainManager())))
}
