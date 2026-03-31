//
//  MainTabView.swift
//
//

import SwiftUI

struct MainTabView: View {
    // MARK: Overview
    // This view is the app's root navigation shell.
    // Step 1: decide "phone tabs" vs "iPad split view" based on size class.
    // Step 2: keep selected destination and legacy tab state in sync.
    // Step 3: persist iPad destination so window/app restore returns user to same place.
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared

    @State private var selectedTab: Tab = .chat
    // iPad-specific destination state for NavigationSplitView detail routing.
    @State private var selectedIpadDestination: IpadDestination = .publicChat
    // Controls whether sidebar/detail/both columns are visible in split view.
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    // Sidebar People search query.
    @State private var peopleSearchText = ""
    @State private var showVerificationSheet = false
    @State private var showSidebarNameEditSheet = false
    @State private var sidebarEditingName = ""
    // Enables the transparent "tap outside to dismiss sidebar" overlay.
    @State private var allowTapToDismissSidebar = false

    // Persists iPad destination between launches and window restores.
    @SceneStorage("mainTab.iPadDestinationKind") private var persistedIpadDestinationKind = IpadDestinationPersistence.publicChat.rawValue
    @SceneStorage("mainTab.iPadDestinationPeerID") private var persistedIpadDestinationPeerID = ""

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #else
    private var isPad: Bool { false }
    #endif

    private var isRegularPadLayout: Bool {
        isPad && horizontalSizeClass == .regular
    }

    // Enum to identify tabs
    enum Tab {
        case chat
        case locations
        case people
        case settings
    }

    // High-level destinations shown in iPad split-view detail.
    enum IpadDestination: Hashable {
        case publicChat
        case locations
        case settings
        case privateChat(PeerID)
    }

    // Storage-safe representation of IpadDestination for SceneStorage.
    enum IpadDestinationPersistence: String {
        case publicChat
        case locations
        case settings
        case privateChat
    }

    // Convert runtime destination into primitive values that SceneStorage can store.
    static func persistPayload(for destination: IpadDestination) -> (kind: String, peerID: String) {
        switch destination {
        case .publicChat:
            return (IpadDestinationPersistence.publicChat.rawValue, "")
        case .locations:
            return (IpadDestinationPersistence.locations.rawValue, "")
        case .settings:
            return (IpadDestinationPersistence.settings.rawValue, "")
        case .privateChat(let peerID):
            return (IpadDestinationPersistence.privateChat.rawValue, peerID.id)
        }
    }

    // Restore runtime destination from persisted primitive values.
    static func destinationFromPersistence(kind: String, peerID: String) -> IpadDestination {
        switch IpadDestinationPersistence(rawValue: kind) {
        case .locations:
            return .locations
        case .settings:
            return .settings
        case .privateChat:
            let parsedPeerID = PeerID(str: peerID)
            guard !parsedPeerID.isEmpty else {
                return .publicChat
            }
            return .privateChat(parsedPeerID)
        case .publicChat, .none:
            return .publicChat
        }
    }

    static func tab(for destination: IpadDestination) -> Tab {
        switch destination {
        case .publicChat, .privateChat:
            return .chat
        case .locations:
            return .locations
        case .settings:
            return .settings
        }
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

    // Keep legacy Tab selection and iPad destination selection in sync.
    private var iPadTabSelectionBinding: Binding<Tab> {
        Binding(
            get: { Self.tab(for: selectedIpadDestination) },
            set: { tab in
                selectedTab = tab
                switch tab {
                case .chat, .people:
                    selectedIpadDestination = .publicChat
                case .locations:
                    selectedIpadDestination = .locations
                case .settings:
                    selectedIpadDestination = .settings
                }
            }
        )
    }

    var body: some View {
        Group {
            // iPad regular-width gets split-view navigation; everything else keeps tab UI.
            if isRegularPadLayout {
                ipadSplitView
            } else {
                phoneTabView
            }
        }
        #if os(iOS)
        .overlay(
            TripleTapOverlay {
                viewModel.panicClearAllData()
            }
        )
        #endif
        .onAppear {
            // Restore saved UI routing and any deferred navigation intents.
            // This is intentionally done in this order:
            // 1) seed edit sheet with current nickname,
            // 2) restore last iPad destination if available,
            // 3) apply special one-time settings redirect from decoy flow,
            // 4) sync sidebar outside-tap dismiss behavior.
            sidebarEditingName = viewModel.nickname
            restoreIpadDestinationIfNeeded()
            applyDeferredSettingsNavigationIfNeeded()
            syncSidebarDismissState()
        }
        .onChange(of: selectedIpadDestination) { _, newDestination in
            // Whenever iPad destination changes, we:
            // 1) persist it for restoration
            // 2) mirror the equivalent top-level tab selection.
            persist(destination: newDestination)
            selectedTab = Self.tab(for: newDestination)
        }
        .onChange(of: splitVisibility) { _, _ in
            syncSidebarDismissState()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            syncSidebarDismissState()
        }
        .sheet(isPresented: $showVerificationSheet) {
            VerificationSheetView(isPresented: $showVerificationSheet)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showSidebarNameEditSheet) {
            sidebarNameEditSheet
        }
    }

    private var phoneTabView: some View {
        // Compact layout keeps the familiar tab experience.
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


            if !isPad {
                PeopleTabView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(
                            LanguageManager.shared.localizedString("tabs.people"),
                            systemImage: "person.2.fill"
                        )
                    }
                    .tag(Tab.people)
                    .badge(peopleCount > 0 ? peopleCount : 0)
            }

            SettingsTabView()
                .tabItem {
                    Label(
                        LanguageManager.shared.localizedString("tabs.settings"),
                        systemImage: "gearshape.fill"
                    )
                }
                .tag(Tab.settings)
        }
    }

    private var ipadSplitView: some View {
        // Regular-width iPad uses split-view:
        // - leading sidebar: app destinations + people sections
        // - detail pane: selected destination content.
        NavigationSplitView(columnVisibility: $splitVisibility) {
            List {
                Section {
                    // Editable identity row at top of sidebar.
                    sidebarIdentityRow

                    sidebarPrimaryRow(
                        title: LanguageManager.shared.localizedString("tabs.chat"),
                        systemImage: "bubble.left.and.bubble.right.fill",
                        destination: .publicChat,
                        keyboardShortcut: "1"
                    )

                    sidebarPrimaryRow(
                        title: LanguageManager.shared.localizedString("tabs.locations"),
                        systemImage: "location.north.fill",
                        destination: .locations,
                        keyboardShortcut: "2"
                    )

                    sidebarPrimaryRow(
                        title: LanguageManager.shared.localizedString("tabs.settings"),
                        systemImage: "gearshape.fill",
                        destination: .settings,
                        keyboardShortcut: ","
                    )
                }

                // Reused People sections also appear in sidebar to open private chat inline.
                PeopleListSections(
                    selectedPrivatePeerID: selectedPrivatePeerID,
                    searchText: peopleSearchText,
                    onSelectPrivateChat: { peerID in
                        openPrivateChat(peerID)
                    }
                )
                .environmentObject(viewModel)
            }
            .listStyle(.sidebar)
            .navigationTitle("Gap Mesh")
            .searchable(
                text: $peopleSearchText,
                placement: .sidebar,
                prompt: Text(LanguageManager.shared.localizedString("tabs.people"))
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showVerificationSheet = true }) {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .hoverEffect(.highlight)
                    .help("Verify")
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                }
            }
        } detail: {
            ipadDetailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var ipadDetailView: some View {
        ZStack {
            Group {
                // The currently selected destination decides what appears in detail pane.
                // Think of this like a router switch statement for iPad detail content.
                switch selectedIpadDestination {
                case .publicChat:
                    ChatTabView(
                        selectedTab: iPadTabSelectionBinding,
                        onRequestPrivateChat: { peerID in
                            openPrivateChat(peerID)
                        }
                    )
                    .id("ipad-public-chat")

                case .locations:
                    LocationsTabView(selectedTab: iPadTabSelectionBinding)
                        .id("ipad-locations")

                case .settings:
                    SettingsTabView()
                        .id("ipad-settings")

                case .privateChat(let peerID):
                    // Private chat is inline on iPad (not modal) to match split-view patterns.
                    PrivateChatDetailView(peerID: peerID, endChatOnDisappear: true)
                        .id("ipad-private-\(peerID.id)")
                        .onAppear {
                            if viewModel.selectedPrivateChatPeer != peerID {
                                viewModel.startPrivateChat(with: peerID)
                            }
                        }
                }
            }

            // Transparent tap catcher so users can dismiss sidebar by tapping detail area.
            if allowTapToDismissSidebar && splitVisibility == .all {
                Color.black
                    .opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        splitVisibility = .detailOnly
                        allowTapToDismissSidebar = false
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    private var sidebarIdentityRow: some View {
        // Tapping the username opens a sheet to edit nickname.
        Button(action: {
            sidebarEditingName = viewModel.nickname
            showSidebarNameEditSheet = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(Theme.legacyGreen(colorScheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(viewModel.nickname)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(LanguageManager.shared.localizedString("settings.change_username"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    private var sidebarNameEditSheet: some View {
        // Small focused form used by sidebar identity row.
        // Save behavior: ignore empty/whitespace-only names.
        NavigationStack {
            Form {
                Section(header: Text(LanguageManager.shared.localizedString("settings.change_username"))) {
                    #if os(iOS)
                    DeterministicTextField(
                        placeholder: LanguageManager.shared.localizedString("settings.enter_username"),
                        text: $sidebarEditingName,
                        direction: .followsAppLanguage(LanguageManager.shared.currentLanguage),
                        autocorrectionType: .no,
                        autocapitalizationType: .none
                    )
                    // Force field recreation on language changes to avoid stale UIKit input state.
                    .id("sidebar-name-input-\(LanguageManager.shared.currentLanguage.rawValue)")
                    #else
                    TextField(
                        LanguageManager.shared.localizedString("settings.enter_username"),
                        text: $sidebarEditingName
                    )
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    #endif
                }
            }
            .navigationTitle(LanguageManager.shared.localizedString("settings.change_username"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localizedString("common.cancel")) {
                        showSidebarNameEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localizedString("common.save")) {
                        let trimmed = sidebarEditingName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.nickname = trimmed
                        }
                        showSidebarNameEditSheet = false
                    }
                }
            }
        }
        .applyLanguageEnvironment(LanguageManager.shared)
        .id(LanguageManager.shared.refreshID)
    }

    @ViewBuilder
    private func sidebarPrimaryRow(
        title: String,
        systemImage: String,
        destination: IpadDestination,
        keyboardShortcut: KeyEquivalent
    ) -> some View {
        Button(action: {
            selectedIpadDestination = destination
        }) {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                Spacer()
                if selectedIpadDestination == destination {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.legacyGreen(colorScheme))
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .keyboardShortcut(keyboardShortcut, modifiers: [.command])
    }

    private var selectedPrivatePeerID: PeerID? {
        // Keep People highlight synced to currently shown private chat.
        if case .privateChat(let peerID) = selectedIpadDestination {
            return peerID
        }
        return viewModel.selectedPrivateChatPeer
    }

    private func openPrivateChat(_ peerID: PeerID) {
        // iPad opens private chat inline in detail pane.
        // We still notify the view model first so message state stays consistent.
        viewModel.startPrivateChat(with: peerID)
        selectedIpadDestination = .privateChat(peerID)
    }

    private func toggleSidebarVisibility() {
        if splitVisibility == .detailOnly {
            splitVisibility = .all
        } else {
            splitVisibility = .detailOnly
        }
        syncSidebarDismissState()
    }

    private func syncSidebarDismissState() {
        // Outside-tap dismissal is only valid when split view actually shows a sidebar.
        allowTapToDismissSidebar = isRegularPadLayout && splitVisibility == .all
    }

    private func persist(destination: IpadDestination) {
        // Save routing so app/window restore returns to same destination.
        let payload = Self.persistPayload(for: destination)
        persistedIpadDestinationKind = payload.kind
        persistedIpadDestinationPeerID = payload.peerID
    }

    private func restoreIpadDestinationIfNeeded() {
        // Restore persisted destination only on iPad.
        guard isPad else { return }

        // Parse and validate stored values before applying to state.
        // Invalid/empty peer IDs safely fall back to public chat.
        let restored = Self.destinationFromPersistence(
            kind: persistedIpadDestinationKind,
            peerID: persistedIpadDestinationPeerID
        )
        selectedIpadDestination = restored
        selectedTab = Self.tab(for: restored)
    }

    private func applyDeferredSettingsNavigationIfNeeded() {
        // If returning from decoy mode with "Go to Settings" selected,
        // auto-switch to the Settings surface so the icon picker opens.
        guard UserDefaults.standard.bool(forKey: "shouldOpenAppIconPicker") else { return }

        if isRegularPadLayout {
            selectedIpadDestination = .settings
        } else {
            selectedTab = .settings
        }
    }
}
