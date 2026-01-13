//
//  MainTabView.swift
//  bitchat
//
//  Created by Unlicense
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @State private var selectedTab: Tab = .chat
    
    // Enum to identify tabs
    enum Tab {
        case chat
        case locations
        case people
        case settings
    }
    
    // Compute people count for badge
    private var peopleCount: Int {
        switch locationManager.selectedChannel {
        case .mesh:
            return viewModel.allPeers.filter { $0.isConnected && $0.peerID != viewModel.meshService.myPeerID }.count
        case .location(let ch):
            return viewModel.geohashParticipantCount(for: ch.geohash)
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ChatTabView(selectedTab: $selectedTab)
                .tabItem {
                    Label(
                        LanguageManager.shared.localizedString("tabs.chat"),
                        systemImage: "bubble.left.and.bubble.right.fill"
                    )
                }
                .tag(Tab.chat)
            
            LocationsTabView(selectedTab: $selectedTab)
                .tabItem {
                    Label(
                        LanguageManager.shared.localizedString("tabs.locations"),
                        systemImage: "location.north.fill"
                    )
                }
                .tag(Tab.locations)
            
            PeopleTabView(selectedTab: $selectedTab)
                .tabItem {
                    Label(
                        LanguageManager.shared.localizedString("tabs.people"),
                        systemImage: "person.2.fill"
                    )
                }
                .tag(Tab.people)
                .badge(peopleCount > 0 ? peopleCount : 0)
            
            SettingsTabView()
                .tabItem {
                    Label(
                        LanguageManager.shared.localizedString("tabs.settings"),
                        systemImage: "gearshape.fill"
                    )
                }
                .tag(Tab.settings)
        }
        .accentColor(Color.green) // Global accent color to match "Gap Mesh" branding style
        .onAppear {
            // Ensure view model is ready if needed
        }
    }
}
