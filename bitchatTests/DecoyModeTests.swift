//
// DecoyModeTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Testing
import Foundation
@testable import Gap_Mesh

// MARK: - CalculatorEngine Tests

struct CalculatorEngineTests {

    // MARK: - Basic Arithmetic

    @Test func initialDisplayIsZero() {
        let engine = CalculatorEngine()
        #expect(engine.displayText == "0")
    }

    @Test func singleDigitInput() {
        let engine = CalculatorEngine()
        engine.inputDigit("5")
        #expect(engine.displayText == "5")
    }

    @Test func multiDigitInput() {
        let engine = CalculatorEngine()
        engine.inputDigit("1")
        engine.inputDigit("2")
        engine.inputDigit("3")
        #expect(engine.displayText == "123")
    }

    @Test func additionWorks() {
        let engine = CalculatorEngine()
        engine.inputDigit("2")
        engine.inputOperator(.add)
        engine.inputDigit("3")
        engine.inputEquals()
        #expect(engine.displayText == "5")
    }

    @Test func subtractionWorks() {
        let engine = CalculatorEngine()
        engine.inputDigit("9")
        engine.inputOperator(.subtract)
        engine.inputDigit("4")
        engine.inputEquals()
        #expect(engine.displayText == "5")
    }

    @Test func multiplicationWorks() {
        let engine = CalculatorEngine()
        engine.inputDigit("6")
        engine.inputOperator(.multiply)
        engine.inputDigit("7")
        engine.inputEquals()
        #expect(engine.displayText == "42")
    }

    @Test func divisionWorks() {
        let engine = CalculatorEngine()
        engine.inputDigit("1")
        engine.inputDigit("0")
        engine.inputOperator(.divide)
        engine.inputDigit("4")
        engine.inputEquals()
        #expect(engine.displayText == "2.5")
    }

    @Test func divisionByZeroShowsError() {
        let engine = CalculatorEngine()
        engine.inputDigit("5")
        engine.inputOperator(.divide)
        engine.inputDigit("0")
        engine.inputEquals()
        #expect(engine.displayText == "Error")
    }

    // MARK: - Chained Operations

    @Test func chainedOperations() {
        let engine = CalculatorEngine()
        // 2 + 3 = 5, then + 4 = 9
        engine.inputDigit("2")
        engine.inputOperator(.add)
        engine.inputDigit("3")
        engine.inputOperator(.add)  // Triggers 2+3=5
        #expect(engine.displayText == "5")
        engine.inputDigit("4")
        engine.inputEquals()
        #expect(engine.displayText == "9")
    }

    // MARK: - Clear

    @Test func clearResetsEverything() {
        let engine = CalculatorEngine()
        engine.inputDigit("5")
        engine.inputOperator(.add)
        engine.inputDigit("3")
        engine.inputClear()
        #expect(engine.displayText == "0")
        #expect(engine.digitBuffer == "")
    }

    // MARK: - Decimal

    @Test func decimalInput() {
        let engine = CalculatorEngine()
        engine.inputDigit("3")
        engine.inputDecimal()
        engine.inputDigit("1")
        engine.inputDigit("4")
        #expect(engine.displayText == "3.14")
    }

    @Test func doubleDecimalIgnored() {
        let engine = CalculatorEngine()
        engine.inputDigit("3")
        engine.inputDecimal()
        engine.inputDecimal()
        engine.inputDigit("5")
        #expect(engine.displayText == "3.5")
    }

    // MARK: - Percent

    @Test func percentWorks() {
        let engine = CalculatorEngine()
        engine.inputDigit("5")
        engine.inputDigit("0")
        engine.inputPercent()
        #expect(engine.displayText == "0.5")
    }

    // MARK: - Negate

    @Test func negateWorks() {
        let engine = CalculatorEngine()
        engine.inputDigit("7")
        engine.inputNegate()
        #expect(engine.displayText == "-7")
    }

    @Test func negateZeroDoesNothing() {
        let engine = CalculatorEngine()
        engine.inputNegate()
        #expect(engine.displayText == "0")
    }

    // MARK: - PIN Detection via digitBuffer

    @Test func digitBufferAccumulatesDuringTyping() {
        let engine = CalculatorEngine()
        engine.inputDigit("1")
        engine.inputDigit("2")
        engine.inputDigit("3")
        engine.inputDigit("4")
        #expect(engine.digitBuffer == "1234")
    }

    @Test func digitBufferResetsOnOperator() {
        let engine = CalculatorEngine()
        engine.inputDigit("1")
        engine.inputDigit("2")
        engine.inputOperator(.add)
        #expect(engine.digitBuffer == "")
        engine.inputDigit("5")
        engine.inputDigit("6")
        #expect(engine.digitBuffer == "56")
    }

    @Test func inputEqualsReturnsDigitBuffer() {
        let engine = CalculatorEngine()
        engine.inputDigit("5")
        engine.inputOperator(.add)
        engine.inputDigit("1")
        engine.inputDigit("2")
        engine.inputDigit("3")
        engine.inputDigit("4")
        let buffer = engine.inputEquals()
        #expect(buffer == "1234")
    }

    @Test func inputEqualsResetsDigitBuffer() {
        let engine = CalculatorEngine()
        engine.inputDigit("4")
        engine.inputDigit("2")
        _ = engine.inputEquals()
        #expect(engine.digitBuffer == "")
    }

    @Test func digitBufferClearedOnClear() {
        let engine = CalculatorEngine()
        engine.inputDigit("9")
        engine.inputDigit("8")
        engine.inputClear()
        #expect(engine.digitBuffer == "")
    }

    @Test func pinDetectionAfterAddition() {
        // Simulate: user types 1+1=, then types 5678=
        // The buffer on the second = should be "5678"
        let engine = CalculatorEngine()
        engine.inputDigit("1")
        engine.inputOperator(.add)
        engine.inputDigit("1")
        _ = engine.inputEquals()  // result = 2, buffer was "1"

        // Now type the PIN
        engine.inputDigit("5")
        engine.inputDigit("6")
        engine.inputDigit("7")
        engine.inputDigit("8")
        let pinBuffer = engine.inputEquals()
        #expect(pinBuffer == "5678")
    }

    // MARK: - Display Limits

    @Test func displayLimitedTo12Characters() {
        let engine = CalculatorEngine()
        for _ in 0..<15 {
            engine.inputDigit("1")
        }
        #expect(engine.displayText.count <= 12)
    }

    // MARK: - Whole Number Formatting

    @Test func wholeNumberResultHasNoDecimal() {
        let engine = CalculatorEngine()
        engine.inputDigit("4")
        engine.inputOperator(.add)
        engine.inputDigit("6")
        engine.inputEquals()
        #expect(engine.displayText == "10")
        #expect(!engine.displayText.contains("."))
    }
}

// MARK: - DecoyModeManager PIN Logic Tests

struct DecoyPINTests {

    @Test func generatedPINIs4Digits() {
        let pin = DecoyModeManager.generateRandomPIN()
        #expect(pin.count == 4)
        #expect(Int(pin) != nil)
    }

    @Test func generatedPINInValidRange() {
        // Generate several and check all are 1000-9999
        for _ in 0..<100 {
            let pin = DecoyModeManager.generateRandomPIN()
            let value = Int(pin)!
            #expect(value >= 1000)
            #expect(value <= 9999)
        }
    }

    @Test func generatedPINsAreNotAllIdentical() {
        // Statistical check: 50 PINs should not all be the same
        var pins = Set<String>()
        for _ in 0..<50 {
            pins.insert(DecoyModeManager.generateRandomPIN())
        }
        #expect(pins.count > 1, "50 generated PINs should not all be identical")
    }
}
