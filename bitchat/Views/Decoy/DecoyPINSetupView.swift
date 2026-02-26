//
// DecoyPINSetupView.swift
// bitchat
//
// Reusable decoy mode PIN setup component.
// Used by both the initial onboarding flow (step 4) and the standalone
// post-update onboarding screen for existing users who don't have a PIN yet.
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// A reusable view that lets the user set up their decoy mode PIN.
///
/// Displays an explanation of how decoy/calculator mode works,
/// shows a randomly generated 4-digit PIN (or lets the user choose their own),
/// and requires the user to check a "I have memorized my PIN" box before proceeding.
///
/// The caller is responsible for providing the state bindings and the save action.
struct DecoyPINSetupView: View {
    @Binding var generatedPIN: String
    @Binding var isCustomPINMode: Bool
    @Binding var customPIN: String
    @Binding var confirmPIN: String
    @Binding var pinMismatch: Bool
    @Binding var pinMemorized: Bool

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer().frame(height: 40)

                // Header
                HStack {
                    Image(systemName: "number.square.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)

                    Text("onboarding.decoy_title")
                        .font(.title)
                        .fontWeight(.bold)
                }

                Text("onboarding.decoy_desc")
                    .font(.body)
                    .foregroundColor(Theme.secondaryText(colorScheme))

                // How it works card
                VStack(alignment: .leading, spacing: 12) {
                    Text("onboarding.decoy_how_title")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    FeaturePoint(icon: "hand.tap.fill", textKey: "onboarding.decoy_how_wipe")
                    FeaturePoint(icon: "function", textKey: "onboarding.decoy_how_calc")
                    FeaturePoint(icon: "key.fill", textKey: "onboarding.decoy_how_pin")
                    FeaturePoint(icon: "arrow.clockwise", textKey: "onboarding.decoy_how_persist")
                }
                .padding()
                .background(Theme.surface(colorScheme))
                .cornerRadius(Theme.CornerRadius.medium)

                // PIN display / entry card
                VStack(spacing: 16) {
                    Text("onboarding.decoy_pin_label")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if isCustomPINMode {
                        // Custom PIN entry mode
                        VStack(spacing: 12) {
                            SecureField(
                                String(localized: "onboarding.decoy_pin_label"),
                                text: $customPIN
                            )
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            #endif
                            .font(.system(.title2, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: customPIN) { _ in
                                pinMismatch = false
                                // Strip non-digits
                                customPIN = String(customPIN.filter { $0.isNumber }.prefix(8))
                            }

                            SecureField(
                                String(localized: "onboarding.decoy_pin_confirm"),
                                text: $confirmPIN
                            )
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            #endif
                            .font(.system(.title2, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: confirmPIN) { _ in
                                pinMismatch = false
                                confirmPIN = String(confirmPIN.filter { $0.isNumber }.prefix(8))
                            }

                            if pinMismatch {
                                Text("onboarding.decoy_pin_mismatch")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            Button(action: {
                                isCustomPINMode = false
                                pinMismatch = false
                            }) {
                                Label {
                                    Text("onboarding.decoy_use_random")
                                } icon: {
                                    Image(systemName: "dice.fill")
                                }
                                .font(.subheadline)
                                .foregroundColor(Theme.legacyGreen(colorScheme))
                            }
                        }
                    } else {
                        // Random PIN display mode
                        VStack(spacing: 16) {
                            // Large PIN display
                            HStack(spacing: 12) {
                                ForEach(Array(generatedPIN), id: \.self) { digit in
                                    Text(String(digit))
                                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                                        .frame(width: 52, height: 64)
                                        .background(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                                .fill(Theme.surface(colorScheme))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                                        .stroke(Theme.legacyGreen(colorScheme), lineWidth: 2)
                                                )
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity)

                            HStack(spacing: 24) {
                                Button(action: {
                                    generatedPIN = DecoyModeManager.generateRandomPIN()
                                }) {
                                    Label {
                                        Text("onboarding.decoy_generate_new")
                                    } icon: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(Theme.legacyGreen(colorScheme))
                                }

                                Button(action: {
                                    isCustomPINMode = true
                                    customPIN = ""
                                    confirmPIN = ""
                                    pinMemorized = false
                                }) {
                                    Label {
                                        Text("onboarding.decoy_choose_own")
                                    } icon: {
                                        Image(systemName: "pencil")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(Theme.legacyGreen(colorScheme))
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.97))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                                .stroke(Theme.legacyGreen(colorScheme).opacity(0.3), lineWidth: 1)
                        )
                )

                // Warning
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("onboarding.decoy_pin_warning")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(Theme.CornerRadius.medium)

                // Memorization checkbox
                Button(action: {
                    if isCustomPINMode {
                        // In custom mode, only allow if PINs are valid
                        if customPIN.count >= 4 && customPIN == confirmPIN {
                            pinMemorized.toggle()
                            pinMismatch = false
                        } else if customPIN.count >= 4 && customPIN != confirmPIN {
                            pinMismatch = true
                        }
                    } else {
                        pinMemorized.toggle()
                    }
                }) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: pinMemorized ? "checkmark.square.fill" : "square")
                            .font(.title2)
                            .foregroundColor(pinMemorized ? Theme.legacyGreen(colorScheme) : .gray)

                        Text("onboarding.decoy_memorized")
                            .font(.body)
                            .foregroundColor(Theme.primaryText(colorScheme))
                            .multilineTextAlignment(.leading)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                            .stroke(pinMemorized ? Theme.legacyGreen(colorScheme) : Color.gray.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Helper used by both DecoyPINSetupView and OnboardingView feature steps

/// A small icon + localized text row used in onboarding cards.
/// Declared `internal` so both OnboardingView and DecoyPINSetupView can use it.
struct FeaturePoint: View {
    let icon: String
    let textKey: LocalizedStringKey
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(Theme.legacyGreen(colorScheme))
                .frame(width: 24)

            Text(textKey)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
