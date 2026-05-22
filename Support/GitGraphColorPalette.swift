import SwiftUI

enum GitGraphColorPalette {
    private static let colors: [Color] = [
        .orange,
        .blue,
        .red,
        .cyan,
        .purple,
        .green,
        .indigo,
        .pink
    ]

    static func color(for lane: Int) -> Color {
        colors[abs(lane) % colors.count]
    }
}
