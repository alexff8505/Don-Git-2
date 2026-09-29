import SwiftUI

/// ANSI hues, using native adaptive colours for both macOS appearances.
enum GitGraphColorPalette {
    private static let colors: [Color] = [.primary, .red, .green, .yellow, .blue, .purple, .cyan, .primary]

    static func color(for codes: [Int]) -> Color {
        if let extended = codes.lastIndex(of: 38), codes.count > extended + 2 {
            if codes[extended + 1] == 2, codes.count > extended + 4 {
                return Color(red: Double(codes[extended + 2]) / 255,
                             green: Double(codes[extended + 3]) / 255,
                             blue: Double(codes[extended + 4]) / 255)
            }
            if codes[extended + 1] == 5 {
                let value = codes[extended + 2]
                if value < 16 { return colors[max(0, value) % 8] }
                if value >= 232 {
                    return Color(white: Double(min(255, 8 + (value - 232) * 10)) / 255)
                }
                let cube = value - 16
                let levels = [0.0, 95.0, 135.0, 175.0, 215.0, 255.0]
                return Color(red: levels[(cube / 36) % 6] / 255,
                             green: levels[(cube / 6) % 6] / 255,
                             blue: levels[cube % 6] / 255)
            }
        }
        guard let code = codes.last(where: { (30...37).contains($0) || (90...97).contains($0) }) else {
            return .primary
        }
        return colors[code >= 90 ? code - 90 : code - 30]
    }
}
