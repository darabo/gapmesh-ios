//
// DecoyPINOnboardingView.swift
// bitchat
//
// Standalone decoy PIN setup screen shown to existing users who updated
// the app before the calculator decoy feature existed.
//
// This screen is mandatory — the user cannot proceed to the main app
// until they have set up their decoy PIN. This prevents users from being
// trapped in the calculator decoy after a triple-tap panic wipe with
// no PIN to exit.
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// A full-screen, non-dismissable view that prompts existing users
/// to set up their decoy mode PIN after an app update.
///
/// Shown by `BitchatApp` when `onboarding_seen == true` but
/// `DecoyModeManager.shared.hasPIN == false`.
struct DecoyPINOnboardingView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @Environment(\.colorScheme) var colorScheme

    // PIN setup state
    @State private var generatedPIN: String = DecoyModeManager.generateRandomPIN()
    @State private var isCustomPINMode = false
    @State private var customPIN = ""
    @State private var confirmPIN = ""
    @State private var pinMismatch = false
    @State private var pinMemorized = false

    var body: some View {
        VStack(spacing: 0) {
            // "New Feature" banner at top
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.legacyGreen(colorScheme))

                Text("onboarding.decoy_update_banner")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.secondaryText(colorScheme))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            // Reusable PIN setup content
            DecoyPINSetupView(
                generatedPIN: $generatedPIN,
                isCustomPINMode: $isCustomPINMode,
                customPIN: $customPIN,
                confirmPIN: $confirmPIN,
                pinMismatch: $pinMismatch,
                pinMemorized: $pinMemorized
            )

            // Continue button
            Button(action: savePINAndContinue) {
                HStack {
                    Text("onboarding.decoy_continue")
                        .fontWeight(.semibold)
                    Image(systemName: "checkmark")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.legacyGreen(colorScheme))
                .foregroundColor(.white)
                .cornerRadius(Theme.CornerRadius.medium)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .disabled(!pinMemorized)
            .opacity(pinMemorized ? 1.0 : 0.5)
        }
        .background(Theme.background(colorScheme))
        .interactiveDismissDisabled()
    }

    private func savePINAndContinue() {
        if isCustomPINMode {
            if customPIN != confirmPIN {
                pinMismatch = true
                return
            }
            DecoyModeManager.shared.setPIN(customPIN)
        } else {
            DecoyModeManager.shared.setPIN(generatedPIN)
        }
        // The PIN is now saved in Keychain.
        // setPIN() sets hasPINConfigured = true (a @Published property),
        // which causes BitchatApp's root view to re-evaluate and switch
        // to MainTabView.
        
        // Start services that were deferred while the PIN wasn't configured.
        // These are the same calls made by OnboardingView.completeOnboarding()
        // and BitchatApp.onAppear — they are safe to call multiple times.
        viewModel.startServices()
        NetworkActivationService.shared.start()
        GeohashPresenceService.shared.start()
    }
}
