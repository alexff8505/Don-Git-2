import Foundation

enum DisplayFormatters {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func commitDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today at \(timeFormatter.string(from: date))"
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday at \(timeFormatter.string(from: date))"
        }

        return dateFormatter.string(from: date)
    }
}
