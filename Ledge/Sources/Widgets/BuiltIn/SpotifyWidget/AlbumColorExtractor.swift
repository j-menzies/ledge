import AppKit
import SwiftUI
import os

/// Extracts dominant colors from album artwork for dynamic widget backgrounds.
///
/// Downloads the image, scales it down for fast processing, then samples
/// pixels to find dominant and accent colors. Results are cached by URL.
nonisolated class AlbumColorExtractor: @unchecked Sendable {

    struct Colors: Equatable {
        let primary: Color
        let secondary: Color
        let isDark: Bool
    }

    /// Thread-safe cache of extracted colors keyed by artwork URL.
    private let cache = OSAllocatedUnfairLock(initialState: [String: Colors]())

    /// Extract dominant colors from an image URL.
    func extract(from urlString: String) async -> Colors? {
        // Check cache
        if let cached = cache.withLock({ $0[urlString] }) {
            return cached
        }

        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let colors = analyzeImage(cgImage)

        cache.withLock { $0[urlString] = colors }

        return colors
    }

    /// Clear the cache (e.g., when memory is low).
    func clearCache() {
        cache.withLock { $0.removeAll() }
    }

    private func analyzeImage(_ cgImage: CGImage) -> Colors {
        let sampleSize = 24
        var pixelData = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Colors(primary: Color(white: 0.15), secondary: Color(white: 0.1), isDark: true)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        // Collect color buckets using simple quantization
        var buckets: [Int: (r: Double, g: Double, b: Double, count: Int)] = [:]

        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let offset = (y * sampleSize + x) * 4
                let r = Double(pixelData[offset]) / 255.0
                let g = Double(pixelData[offset + 1]) / 255.0
                let b = Double(pixelData[offset + 2]) / 255.0

                // Quantize to 4-bit per channel for bucketing
                let key = (Int(r * 15) << 8) | (Int(g * 15) << 4) | Int(b * 15)
                if var bucket = buckets[key] {
                    bucket.r += r
                    bucket.g += g
                    bucket.b += b
                    bucket.count += 1
                    buckets[key] = bucket
                } else {
                    buckets[key] = (r, g, b, 1)
                }
            }
        }

        // Sort buckets by count (most common first), skip very dark/bright
        let sorted = buckets.values
            .filter { bucket in
                let avg = (bucket.r + bucket.g + bucket.b) / (3.0 * Double(bucket.count))
                return avg > 0.05 && avg < 0.9
            }
            .sorted { $0.count > $1.count }

        let primaryBucket = sorted.first ?? (r: 0.15, g: 0.15, b: 0.15, count: 1)
        let secondaryBucket = sorted.dropFirst().first ?? primaryBucket

        let pr = primaryBucket.r / Double(primaryBucket.count)
        let pg = primaryBucket.g / Double(primaryBucket.count)
        let pb = primaryBucket.b / Double(primaryBucket.count)

        let sr = secondaryBucket.r / Double(secondaryBucket.count)
        let sg = secondaryBucket.g / Double(secondaryBucket.count)
        let sb = secondaryBucket.b / Double(secondaryBucket.count)

        // Darken the colors to ensure text readability (multiply by 0.4)
        let darkenFactor = 0.4
        let primary = Color(
            red: pr * darkenFactor,
            green: pg * darkenFactor,
            blue: pb * darkenFactor
        )
        let secondary = Color(
            red: sr * darkenFactor * 0.7,
            green: sg * darkenFactor * 0.7,
            blue: sb * darkenFactor * 0.7
        )

        let brightness = (pr + pg + pb) / 3.0
        return Colors(primary: primary, secondary: secondary, isDark: brightness < 0.5)
    }
}
