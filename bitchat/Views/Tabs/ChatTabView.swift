//
//  ChatTabView.swift
//  
//
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Tor

struct ChatTabView: View {
    // MARK: Overview
    // This view renders public chat plus its composer/actions.
    // Private chat entry is adaptive:
    // - iPad regular width: ask parent to route inline in split detail.
    // - compact/phone: open modal private chat sheet.
    @Binding var selectedTab: MainTabView.Tab
    // On iPad, parent split view injects this so we route private chats inline.
    var onRequestPrivateChat: ((PeerID) -> Void)? = nil
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var locationManager = LocationChannelManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // State from ContentView
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // Private Chat Sheet
    @State private var showPrivateChatSheet = false
    @State private var selectedPeerForChat: PeerID? = nil
    @State private var isAtBottom: Bool = true
    @State private var lastScrollTime: Date = .distantPast
    @State private var scrollThrottleTimer: Timer?
    @State private var autocompleteDebounceTimer: Timer?
    
    // Voice Recording
    @State private var recordingAlertMessage: String = ""
    @State private var showRecordingAlert = false
    @State private var isRecordingVoiceNote = false
    @State private var isPreparingVoiceNote = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var recordingStartDate: Date?
    
    // Media / Actions
    @State private var showMessageActions = false
    @State private var selectedMessageSender: String?
    @State private var selectedMessageSenderID: PeerID?
    @State private var expandedMessageIDs: Set<String> = []
    @State private var imagePreviewItem: PreviewImageItem? = nil
    
    // Windowing
    @State private var windowCount: Int = 300
    
    // Edit Name
    @State private var showingNameEditSheet = false
    @State private var editingName = ""
    
    // Image Picker
    #if os(iOS)
    @State private var showImagePicker = false
    @State private var showImagePickerOptions = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #else
    @State private var showMacImagePicker = false
    private var isPad: Bool { false }
    #endif
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Colors
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    private var textColor: Color {
        colorScheme == .dark ? Color.green : Color(red: 0, green: 0.5, blue: 0)
    }
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.green.opacity(0.8) : Color(red: 0, green: 0.5, blue: 0).opacity(0.8)
    }
    private var composerAccentColor: Color {
        // Use orange if private chat (though this view is currently mainly public)
        // or just default to text color
        textColor
    }
    
    // Connection status color
    private var connectionStatusColor: Color {
        switch locationManager.selectedChannel {
        case .mesh:
            let meshPeers = viewModel.allPeers.filter { $0.isConnected && $0.peerID != viewModel.meshService.myPeerID }
            return meshPeers.isEmpty ? .red : .green
        case .location:
            // For geohash channels, show Tor status - red if disconnected
            return TorManager.shared.isReady ? .green : .red
        }
    }
    
    // Check if Tor is disconnected while in geohash
    private var isGeohashDisconnected: Bool {
        if case .location = locationManager.selectedChannel {
            return !TorManager.shared.isReady
        }
        return false
    }
    
    // Current channel display text
    private var currentChannelText: String {
        switch locationManager.selectedChannel {
        case .mesh:
            return LanguageManager.shared.localizedString("channels.mesh")
        case .location(let ch):
            return "#\(ch.geohash)"
        }
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Step 1: header (channel + status + top actions).
            headerView
            
            Divider()
                .background(textColor.opacity(0.3))
            
            // Step 2: chat timeline + composer.
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    messagesList
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .background(backgroundColor)
                
                Divider()
                
                inputView
            }
        }
        .background(backgroundColor)
        // Sheet group:
        // - nickname editor
        // - media pickers
        // - private chat fallback sheet (compact layouts)
        .sheet(isPresented: $showingNameEditSheet) {
            editNameSheet
        }
        // Image Picker Options
        #if os(iOS)
        .confirmationDialog(
            LanguageManager.shared.localizedString("chat.photo_options"),
            isPresented: $showImagePickerOptions,
            titleVisibility: .visible
        ) {
            Button(LanguageManager.shared.localizedString("chat.take_photo")) {
                imagePickerSourceType = .camera
                showImagePicker = true
            }
            Button(LanguageManager.shared.localizedString("chat.choose_photo")) {
                imagePickerSourceType = .photoLibrary
                showImagePicker = true
            }
            Button(LanguageManager.shared.localizedString("common.cancel"), role: .cancel) {}
        }
        #endif
        // Image Picker Sheets
        #if os(iOS)
        .fullScreenCover(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSourceType) { image in
                showImagePicker = false
                if let image = image {
                    processAndSendImage(image)
                }
            }
            .environmentObject(viewModel)
            .ignoresSafeArea()
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: $showMacImagePicker) {
            MacImagePickerView { url in
                showMacImagePicker = false
                if let url = url {
                    processAndSendImage(at: url)
                }
            }
        }
        #endif
        #if os(iOS)
        // Image Preview
        .fullScreenCover(item: Binding<PreviewImageItem?>(
            get: { imagePreviewItem },
            set: { imagePreviewItem = $0 }
        )) { item in
            ImagePreviewView(url: item.url)
        }
        #else
        .sheet(item: Binding<PreviewImageItem?>(
            get: { imagePreviewItem },
            set: { imagePreviewItem = $0 }
        )) { item in
            ImagePreviewView(url: item.url)
        }
        #endif
        // Alerts
        .alert("Recording Error", isPresented: $showRecordingAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(recordingAlertMessage)
        })
        .confirmationDialog(
            selectedMessageSender.map { "@\($0)" } ?? String(localized: "content.actions.title"),
            isPresented: $showMessageActions,
            titleVisibility: .visible
        ) {
            messageActions
        }
        .sheet(isPresented: $showPrivateChatSheet) {
            if let peerID = selectedPeerForChat {
                PrivateChatSheetView(peerID: peerID)
                    .environmentObject(viewModel)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Gap Mesh logo (triple-tap to clear all data)
                Text(verbatim: "Gap Mesh/")
                    .font(.bitchatSystem(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor)
                    .onTapGesture(count: 3) {
                        // PANIC: Triple-tap to clear all data
                        viewModel.panicClearAllData()
                    }
                
                // Username (tap to edit)
                HStack(spacing: 0) {
                    Text(verbatim: "@")
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    
                    Text(viewModel.nickname)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editingName = viewModel.nickname
                    showingNameEditSheet = true
                }
                
                Spacer()
                
                // Channel badge - tappable to go to locations
                channelBadge
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            
            // Disconnection warning banner for geohash
            if isGeohashDisconnected {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(LanguageManager.shared.localizedString("chat.tor_disconnected_warning"))
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.9))
            }
        }
        .background(backgroundColor)
    }
    
    // Channel badge with prominent geohash display
    private var channelBadge: some View {
        Group {
            switch locationManager.selectedChannel {
            case .mesh:
                // Simple badge for mesh
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 8, height: 8)
                    Text(currentChannelText)
                        .font(.bitchatSystem(size: 14, design: .monospaced))
                        .foregroundColor(Color(hue: 0.60, saturation: 0.85, brightness: 0.82))
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedTab = .locations }
                
            case .location(let ch):
                // Prominent pill badge for geohash
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 8, height: 8)
                    Image(systemName: "location.fill")
                        .font(.caption)
                    Text("#\(ch.geohash)")
                        .font(.bitchatSystem(size: 14, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isGeohashDisconnected ? Color.red.opacity(0.8) : textColor)
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedTab = .locations }
            }
        }
    }
    
    // MARK: - Edit Name Sheet
    
    private var editNameSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text(LanguageManager.shared.localizedString("settings.change_username"))) {
                    #if os(iOS)
                    DeterministicTextField(
                        placeholder: LanguageManager.shared.localizedString("settings.enter_username"),
                        text: $editingName,
                        direction: .followsAppLanguage(LanguageManager.shared.currentLanguage),
                        autocorrectionType: .no,
                        autocapitalizationType: .none
                    )
                    .id("chat-name-input-\(LanguageManager.shared.currentLanguage.rawValue)")
                    #else
                    TextField(
                        LanguageManager.shared.localizedString("settings.enter_username"),
                        text: $editingName
                    )
                    .autocorrectionDisabled()
                    #endif
                }
            }
            .navigationTitle(LanguageManager.shared.localizedString("settings.change_username"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LanguageManager.shared.localizedString("common.cancel")) {
                        showingNameEditSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.shared.localizedString("common.save")) {
                        saveNewName()
                    }
                }
            }
        }
        .applyLanguageEnvironment(LanguageManager.shared)
        .id(LanguageManager.shared.refreshID)
    }
    
    private func saveNewName() {
        let newName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != viewModel.nickname else {
            showingNameEditSheet = false
            return
        }
        viewModel.nickname = newName
        showingNameEditSheet = false
    }
    
    // MARK: - Message List
    
    private var messagesList: some View {
        let messages = viewModel.messages
        let currentWindowCount = windowCount
        let windowedMessages = Array(messages.suffix(currentWindowCount))
        
        let contextKey = "chat" // Simplified key for now
        
        let items: [MessageDisplayItem] = windowedMessages.compactMap { message in
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return MessageDisplayItem(id: "\(contextKey)|\(message.id)", message: message)
        }
        
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        messageRow(for: item.message)
                            .onAppear {
                                if item.message.id == windowedMessages.last?.id {
                                    isAtBottom = true
                                }
                                if item.message.id == windowedMessages.first?.id && messages.count > windowedMessages.count {
                                    // Expand window logic
                                    let newCount = min(messages.count, windowCount + TransportConfig.uiWindowStepCount)
                                    if newCount != windowCount {
                                        windowCount = newCount
                                        let preserveID = "\(contextKey)|\(item.message.id)"
                                        DispatchQueue.main.async { proxy.scrollTo(preserveID, anchor: .top) }
                                    }
                                }
                            }
                            .onDisappear {
                                if item.message.id == windowedMessages.last?.id {
                                    isAtBottom = false
                                }
                            }
                            .onTapGesture {
                                if item.message.sender != "system" {
                                    messageText = "@\(item.message.sender) "
                                    isTextFieldFocused = true
                                }
                            }
                            .contextMenu {
                                // Mention
                                Button {
                                    messageText = "@\(item.message.sender) "
                                    isTextFieldFocused = true
                                } label: {
                                    Label(LanguageManager.shared.localizedString("content.actions.mention"), systemImage: "at")
                                }
                                
                                // Copy message
                                Button {
                                    #if os(iOS)
                                    UIPasteboard.general.string = item.message.content
                                    #else
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.message.content, forType: .string)
                                    #endif
                                } label: {
                                    Label(LanguageManager.shared.localizedString("content.message.copy"), systemImage: "doc.on.doc")
                                }
                                
                                Divider()
                                
                                // Private Message
                                if item.message.sender != "system" && item.message.sender != viewModel.nickname {
                                    Button {
                                        if let peerID = viewModel.peerIDForNickname(item.message.sender) {
                                            openPrivateChat(peerID)
                                        }
                                    } label: {
                                        Label(LanguageManager.shared.localizedString("content.actions.direct_message"), systemImage: "envelope.fill")
                                    }
                                    
                                    // Favorite/Unfavorite
                                    Button {
                                        if let peerID = viewModel.peerIDForNickname(item.message.sender) {
                                            viewModel.toggleFavorite(for: peerID, nickname: item.message.sender)
                                        }
                                    } label: {
                                        let isFav = viewModel.isFavorite(item.message.sender)
                                        Label(
                                            isFav ? LanguageManager.shared.localizedString("content.actions.unfavorite") : LanguageManager.shared.localizedString("content.actions.favorite"),
                                            systemImage: isFav ? "star.slash.fill" : "star.fill"
                                        )
                                    }
                                }
                                
                                Divider()
                                
                                // Hug
                                if item.message.sender != "system" {
                                    Button {
                                        viewModel.sendMessage("/hug @\(item.message.sender)")
                                    } label: {
                                        Label(LanguageManager.shared.localizedString("content.actions.hug"), systemImage: "heart.fill")
                                    }
                                }
                                
                                // Slap
                                if item.message.sender != "system" {
                                    Button {
                                        viewModel.sendMessage("/slap @\(item.message.sender)")
                                    } label: {
                                        Label(LanguageManager.shared.localizedString("content.actions.slap"), systemImage: "hand.raised.fill")
                                    }
                                }
                                
                                Divider()
                                
                                // Block
                                if item.message.sender != "system" && item.message.sender != viewModel.nickname {
                                    Button(role: .destructive) {
                                        viewModel.sendMessage("/block \(item.message.sender)")
                                    } label: {
                                        Label(LanguageManager.shared.localizedString("content.actions.block"), systemImage: "nosign")
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: viewModel.messages.last?.id) { _, _ in
                if let last = items.last, isAtBottom || (messages.last?.sender == viewModel.nickname) {
                    // Scroll to bottom
                    DispatchQueue.main.async {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Input View
    
    private var inputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Autocomplete suggestions omitted for brevity, can add back if needed
            
            CommandSuggestionsView(
                messageText: $messageText,
                textColor: textColor,
                backgroundColor: backgroundColor,
                secondaryTextColor: secondaryTextColor
            )
            
            if isPreparingVoiceNote || isRecordingVoiceNote {
                recordingIndicator
            }
            
            HStack(alignment: .center, spacing: 4) {
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
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.7))
                )
                
                HStack(alignment: .center, spacing: 4) {
                    attachmentButton
                    sendOrMicButton
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(backgroundColor.opacity(0.95))
    }
    
    // MARK: - Buttons & Components
    
    private var attachmentButton: some View {
        #if os(iOS)
        Button(action: {
            showImagePickerOptions = true
        }) {
            Image(systemName: "camera.circle.fill")
                .font(.bitchatSystem(size: 24))
                .foregroundColor(composerAccentColor)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        #else
        Button(action: { showMacImagePicker = true }) {
            Image(systemName: "photo.circle.fill")
                .font(.bitchatSystem(size: 24))
                .foregroundColor(composerAccentColor)
        }
        #endif
    }
    
    private var sendOrMicButton: some View {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Group {
            if hasText {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.bitchatSystem(size: 24))
                        .foregroundColor(composerAccentColor)
                        .frame(width: 36, height: 36)
                }
                .hoverEffect(.highlight)
            } else {
                Image(systemName: "mic.circle.fill")
                    .font(.bitchatSystem(size: 24))
                    .foregroundColor((isRecordingVoiceNote || isPreparingVoiceNote) ? .red : composerAccentColor)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                    .hoverEffect(.highlight)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in startVoiceRecording() }
                            .onEnded { _ in finishVoiceRecording(send: true) }
                    )
            }
        }
    }
    
    private var recordingIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.red)
                .font(.bitchatSystem(size: 20))
            Text(formattedRecordingDuration())
                .font(.bitchatSystem(size: 13, design: .monospaced))
                .foregroundColor(.red)
            Spacer()
            Button(action: cancelVoiceRecording) {
                Image(systemName: "xmark.circle")
                    .font(.bitchatSystem(size: 18))
                    .foregroundColor(.red)
            }
            .hoverEffect(.highlight)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.15)))
    }
    
    // MARK: - Actions

    private func openPrivateChat(_ peerID: PeerID) {
        // iPad regular-width: delegate to parent so private chat opens in detail pane.
        if isPad, horizontalSizeClass == .regular, let onRequestPrivateChat {
            onRequestPrivateChat(peerID)
            return
        }

        // Phone/compact: keep existing modal sheet behavior.
        selectedPeerForChat = peerID
        viewModel.startPrivateChat(with: peerID)
        showPrivateChatSheet = true
    }
    
    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messageText = ""
        DispatchQueue.main.async {
            viewModel.sendMessage(trimmed)
        }
    }
    
    #if os(iOS)
    private func processAndSendImage(_ image: UIImage) {
        Task {
            do {
                let processedURL = try ImageUtils.processImage(image)
                await MainActor.run {
                    viewModel.sendImage(from: processedURL)
                }
            } catch {
                #if DEBUG
                print("Image processing failed: \(error)")
                #endif
            }
        }
    }
    #endif
    
    #if os(macOS)
    private func processAndSendImage(at url: URL) {
        Task {
            do {
                let processedURL = try ImageUtils.processImage(at: url)
                await MainActor.run {
                    viewModel.sendImage(from: processedURL)
                }
            } catch {
                #if DEBUG
                print("Image processing failed: \(error)")
                #endif
            }
        }
    }
    #endif
    
    // MARK: - Voice Recording
    
    private func startVoiceRecording() {
        // Guard against duplicate start events from repeated touch changes.
        guard !isRecordingVoiceNote && !isPreparingVoiceNote else { return }
        isPreparingVoiceNote = true
        
        Task { @MainActor in
            // Step 1: ask for microphone permission.
            let granted = await VoiceRecorder.shared.requestPermission()
            guard granted else {
                isPreparingVoiceNote = false
                recordingAlertMessage = "Microphone access denied"
                showRecordingAlert = true
                return
            }
            
            do {
                // Step 2: begin recording and start live duration timer.
                _ = try VoiceRecorder.shared.startRecording()
                recordingDuration = 0
                recordingStartDate = Date()
                recordingTimer?.invalidate()
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    if let start = recordingStartDate {
                        recordingDuration = Date().timeIntervalSince(start)
                    }
                }
                isPreparingVoiceNote = false
                isRecordingVoiceNote = true
            } catch {
                // Step 3: fail gracefully with user-facing alert.
                isPreparingVoiceNote = false
                isRecordingVoiceNote = false
                recordingAlertMessage = "Failed to start recording"
                showRecordingAlert = true
            }
        }
    }
    
    private func finishVoiceRecording(send: Bool) {
        // If a gesture ended while still requesting permission, cancel prep cleanly.
        guard isRecordingVoiceNote else {
            if isPreparingVoiceNote {
                 isPreparingVoiceNote = false
                 VoiceRecorder.shared.cancelRecording()
            }
            return
        }
        isRecordingVoiceNote = false
        recordingTimer?.invalidate()
        recordingStartDate = nil
        
        if send {
            // Save/send path for valid recordings.
            VoiceRecorder.shared.stopRecording { url in
                DispatchQueue.main.async {
                    if let url, recordingDuration >= 1.0 {
                        viewModel.sendVoiceNote(at: url)
                    } else {
                        // Cleanup short recording
                    }
                }
            }
        } else {
            VoiceRecorder.shared.cancelRecording()
        }
    }
    
    private func cancelVoiceRecording() {
        finishVoiceRecording(send: false)
    }
    
    private func formattedRecordingDuration() -> String {
        let total = Int(max(0, recordingDuration) * 1000)
        let min = total / 60000
        let sec = (total % 60000) / 1000
        let centi = (total % 1000) / 10
        return String(format: "%02d:%02d.%02d", min, sec, centi)
    }
    
    // MARK: - Message Row
    
    @ViewBuilder
    private func messageRow(for message: BitchatMessage) -> some View {
        if message.sender == "system" {
            Text(viewModel.formatMessageAsText(message, colorScheme: colorScheme))
                .font(.bitchatSystem(size: 12))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if let media = mediaAttachment(for: message) {
            mediaMessageRow(message: message, media: media)
        } else {
            textMessageRow(message)
        }
    }
    
    @ViewBuilder
    private func textMessageRow(_ message: BitchatMessage) -> some View {
        // Only show if message has actual content
        let trimmedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            // formatMessageAsText includes the <@sender> prefix, content, and timestamp
            Text(viewModel.formatMessageAsText(message, colorScheme: colorScheme))
        }
        // If empty, show nothing (EmptyView implied by @ViewBuilder)
    }
    
    @ViewBuilder
    private func mediaMessageRow(message: BitchatMessage, media: MessageMedia) -> some View {
        let isSending = message.deliveryStatus == .sending // Simplified check
        
        VStack(alignment: .leading) {
            Text(viewModel.formatMessageHeader(message, colorScheme: colorScheme))
            
            switch media {
            case .voice(let url):
                VoiceNoteView(
                    url: url,
                    isSending: isSending,
                    sendProgress: isSending ? 0.5 : nil, // Simplified progress
                    onCancel: nil
                )
            case .image(let url):
                BlockRevealImageView(
                    url: url,
                    revealProgress: isSending ? 0.5 : 1.0,
                    isSending: isSending,
                    onCancel: nil,
                    initiallyBlurred: false,
                    onOpen: { imagePreviewItem = PreviewImageItem(url: url) },
                    onDelete: nil
                )
                .frame(maxWidth: 240)
            }
        }
    }
    
    private enum MessageMedia {
        case voice(URL)
        case image(URL)
        var url: URL {
            switch self {
            case .voice(let u): return u
            case .image(let u): return u
            }
        }
    }
    
    private func mediaAttachment(for message: BitchatMessage) -> MessageMedia? {
        guard let filesDir = applicationFilesDirectory() else { return nil }
        
        func fileURL(_ prefix: String, _ sub: String) -> URL? {
            guard message.content.hasPrefix(prefix) else { return nil }
            let name = String(message.content.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let dir = message.sender == viewModel.nickname ? "\(sub)/outgoing" : "\(sub)/incoming"
            return filesDir.appendingPathComponent(dir).appendingPathComponent(name)
        }
        
        if let url = fileURL("[voice] ", "voicenotes") { return .voice(url) }
        if let url = fileURL("[image] ", "images") { return .image(url) }
        return nil
    }
    
    private func applicationFilesDirectory() -> URL? {
         try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("files", isDirectory: true)
    }
    
    private var messageActions: some View {
        Group {
            Button("content.actions.mention") {
                if let sender = selectedMessageSender {
                    messageText = "@\(sender) "
                    isTextFieldFocused = true
                }
            }
            if let id = selectedMessageSenderID {
                Button("content.actions.direct_message") {
                    openPrivateChat(id)
                }
            }
            Button("content.actions.hug") {
                if let sender = selectedMessageSender {
                     viewModel.sendMessage("/hug @\(sender)")
                }
            }
            Button("content.actions.block", role: .destructive) {
                if let sender = selectedMessageSender {
                    viewModel.sendMessage("/block \(sender)")
                }
            }
            Button("common.cancel", role: .cancel) {}
        }
    }
}

// Helpers
private struct MessageDisplayItem: Identifiable {
    let id: String
    let message: BitchatMessage
}

private struct PreviewImageItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
