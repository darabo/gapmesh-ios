//
// CalculatorDecoyView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// A fully functional calculator that serves as a decoy after the emergency
/// data wipe. The user exits decoy mode by typing their PIN and pressing `=`.
///
/// The calculator works correctly for all inputs — it is indistinguishable
/// from a real calculator app to a casual observer.
struct CalculatorDecoyView: View {
    @ObservedObject private var decoyManager = DecoyModeManager.shared
    @StateObject private var engine = CalculatorEngine()
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        colorScheme == .dark ? .black : Color(white: 0.96)
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Display
            HStack {
                Spacer()
                Text(engine.displayText)
                    .font(.system(size: displayFontSize, weight: .light, design: .default))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            // Button grid
            VStack(spacing: 12) {
                // Row 1: C, +/-, %, /
                HStack(spacing: 12) {
                    CalculatorButton("C", style: .function) { engine.inputClear() }
                    CalculatorButton("+/-", style: .function) { engine.inputNegate() }
                    CalculatorButton("%", style: .function) { engine.inputPercent() }
                    CalculatorButton("/", style: .operation) { engine.inputOperator(.divide) }
                }

                // Row 2: 7, 8, 9, x
                HStack(spacing: 12) {
                    CalculatorButton("7") { engine.inputDigit("7") }
                    CalculatorButton("8") { engine.inputDigit("8") }
                    CalculatorButton("9") { engine.inputDigit("9") }
                    CalculatorButton("x", style: .operation) { engine.inputOperator(.multiply) }
                }

                // Row 3: 4, 5, 6, -
                HStack(spacing: 12) {
                    CalculatorButton("4") { engine.inputDigit("4") }
                    CalculatorButton("5") { engine.inputDigit("5") }
                    CalculatorButton("6") { engine.inputDigit("6") }
                    CalculatorButton("-", style: .operation) { engine.inputOperator(.subtract) }
                }

                // Row 4: 1, 2, 3, +
                HStack(spacing: 12) {
                    CalculatorButton("1") { engine.inputDigit("1") }
                    CalculatorButton("2") { engine.inputDigit("2") }
                    CalculatorButton("3") { engine.inputDigit("3") }
                    CalculatorButton("+", style: .operation) { engine.inputOperator(.add) }
                }

                // Row 5: 0 (wide), ., =
                GeometryReader { geo in
                    let spacing: CGFloat = 12
                    let totalSpacing = spacing * 3 // 3 gaps in 4-column layout
                    let colWidth = (geo.size.width - totalSpacing) / 4
                    let wideWidth = colWidth * 2 + spacing // 0 button spans 2 columns

                    HStack(spacing: spacing) {
                        CalculatorButton("0") { engine.inputDigit("0") }
                            .frame(width: wideWidth)
                        CalculatorButton(".") { engine.inputDecimal() }
                            .frame(width: colWidth)
                        CalculatorButton("=", style: .operation) { handleEquals() }
                            .frame(width: colWidth)
                    }
                }
                .frame(height: 64)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .background(bgColor.ignoresSafeArea())
    }

    // MARK: - PIN Detection

    private func handleEquals() {
        let buffer = engine.inputEquals()
        // Check if the typed digits match the stored PIN
        if decoyManager.isCorrectPIN(buffer) {
            decoyManager.deactivateDecoy()
        }
    }

    private var displayFontSize: CGFloat {
        let length = engine.displayText.count
        if length > 9 { return 48 }
        if length > 7 { return 56 }
        return 72
    }
}
