//
// CalculatorButton.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// A single button in the calculator grid, styled to mimic the iOS Calculator app.
struct CalculatorButton: View {
    enum Style {
        case number     // Dark gray
        case operation  // Orange
        case function   // Light gray
    }

    let label: String
    let style: Style
    let isWide: Bool
    let action: () -> Void

    init(_ label: String, style: Style = .number, isWide: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.style = style
        self.isWide = isWide
        self.action = action
    }

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        switch style {
        case .number:
            return colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85)
        case .operation:
            return Color.orange
        case .function:
            return colorScheme == .dark ? Color(white: 0.35) : Color(white: 0.72)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .number:
            return colorScheme == .dark ? .white : .black
        case .operation:
            return .white
        case .function:
            return colorScheme == .dark ? .white : .black
        }
    }

    var body: some View {
        Button(action: {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
            action()
        }) {
            Text(label)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(foregroundColor)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 64
                )
                .background(backgroundColor)
                .cornerRadius(32)
        }
        .buttonStyle(.plain)
    }
}
