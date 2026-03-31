//
//  LocationsTabView.swift
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LocationsTabView: View {
    // MARK: Overview
    // This screen has three jobs:
    // 1) Show available location channels (mesh, bookmarks, recent, nearby),
    // 2) Let user join a custom geohash safely (input validation),
    // 3) Handle location permission gating before entering geohash channels.
    @Binding var selectedTab: MainTabView.Tab
    // Shared language manager drives live locale/layout changes.
    @StateObject private var languageManager = LanguageManager.shared
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @ObservedObject private var bookmarks = GeohashBookmarksStore.shared
    @State private var customGeohash = ""
    @State private var geohashError: String? = nil
    @State private var showMapPicker = false
    @State private var showLocationPermissionAlert = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #else
    private var isPad: Bool { false }
    #endif
    
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    // Recent channels that aren't in nearby or bookmarks
    private var filteredRecentChannels: [String] {
        let nearbyGeohashes = Set(locationManager.availableChannels.map { $0.geohash })
        let bookmarkedGeohashes = Set(bookmarks.bookmarks)
        return locationManager.recentChannels.filter { geohash in
            !nearbyGeohashes.contains(geohash) && !bookmarkedGeohashes.contains(geohash)
        }
    }
    
    var body: some View {
        NavigationStack {
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
                    
                    // Recent/Custom Channels (teleported geohashes)
                    if !filteredRecentChannels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LanguageManager.shared.localizedString("channels.recent"))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 1) {
                                ForEach(filteredRecentChannels, id: \.self) { geohash in
                                    recentChannelRow(for: geohash)
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
                            #if os(iOS)
                            // UIKit-backed field is used here because runtime language switching
                            // can leave SwiftUI TextField in stale RTL/LTR alignment states.
                            // This wrapper lets us force absolute alignment every update.
                            DeterministicTextField(
                                placeholder: LanguageManager.shared.localizedString("channels.enter_geohash"),
                                text: $customGeohash,
                                direction: .followsAppLanguage(languageManager.currentLanguage),
                                onSubmit: joinCustomGeohash,
                                keyboardType: .asciiCapable,
                                returnKeyType: .done,
                                autocorrectionType: .no,
                                autocapitalizationType: .none
                            )
                            // Recreate field when language changes to avoid any stale UIKit text state.
                            .id("geohash-input-\(languageManager.currentLanguage.rawValue)")
                            .padding(12)
                            .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                            .cornerRadius(12)
                            #else
                            TextField(
                                LanguageManager.shared.localizedString("channels.enter_geohash"),
                                text: $customGeohash
                            )
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(languageManager.currentLanguage == .farsi ? .trailing : .leading)
                            .autocorrectionDisabled()
                            .onSubmit {
                                joinCustomGeohash()
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                            .cornerRadius(12)
                            #endif
                            
                            Button(action: joinCustomGeohash) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(textColor)
                            }
                        }
                        
                        #if os(iOS)
                        Button(action: {
                            guard canEnterGeohashChannels() else {
                                return
                            }
                            showMapPicker = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "map")
                                    .font(.body)
                                Text(LanguageManager.shared.localizedString("map_picker.pick_on_map"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(textColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        #endif

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
                                .foregroundColor(locationManager.isLocationUserEnabled ? textColor : .gray)
                            
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
                            
                            Toggle("", isOn: $locationManager.isLocationUserEnabled)
                                .labelsHidden()
                                .tint(textColor)
                                .onChange(of: locationManager.isLocationUserEnabled) { _, newValue in
                                    if newValue {
                                        if locationManager.permissionState == .denied {
                                            #if os(iOS)
                                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                                UIApplication.shared.open(url)
                                            }
                                            #endif
                                            DispatchQueue.main.async { locationManager.isLocationUserEnabled = false }
                                        } else {
                                            locationManager.enableLocationChannels()
                                        }
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
            #if os(iOS)
            // Keep nav bar available on iPad split view, hide it on phone-style presentation.
            .navigationBarHidden(!(isPad && horizontalSizeClass == .regular))
            #endif
            #if os(iOS)
            .fullScreenCover(isPresented: $showMapPicker) {
                GeohashMapPicker(isPresented: $showMapPicker) { geohash in
                    if selectGeohashChannel(geohash) {
                        selectedTab = .chat
                    }
                }
            }
            #endif
        }
        .alert("Location Permission Required", isPresented: $showLocationPermissionAlert) {
            switch locationManager.permissionState {
            case .notDetermined:
                Button("Enable Location") {
                    locationManager.enableLocationChannels()
                }
            case .denied, .restricted:
                Button("Open Settings") {
                    openLocationAppSettings()
                }
            case .authorized:
                EmptyView()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To join geohash channels, enable location access for Gap Mesh.")
        }
        // Rebuild view tree when language changes so all labels/placeholders refresh.
        .id(languageManager.refreshID)
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
            if selectGeohashChannel(geohash) {
                selectedTab = .chat
            }
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
            if selectGeohashChannel(channel.geohash) {
                selectedTab = .chat
            }
        }
    }
    
    private func recentChannelRow(for geohash: String) -> some View {
        let level = GeohashChannelLevel.levelForGeohashLength(geohash.count)
        let peerCount = viewModel.geohashParticipantCount(for: geohash)
        let isBookmarked = bookmarks.bookmarks.contains(geohash)
        let isSelected = isChannelSelected(geohash)
        
        return HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundColor(.orange)
            
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
            
            // Bookmark button
            Button(action: { bookmarks.toggle(geohash) }) {
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
            if selectGeohashChannel(geohash) {
                selectedTab = .chat
            }
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
    
    @discardableResult
    private func selectGeohashChannel(_ geohash: String) -> Bool {
        guard canEnterGeohashChannels() else {
            return false
        }
        let level = GeohashChannelLevel.levelForGeohashLength(geohash.count)
        let channel = GeohashChannel(level: level, geohash: geohash)
        locationManager.select(.location(channel))
        return true
    }
    
    private func joinCustomGeohash() {
        // Step 1: normalize user input so validation is deterministic.
        let input = customGeohash.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = Set("0123456789bcdefghjkmnpqrstuvwxyz")
        
        // Step 2: basic empty check.
        guard !input.isEmpty else {
            geohashError = LanguageManager.shared.localizedString("channels.error_empty")
            return
        }
        
        // Step 3: enforce supported geohash length range.
        guard (2...12).contains(input.count) else {
            geohashError = LanguageManager.shared.localizedString("channels.error_length")
            return
        }
        
        // Step 4: enforce valid base32 geohash character set.
        guard input.allSatisfy({ allowed.contains($0) }) else {
            geohashError = LanguageManager.shared.localizedString("channels.error_invalid")
            return
        }
        
        // Step 5: clear local input state and switch channel.
        geohashError = nil
        customGeohash = ""
        if selectGeohashChannel(input) {
            // Switch to chat tab only when channel switch succeeds.
            selectedTab = .chat
        }
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

    private func canEnterGeohashChannels() -> Bool {
        // Geohash channels depend on location authorization. If missing, we show
        // a prompt so users can grant access instead of silently failing to join.
        if locationManager.permissionState == .authorized {
            return true
        }
        showLocationPermissionAlert = true
        return false
    }

    private func openLocationAppSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
