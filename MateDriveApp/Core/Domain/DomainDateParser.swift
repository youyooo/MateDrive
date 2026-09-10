import Foundation

enum DomainDateParser {
    static func date(from value: String) -> Date? {
        isoWithFractionalSeconds().date(from: value) ??
            isoWithoutFractionalSeconds().date(from: value) ??
            localDateFormatter(format: "yyyy-MM-dd'T'HH:mm:ss").date(from: value) ??
            localDateFormatter(format: "yyyy-MM-dd HH:mm:ss").date(from: value)
    }

    static func timeZone(from value: String) -> TimeZone? {
        if value.hasSuffix("Z") || value.hasSuffix("z") {
            return TimeZone(secondsFromGMT: 0)
        }
        guard value.count >= 6 else { return nil }
        let suffix = String(value.suffix(6))
        guard (suffix.first == "+" || suffix.first == "-"),
              suffix[suffix.index(suffix.startIndex, offsetBy: 3)] == ":",
              let hours = Int(suffix.dropFirst().prefix(2)),
              let minutes = Int(suffix.suffix(2)),
              hours <= 23,
              minutes <= 59
        else { return nil }
        let sign = suffix.first == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: sign * ((hours * 60 + minutes) * 60))
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
