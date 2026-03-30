//
// Color+Peer.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

extension Color {
    private static var peerColorCache: [String: Color] = [:]
    
    init(peerSeed: String, isDark: Bool) {
        let cacheKey = peerSeed + (isDark ? "|dark" : "|light")
        if let cached = Self.peerColorCache[cacheKey] {
            self = cached
        }
        let h = peerSeed.djb2()
        
        let baseColors: [[Double]] = [
            [0, 114, 178],   // Blue
            [213, 94, 0],    // Vermillion
            [0, 158, 115],   // Bluish Green
            [230, 159, 0],   // Orange
            [204, 121, 167], // Reddish Purple
            [86, 180, 233],  // Sky Blue
            [240, 228, 66],  // Yellow
            [17, 119, 51],   // Dark Green
            [51, 34, 136],   // Dark Teal
            [136, 204, 238], // Light Blue
            [68, 170, 153],  // Mint
            [153, 153, 51],  // Olive
            [221, 204, 119], // Sand
            [204, 102, 119], // Rose
            [136, 34, 85]    // Wine
        ]
        
        let colorIndex = Int(h % UInt64(baseColors.count))
        let baseRgb = baseColors[colorIndex]
        
        var r = baseRgb[0] / 255.0
        var g = baseRgb[1] / 255.0
        var b = baseRgb[2] / 255.0
        
        if isDark {
            r = r + (1.0 - r) * 0.4
            g = g + (1.0 - g) * 0.4
            b = b + (1.0 - b) * 0.4
        } else {
            r = r * 0.8
            g = g * 0.8
            b = b * 0.8
        }
        
        let c = Color(red: r, green: g, blue: b)
        Self.peerColorCache[cacheKey] = c
        self = c
    }
}
