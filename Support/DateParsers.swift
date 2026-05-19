import Foundation

enum DateParsers {
    static func gitDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        return iso.date(from: value)
    }
}
