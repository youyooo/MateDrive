import Foundation

enum DomainDateParser {
    static func date(from value: String) -> Date? {
        isoWithFractionalSeconds().date(from: value) ??
            isoWithoutFractionalSeconds().date(from: value) ??
            localDateFormatter(format: "yyyy-MM-dd'T'HH:mm:ss").date(from: value) ??
            localDateFormatter(format: "yyyy-MM-dd HH:mm:ss").date(from: value)
    }

    private static func isoWithFractionalSeconds() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func isoWithoutFractionalSeconds() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func localDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
