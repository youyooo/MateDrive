import Foundation

public enum MateDroidCurrencyFormatter {
    public static let automaticCode = "AUTO"

    private static let priorityCodes = [
        "CNY", "HKD", "TWD", "USD", "CAD", "GBP", "EUR", "AUD", "NZD",
        "JPY", "KRW", "SGD", "INR", "CHF", "SEK", "NOK", "DKK", "PLN",
        "CZK", "HUF", "AED", "SAR", "THB", "MYR", "IDR", "PHP", "VND",
        "BRL", "MXN", "ZAR", "TRY"
    ]

    public static let supportedCodes = priorityCodes + Locale.commonISOCurrencyCodes
        .map { $0.uppercased() }
        .filter { !priorityCodes.contains($0) }
        .sorted()

    public static func systemCurrencyCode(locale: Locale = .autoupdatingCurrent) -> String {
        locale.currency?.identifier.uppercased() ?? "USD"
    }

    public static func symbol(for code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case automaticCode: return symbol(for: systemCurrencyCode())
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        case "CNY", "RMB", "JPY": return "¥"
        case "HKD": return "HK$"
        case "TWD": return "NT$"
        case "CAD": return "CA$"
        case "AUD": return "A$"
        case "NZD": return "NZ$"
        case "SGD": return "S$"
        case "KRW": return "₩"
        case "INR": return "₹"
        case "BRL": return "R$"
        case "MXN": return "MX$"
        case "TRY": return "₺"
        case "THB": return "฿"
        case "PHP": return "₱"
        case "VND": return "₫"
        case "IDR": return "Rp "
        case "MYR": return "RM "
        case "AED": return "AED "
        case "SAR": return "SAR "
        case "ZAR": return "R "
        case "": return "¤"
        default: return normalized + " "
        }
    }
}
