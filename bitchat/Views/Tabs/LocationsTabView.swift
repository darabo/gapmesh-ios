//
//  LocationsTabView.swift
//  bitchat
//
//  Created by Unlicense
//

import SwiftUI

struct LocationsTabView: View {
    @Binding var selectedTab: MainTabView.Tab
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @ObservedObject private var bookmarks = GeohashBookmarksStore.shared
    @State private var customGeohash = ""
    @State private var geohashError: String? = nil
    @State private var locationServicesEnabled = true
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header title
                    Text(LanguageManager.shared.localizedString("channels.title"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Description blurb
                    Text(LanguageManager.shared.localizedString("channels.description"))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    
                    // Mesh Network Section
                    VStack(spacing: 0) {
                        meshNetworkRow
                            .padding()
                            .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                    }
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .onTapGesture {
                        locationManager.select(.mesh)
                        selectedTab = .chat
                    }
                    
                    // Bookmarked Channels
                    if !bookmarks.bookmarks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LanguageManager.shared.localizedString("channels.bookmarks"))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 1) {
                                ForEach(Array(bookmarks.bookmarks).sorted(), id: \.self) { geohash in
                                    bookmarkedChannelRow(for: geohash)
                                        .padding()
                                        .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                                }
                            }
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Nearby Channels
                    if !locationManager.availableChannels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LanguageManager.shared.localizedString("channels.nearby"))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 1) {
                                ForEach(locationManager.availableChannels, id: \.geohash) { channel in
                                    nearbyChannelRow(for: channel)
                                        .padding()
                                        .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                                }
                            }
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Custom Geohash
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LanguageManager.shared.localizedString("channels.custom_geohash_place"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 4)
                        
                        HStack {
                            TextField(
                                LanguageManager.shared.localizedString("channels.enter_geohash"),
                                text: $customGeohash
                            )
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .submitLabel(SubmitLabel.done)
                            #endif
                            .onSubmit {
                                joinCustomGeohash()
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                            .cornerRadius(12)
                            
                            Button(action: joinCustomGeohash) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(textColor)
                            }
                        }
                        
                        if let error = geohashError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Location Services Toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LanguageManager.shared.localizedString("settings.location").uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 4)
                        
                        HStack {
                            Image(systemName: "location.fill")
                                .font(.system(size: 20))
                                .foregroundColor(locationServicesEnabled ? textColor : .gray)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LanguageManager.shared.localizedString("settings.location"))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Text(LanguageManager.shared.localizedString("settings.location_description"))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $locationServicesEnabled)
                                .labelsHidden()
                                .tint(textColor)
                                .onChange(of: locationServicesEnabled) { newValue in
                                    if newValue {
                                        locationManager.enableLocationChannels()
                                    } else {
                                        locationManager.select(.mesh)
                                    }
                                }
                        }
                        .padding()
                        .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
            .background(backgroundColor)
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Rows
    
    private var meshNetworkRow: some View {
        let peerCount = viewModel.allPeers.filter { $0.isConnected && $0.peerID != viewModel.meshService.myPeerID }.count
        let isSelected = locationManager.selectedChannel.isMesh
        
        return HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .foregroundColor(textColor)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(LanguageManager.shared.localizedString("channels.mesh_title"))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(textColor)
                    
                    Text("(\(peerCount) \(LanguageManager.shared.localizedString("channels.people")))")
                        .font(.body)
                        .foregroundColor(textColor)
                }
                
                Text(LanguageManager.shared.localizedString("channels.mesh_subtitle"))
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }
            
            Spacer()
            
            // Red/green status dot
            Circle()
                .fill(peerCount > 0 ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(textColor)
            }
        }
        .contentShape(Rectangle())
    }
    
    private func bookmarkedChannelRow(for geohash: String) -> some View {
        let level = GeohashChannelLevel.levelForGeohashLength(geohash.count)
        let peerCount = viewModel.geohashParticipantCount(for: geohash)
        let isSelected = isChannelSelected(geohash)
        
        return HStack {
            Image(systemName: channelIcon(for: level))
                .font(.title2)
                .foregroundColor(textColor)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("#\(geohash)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(textColor)
                    
                    if peerCount > 0 {
                        Text("\(peerCount) \(LanguageManager.shared.localizedString("channels.people"))")
                            .font(.caption)
                            .foregroundColor(secondaryTextColor)
                    }
                }
                
                Text(level.displayName)
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }
            
            Spacer()
            
            // Bookmark button (filled since it's bookmarked)
            Button(action: { bookmarks.toggle(geohash) }) {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(textColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectGeohashChannel(geohash)
            selectedTab = .chat
        }
    }
    
    private func nearbyChannelRow(for channel: GeohashChannel) -> some View {
        let peerCount = viewModel.geohashParticipantCount(for: channel.geohash)
        let isBookmarked = bookmarks.bookmarks.contains(channel.geohash)
        let isSelected = isChannelSelected(channel.geohash)
        
        return HStack {
            Image(systemName: channelIcon(for: channel.level))
                .font(.title2)
                .foregroundColor(textColor)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("#\(channel.geohash)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(textColor)
                    
                    if peerCount > 0 {
                        Text("\(peerCount) \(LanguageManager.shared.localizedString("channels.people"))")
                            .font(.caption)
                            .foregroundColor(secondaryTextColor)
                    }
                }
                
                Text(channel.level.displayName)
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }
            
            Spacer()
            
            // Bookmark button
            Button(action: { bookmarks.toggle(channel.geohash) }) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundColor(isBookmarked ? .yellow : .gray)
            }
            .buttonStyle(.plain)
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(textColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectGeohashChannel(channel.geohash)
            selectedTab = .chat
        }
    }
    
    // MARK: - Helpers
    
    private func isChannelSelected(_ geohash: String) -> Bool {
        if case .location(let ch) = locationManager.selectedChannel {
            return ch.geohash == geohash
        }
        return false
    }
    
    // MARK: - Actions
    
    private func selectGeohashChannel(_ geohash: String) {
        let level = GeohashChannelLevel.levelForGeohashLength(geohash.count)
        let channel = GeohashChannel(level: level, geohash: geohash)
        locationManager.select(.location(channel))
    }
    
    private func joinCustomGeohash() {
        let input = customGeohash.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = Set("0123456789bcdefghjkmnpqrstuvwxyz")
        
        guard !input.isEmpty else {
            geohashError = LanguageManager.shared.localizedString("channels.error_empty")
            return
        }
        
        guard (2...12).contains(input.count) else {
            geohashError = LanguageManager.shared.localizedString("channels.error_length")
            return
        }
        
        guard input.allSatisfy({ allowed.contains($0) }) else {
            geohashError = LanguageManager.shared.localizedString("channels.error_invalid")
            return
        }
        
        geohashError = nil
        customGeohash = ""
        selectGeohashChannel(input)
        
        // Switch to chat tab
        selectedTab = .chat
    }
    
    private func channelIcon(for level: GeohashChannelLevel) -> String {
        switch level {
        case .region: return "globe.americas"
        case .province: return "map"
        case .city: return "building.2.fill"
        case .neighborhood: return "building.fill"
        case .block: return "location.circle"
        case .building: return "house.fill"
        }
    }
}
