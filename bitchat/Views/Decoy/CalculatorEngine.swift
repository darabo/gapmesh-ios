//
// CalculatorEngine.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Pure calculator logic for the decoy calculator view.
/// Handles basic arithmetic (+, -, x, /) and tracks the raw digit buffer
/// for PIN detection when `=` is pressed.
final class CalculatorEngine: ObservableObject {
    enum Operation {
        case add, subtract, multiply, divide
    }

    @Published var displayText: String = "0"

    // Internal state
    private var accumulator: Double = 0
    private var pendingOperation: Operation?
    private var isTypingNumber = false
    private var lastInputWasOperator = false

    /// The raw digit sequence typed since last clear or operator press.
    /// Used by the decoy view to detect PIN entry on `=`.
    private(set) var digitBuffer: String = ""

    // MARK: - Input Methods

    func inputDigit(_ digit: String) {
        if isTypingNumber {
            // Prevent excessively long display
            guard displayText.count < 12 else { return }
            if displayText == "0" && digit != "." {
                displayText = digit
            } else {
                displayText += digit
            }
        } else {
            displayText = digit
            isTypingNumber = true
        }
        digitBuffer += digit
        lastInputWasOperator = false
    }

    func inputDecimal() {
        guard !displayText.contains(".") else { return }
        if !isTypingNumber {
            displayText = "0."
            isTypingNumber = true
        } else {
            displayText += "."
        }
        digitBuffer += "."
        lastInputWasOperator = false
    }

    func inputOperator(_ op: Operation) {
        if isTypingNumber && pendingOperation != nil {
            performCalculation()
        } else {
            accumulator = Double(displayText) ?? 0
        }
        pendingOperation = op
        isTypingNumber = false
        lastInputWasOperator = true
        digitBuffer = ""  // Reset buffer on operator press
    }

    /// Performs the pending calculation and returns the raw digit buffer
    /// that was typed before `=` was pressed (for PIN detection).
    @discardableResult
    func inputEquals() -> String {
        let buffer = digitBuffer
        if isTypingNumber {
            performCalculation()
        }
        pendingOperation = nil
        isTypingNumber = false
        digitBuffer = ""
        return buffer
    }

    func inputClear() {
        displayText = "0"
        accumulator = 0
        pendingOperation = nil
        isTypingNumber = false
        lastInputWasOperator = false
        digitBuffer = ""
    }

    func inputNegate() {
        guard let value = Double(displayText), value != 0 else { return }
        let negated = -value
        displayText = formatNumber(negated)
    }

    func inputPercent() {
        guard let value = Double(displayText) else { return }
        let result = value / 100.0
        displayText = formatNumber(result)
        isTypingNumber = false
    }

    // MARK: - Private

    private func performCalculation() {
        guard let op = pendingOperation,
              let currentValue = Double(displayText) else { return }

        var result: Double
        switch op {
        case .add:      result = accumulator + currentValue
        case .subtract: result = accumulator - currentValue
        case .multiply: result = accumulator * currentValue
        case .divide:
            guard currentValue != 0 else {
                displayText = "Error"
                accumulator = 0
                return
            }
            result = accumulator / currentValue
        }

        displayText = formatNumber(result)
        accumulator = result
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded(.towardZero) && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        // Limit decimal places for clean display
        let formatted = String(format: "%.8g", value)
        return formatted
    }
}
