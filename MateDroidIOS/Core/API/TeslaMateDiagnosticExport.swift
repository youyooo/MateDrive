import Foundation

public struct TeslaMateDiagnosticExportMetadata: Equatable, Sendable {
    public let appVersion: String
    public let appBuild: String
    public let languageCode: String
    public let unitSystem: String
    public let currencyCode: String

    public init(
        appVersion: String,
        appBuild: String,
        languageCode: String,
        unitSystem: String,
        currencyCode: String
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.languageCode = languageCode
        self.unitSystem = unitSystem
        self.currencyCode = currencyCode
    }
}

public enum TeslaMateDiagnosticExport {
    public static func render(
        report: TeslaMateDiagnosticReport,
        metadata: TeslaMateDiagnosticExportMetadata,
        generatedAt: Date = Date()
    ) -> String {
        let passedCount = report.checks.filter { $0.status == .passed }.count
        let warningCount = report.checks.filter { $0.status == .warning }.count
        let failedCount = report.checks.filter { $0.status == .failed }.count
        var lines = [
            "MateDrive Diagnostic Report",
            "format_version: 1",
            "generated_at: \(timestamp(generatedAt))",
            "app_version: \(safe(metadata.appVersion)) (\(safe(metadata.appBuild)))",
            "language: \(safe(metadata.languageCode))",
            "unit_system: \(safe(metadata.unitSystem))",
            "currency: \(safe(metadata.currencyCode))",
            "privacy: server addresses, credentials, vehicle identifiers, and coordinates are omitted or redacted",
            "",
            "[Summary]",
            "summary: passed=\(passedCount) warning=\(warningCount) failed=\(failedCount)",
            "api_version: \(safe(report.serverProfile?.version.displayVersion ?? "unknown"))"
        ]

        if let buildInfo = report.serverProfile?.version.buildInfo, !buildInfo.isEmpty {
            lines.append("api_build: \(safe(buildInfo))")
        }

        lines.append("")
        lines.append("[Capabilities]")
        let capabilities = report.serverProfile?.capabilities.sorted { $0.key.rawValue < $1.key.rawValue } ?? []
        if capabilities.isEmpty {
            lines.append("none")
        } else {
            for (capability, status) in capabilities {
                var parts = ["\(capability.rawValue): \(status.state.rawValue)"]
                if let reason = status.reason {
                    parts.append("reason=\(reason.rawValue)")
                }
                parts.append("source=\(status.source.rawValue)")
                lines.append(parts.joined(separator: "; "))
            }
        }

        lines.append("")
        lines.append("[Checks]")
        if report.checks.isEmpty {
            lines.append("none")
        } else {
            for check in report.checks {
                lines.append("[\(check.status.rawValue)] \(check.checkID.rawValue) | \(safe(check.title)) | \(safe(check.message))")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func suggestedFilename(generatedAt: Date = Date()) -> String {
        "MateDrive-Diagnostics-\(timestamp(generatedAt).replacingOccurrences(of: ":", with: "-")).txt"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func safe(_ value: String) -> String {
        var sanitized = value.replacingOccurrences(of: "[\\r\\n]+", with: " ", options: .regularExpression)
        let redactions: [(String, String)] = [
            (#"(?i)\b(?:https?|wss?)://[^\s]+"#, "[REDACTED_URL]"),
            (#"(?<!\d)-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}(?!\d)"#, "[REDACTED_COORDINATES]"),
            (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, "[REDACTED_CREDENTIAL]"),
            (#"(?i)\b(?:authorization|api[_ -]?token|token|access[_ -]?key|secret(?:[_ -]?key)?|password)\b\s*[:=]\s*[^\s,;]+"#, "[REDACTED_CREDENTIAL]"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b"#, "[REDACTED_HOST]"),
            (#"\b(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?\b"#, "[REDACTED_HOST]"),
            (#"\b[A-Fa-f0-9]{24,}\b"#, "[REDACTED_CREDENTIAL]")
        ]
        for (pattern, replacement) in redactions {
            sanitized = sanitized.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
