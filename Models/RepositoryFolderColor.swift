import SwiftUI

enum RepositoryFolderColor: String, CaseIterable, Identifiable, Sendable {
    case defaultColor
    case red
    case orange
    case yellow
    case green
    case mint
    case blue
    case purple
    case pink
    case gray

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .defaultColor:
            "Default"
        case .red:
            "Red"
        case .orange:
            "Orange"
        case .yellow:
            "Yellow"
        case .green:
            "Green"
        case .mint:
            "Mint"
        case .blue:
            "Blue"
        case .purple:
            "Purple"
        case .pink:
            "Pink"
        case .gray:
            "Gray"
        }
    }

    var color: Color? {
        switch self {
        case .defaultColor:
            nil
        case .red:
            .red
        case .orange:
            .orange
        case .yellow:
            .yellow
        case .green:
            .green
        case .mint:
            .mint
        case .blue:
            .blue
        case .purple:
            .purple
        case .pink:
            .pink
        case .gray:
            .gray
        }
    }
}
