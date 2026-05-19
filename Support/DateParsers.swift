import Foundation

enum DateParsers {
    private static let iso = ISO8601DateFormatter()

    static func gitDate(_ value: String) -> Date? {
        iso.date(from: value)
    }
}
