import SwiftUI

enum GitGraphColorPalette {
    private static let colors: [Color] = [
        Color(red: 0.00, green: 0.62, blue: 0.76),
        Color(red: 0.98, green: 0.55, blue: 0.16),
        Color(red: 0.18, green: 0.78, blue: 0.37),
        Color(red: 0.26, green: 0.48, blue: 0.95),
        Color(red: 0.86, green: 0.08, blue: 0.55),
        Color(red: 0.02, green: 0.83, blue: 0.76),
        Color(red: 0.62, green: 0.31, blue: 0.96),
        Color(red: 0.95, green: 0.84, blue: 0.18),
        Color(red: 0.95, green: 0.26, blue: 0.22),
        Color(red: 0.00, green: 0.74, blue: 0.95),
        Color(red: 0.42, green: 0.86, blue: 0.23),
        Color(red: 0.86, green: 0.25, blue: 0.82),
        Color(red: 1.00, green: 0.42, blue: 0.14),
        Color(red: 0.00, green: 0.56, blue: 0.82),
        Color(red: 0.00, green: 0.72, blue: 0.48),
        Color(red: 0.70, green: 0.25, blue: 0.92)
    ]

    static func color(for lane: Int) -> Color {
        colors[abs(lane) % colors.count]
    }
}
