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
        
        // 15 bold, distinct colors optimized explicitly for Dark Mode (Neon/Pastel Brights)
        let darkColors: [[Double]] = [
            [51, 181, 229],   // Neon Azure
            [255, 136, 0],    // Neon Orange
            [0, 200, 81],     // Neon Green
            [170, 102, 204],  // Bright Purple
            [255, 68, 68],    // Bright Pink/Rose
            [255, 223, 0],    // Bright Yellow
            [0, 229, 255],    // Cyan/Teal
            [255, 0, 255],    // Bright Magenta
            [174, 234, 0],    // Lime Green
            [255, 112, 67],   // Coral
            [92, 107, 192],   // Bright Indigo
            [105, 240, 174],  // Bright Mint
            [255, 202, 40],   // Gold
            [224, 64, 251],   // Orchid
            [68, 138, 255]    // Dodger Blue
        ]
        
        // 15 bold, distinct colors optimized explicitly for Light Mode (Jewel Tones for high contrast)
        let lightColors: [[Double]] = [
            [0, 91, 159],     // Deep Azure
            [230, 81, 0],     // Deep Orange
            [0, 126, 51],     // Deep Green
            [106, 27, 154],   // Deep Purple
            [204, 0, 0],      // Deep Red
            [245, 127, 23],   // Amber
            [0, 96, 100],     // Deep Teal
            [136, 14, 79],    // Deep Magenta
            [85, 139, 47],    // Olive Green
            [216, 67, 21],    // Rust
            [40, 53, 147],    // Navy Indigo
            [0, 105, 92],     // Deep Mint
            [255, 143, 0],    // Dark Gold
            [173, 20, 87],    // Deep Orchid
            [1, 87, 155]      // Royal Blue
        ]
        
        // Choose palette based on current color scheme
        let activePalette = isDark ? darkColors : lightColors
        let colorIndex = Int(h % UInt64(activePalette.count))
        let rgb = activePalette[colorIndex]
        
        let c = Color(red: rgb[0] / 255.0, green: rgb[1] / 255.0, blue: rgb[2] / 255.0)
        Self.peerColorCache[cacheKey] = c
        self = c
    }
}
