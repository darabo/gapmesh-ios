//
// HexStringTests.swift
// GapTests
//
// Tests for hex string parsing in Data extension.
// This is free and unencumbered software released into the public domain.
//

import Testing
import Foundation
@testable import Gap_Mesh

@Suite("Hex String Parsing")
struct HexStringTests {

    // MARK: - Valid Hex Strings

    @Test func validHexString_lowercase() {
        let data = Data(hexString: "deadbeef")
        #expect(data != nil)
        #expect(data?.count == 4)
        #expect(data?[0] == 0xDE)
        #expect(data?[1] == 0xAD)
        #expect(data?[2] == 0xBE)
        #expect(data?[3] == 0xEF)
    }

    @Test func validHexString_uppercase() {
        let data = Data(hexString: "DEADBEEF")
        #expect(data != nil)
        #expect(data?.count == 4)
        #expect(data?[0] == 0xDE)
    }

    @Test func validHexString_mixedCase() {
        let data = Data(hexString: "DeAdBeEf")
        #expect(data != nil)
        #expect(data?.count == 4)
    }

    @Test func validHexString_allZeros() {
        let data = Data(hexString: "00000000")
        #expect(data != nil)
        #expect(data?.count == 4)
        #expect(data?.allSatisfy { $0 == 0 } == true)
    }

    @Test func validHexString_allFs() {
        let data = Data(hexString: "ffffffff")
        #expect(data != nil)
        #expect(data?.count == 4)
        #expect(data?.allSatisfy { $0 == 0xFF } == true)
    }

    // MARK: - 0x Prefix Handling

    @Test func hexString_with0xPrefix_lowercase() {
        let data = Data(hexString: "0xdeadbeef")
        #expect(data != nil)
        #expect(data?.count == 4)
        #expect(data?[0] == 0xDE)
    }

    @Test func hexString_with0XPrefix_uppercase() {
        let data = Data(hexString: "0XDEADBEEF")
        #expect(data != nil)
        #expect(data?.count == 4)
    }

    @Test func hexString_with0xPrefix_mixedCase() {
        let data = Data(hexString: "0xDeAdBeEf")
        #expect(data != nil)
        #expect(data?.count == 4)
    }

    // MARK: - Whitespace Handling

    @Test func hexString_withLeadingWhitespace() {
        let data = Data(hexString: "   deadbeef")
        #expect(data != nil)
        #expect(data?.count == 4)
    }

    @Test func hexString_withTrailingWhitespace() {
        let data = Data(hexString: "deadbeef   ")
        #expect(data != nil)
        #expect(data?.count == 4)
    }

    @Test func hexString_withBothWhitespace() {
        let data = Data(hexString: "  deadbeef  ")
        #expect(data != nil)
        #expect(data?.count == 4)
    }

    @Test func hexString_withWhitespaceAnd0xPrefix() {
        let data = Data(hexString: "  0xdeadbeef  ")
        #expect(data != nil)
        #expect(data?.count == 4)
    }

    // MARK: - Empty and Edge Cases

    @Test func hexString_empty() {
        let data = Data(hexString: "")
        #expect(data != nil)
        #expect(data?.isEmpty == true)
    }

    @Test func hexString_onlyWhitespace() {
        let data = Data(hexString: "   ")
        #expect(data != nil)
        #expect(data?.isEmpty == true)
    }

    @Test func hexString_only0xPrefix() {
        let data = Data(hexString: "0x")
        #expect(data != nil)
        #expect(data?.isEmpty == true)
    }

    @Test func hexString_twoByteSingle() {
        let data = Data(hexString: "ab")
        #expect(data != nil)
        #expect(data?.count == 1)
        #expect(data?[0] == 0xAB)
    }

    // MARK: - Invalid Hex Strings

    @Test func hexString_oddLength() {
        let data = Data(hexString: "abc")
        #expect(data == nil)
    }

    @Test func hexString_oddLengthWith0x() {
        let data = Data(hexString: "0xabc")
        #expect(data == nil)
    }

    @Test func hexString_invalidCharacters() {
        let data = Data(hexString: "ghij")
        #expect(data == nil)
    }

    @Test func hexString_mixedValidAndInvalid() {
        let data = Data(hexString: "abgh")
        #expect(data == nil)
    }

    @Test func hexString_specialCharacters() {
        let data = Data(hexString: "ab!@")
        #expect(data == nil)
    }

    // MARK: - Round-Trip Tests

    @Test func roundTrip_basic() {
        let original = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        let hexString = original.hexEncodedString()
        let roundTripped = Data(hexString: hexString)

        #expect(roundTripped == original)
    }

    @Test func roundTrip_randomData() {
        let original = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let hexString = original.hexEncodedString()
        let roundTripped = Data(hexString: hexString)

        #expect(roundTripped == original)
    }

    @Test func roundTrip_emptyData() {
        let original = Data()
        let hexString = original.hexEncodedString()
        let roundTripped = Data(hexString: hexString)

        #expect(roundTripped == original)
        #expect(roundTripped?.isEmpty == true)
    }

    @Test func roundTrip_singleByte() {
        for byte: UInt8 in [0x00, 0x0F, 0xF0, 0xFF, 0x42] {
            let original = Data([byte])
            let hexString = original.hexEncodedString()
            let roundTripped = Data(hexString: hexString)

            #expect(roundTripped == original)
        }
    }

    // MARK: - Long Strings

    @Test func hexString_long() {
        // 64 bytes = 128 hex characters
        let hexString = String(repeating: "ab", count: 64)
        let data = Data(hexString: hexString)

        #expect(data != nil)
        #expect(data?.count == 64)
        #expect(data?.allSatisfy { $0 == 0xAB } == true)
    }

    @Test func hexString_veryLong() {
        // 1024 bytes = 2048 hex characters
        let hexString = String(repeating: "12", count: 1024)
        let data = Data(hexString: hexString)

        #expect(data != nil)
        #expect(data?.count == 1024)
    }
}
