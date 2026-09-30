import AppKit
import SwiftUI

/// Keep Git's ANSI colour identity, translated into adaptive macOS colours.
enum GitGraphColorPalette {
    static func color(for codes: [Int], scheme: ColorScheme, increasedContrast: Bool = false) -> Color {
        Color(nsColor: resolvedColor(for: codes, dark: scheme == .dark, increasedContrast: increasedContrast))
    }

    static func resolvedColor(for codes: [Int], dark: Bool, increasedContrast: Bool = false) -> NSColor {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var result = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            let base = (baseColor(for: codes).usingColorSpace(.sRGB) ?? .labelColor).withAlphaComponent(1)
            let backgrounds = [NSColor.controlBackgroundColor, .windowBackgroundColor]
                + NSColor.alternatingContentBackgroundColors
            let target = increasedContrast ? 4.5 : 3.0
            result = base
            // Preserve the hue while moving luminance toward native text colour.
            for step in 0...20 {
                let candidate = base.blended(withFraction: CGFloat(step) / 20, of: .labelColor)!
                    .usingColorSpace(.sRGB)!.withAlphaComponent(1)
                result = candidate
                if backgrounds.allSatisfy({ contrastRatio(candidate, $0.usingColorSpace(.sRGB)!) >= target }) { break }
            }
        }
        return result
    }

    static func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
        func composite(_ color: NSColor, over background: NSColor) -> NSColor {
            let alpha = color.alphaComponent
            return NSColor(srgbRed: color.redComponent * alpha + background.redComponent * (1 - alpha),
                green: color.greenComponent * alpha + background.greenComponent * (1 - alpha),
                blue: color.blueComponent * alpha + background.blueComponent * (1 - alpha), alpha: 1)
        }
        func luminance(_ color: NSColor) -> Double {
            func linear(_ component: CGFloat) -> Double {
                let value = Double(component)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
        }
        // Dark macOS striped rows use a translucent white overlay, rather than
        // an opaque white background. Measure the actual composited row colour.
        let background = composite(second, over: NSColor.controlBackgroundColor.usingColorSpace(.sRGB)!)
        let a = luminance(composite(first, over: background)), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func baseColor(for codes: [Int]) -> NSColor {
        if let extended = codes.lastIndex(of: 38), codes.count > extended + 2 {
            if codes[extended + 1] == 2, codes.count > extended + 4 {
                return NSColor(srgbRed: CGFloat(codes[extended + 2]) / 255,
                    green: CGFloat(codes[extended + 3]) / 255, blue: CGFloat(codes[extended + 4]) / 255, alpha: 1)
            }
            if codes[extended + 1] == 5 {
                let value = min(255, max(0, codes[extended + 2]))
                if value < 16 { return standardColor(value % 8, bright: value >= 8) }
                if value >= 232 { return NSColor(white: CGFloat(8 + (value - 232) * 10) / 255, alpha: 1) }
                let cube = value - 16
                let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
                return NSColor(srgbRed: levels[(cube / 36) % 6] / 255,
                    green: levels[(cube / 6) % 6] / 255, blue: levels[cube % 6] / 255, alpha: 1)
            }
        }
        guard let code = codes.last(where: { (30...37).contains($0) || (90...97).contains($0) }) else { return .labelColor }
        return standardColor(code >= 90 ? code - 90 : code - 30, bright: code >= 90 || codes.contains(1))
    }

    private static func standardColor(_ index: Int, bright: Bool) -> NSColor {
        let normal: [NSColor] = [.secondaryLabelColor, .systemRed, .systemGreen, .systemOrange, .systemBlue, .systemPurple, .systemTeal, .labelColor]
        let vivid: [NSColor] = [.secondaryLabelColor, .systemPink, .systemMint, .systemYellow, .systemIndigo, .systemPurple, .systemCyan, .labelColor]
        if bright && index == 5 {
            // AppKit has one system purple. Give Git's bright magenta a distinct
            // native tint instead of making two concurrent ANSI lanes identical.
            return NSColor.systemPurple.blended(withFraction: 0.22, of: .labelColor) ?? .systemPurple
        }
        return (bright ? vivid : normal)[index]
    }
}
