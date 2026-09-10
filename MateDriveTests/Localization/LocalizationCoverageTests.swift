import Foundation
import XCTest
@testable import MateDriveApp

final class LocalizationCoverageTests: XCTestCase {
    func testAppTextUsesSupportedLocalizations() {
        XCTAssertEqual(AppText.localized("Settings", "设置", language: .chinese), "设置")
        XCTAssertEqual(AppText.localized("Settings", "设置", language: .traditionalChinese), "設定")
        XCTAssertEqual(AppText.localized("Settings", "设置", language: .english), "Settings")
    }

    func testTraditionalChineseUsesContextualChineseFallbacksInsteadOfSharedEnglishKeys() {
        XCTAssertEqual(AppText.localized("Home", "首页", language: .traditionalChinese), "首頁")
        XCTAssertEqual(AppText.localized("Home", "家", language: .traditionalChinese), "家")
        XCTAssertEqual(AppText.localized("Battery", "电量", language: .traditionalChinese), "電量")
        XCTAssertEqual(AppText.localized("Battery", "电池", language: .traditionalChinese), "電池")
        XCTAssertEqual(
            AppText.localized("Server settings", "服务器设置", language: .traditionalChinese),
            "伺服器設定"
        )
        XCTAssertEqual(
            AppText.localized("Loading data", "正在加载数据", language: .traditionalChinese),
            "正在載入資料"
        )
    }

    func testTraditionalChineseRegionDetectionIsExplicit() {
        XCTAssertTrue(AppText.usesTraditionalChinese(language: .traditionalChinese))
        XCTAssertTrue(AppText.usesTraditionalChinese(language: .system, preferredLanguage: "zh-Hant-TW"))
        XCTAssertTrue(AppText.usesTraditionalChinese(language: .system, preferredLanguage: "zh-HK"))
        XCTAssertFalse(AppText.usesTraditionalChinese(language: .system, preferredLanguage: "zh-Hans-CN"))
        XCTAssertFalse(AppText.usesTraditionalChinese(language: .system, preferredLanguage: "zh"))
        XCTAssertFalse(AppText.usesTraditionalChinese(language: .chinese))
    }

    private let requiredLocales: Set<String> = ["en", "zh-Hans", "zh-Hant"]
    private let requiredFeatureKeys: Set<String> = [
        "MateDrive",
        "Settings",
        "Dashboard",
        "Activities",
        "Parking Detail",
        "Palette",
        "Charges",
        "Charge Detail",
        "Compare Charges",
        "Current Charge",
        "Drives",
        "Drive Detail",
        "Compare Drives",
        "Battery",
        "Battery Health",
        "Battery Report",
        "Share Battery Report",
        "Include exact recording dates",
        "Include recording start odometer",
        "Data Quality",
        "History Span",
        "Mileage",
        "Updates",
        "Stats",
        "Countries Visited",
        "Regions Visited",
        "Where Was I",
        "Trips",
        "Create Trip",
        "Trip Detail",
        "Sentry",
        "Widget",
        "Notifications",
        "Loading",
        "Error",
        "This feature is temporarily unavailable.",
        "No data",
        "Charge",
        "Mileage by Year",
        "Mileage by Month",
        "Mileage by Day",
        "No mileage data",
        "Weather Along The Way",
        "Loading weather",
        "No weather samples",
        "Finding location",
        "Location",
        "Driving",
        "Charging",
        "Speed",
        "Power",
        "Outside",
        "Power Curve",
        "Peak Power",
        "Peak",
        "Base Charge",
        "Cloudflare Access Client ID",
        "Cloudflare Access Client Secret",
        "Server Version",
        "API Capabilities",
        "Server Statistics",
        "Unified Activities",
        "Merge adjacent drives",
        "Maximum stop",
        "Merged Drive",
        "Why These Drives Were Merged",
        "Original Drive Segments",
        "Activity Recap",
        "Share Period Recap",
        "Include exact activity dates",
        "Include costs",
        "Partial history",
        "Battery History",
        "Drive Insights",
        "Available",
        "Limited",
        "Unavailable",
        "Similar Charges",
        "Charge Curves",
        "No comparable charges",
        "Charge Energy",
        "Total Cost",
        "Cost",
        "Average",
        "Price per kWh",
        "SOC",
        "Date",
        "Today",
        "7 Days",
        "30 Days",
        "90 Days",
        "Year",
        "All Time",
        "All",
        "Sort",
        "Drive",
        "AC Charge",
        "DC Charge",
        "Parked",
        "Has Cost",
        "No Cost",
        "Charge Cost",
        "Manual Cost",
        "API Cost",
        "Save Cost",
        "Clear Manual Cost",
        "Cost Source",
        "Local manual price",
        "Pricing rule",
        "TeslaMate API price",
        "No cost recorded",
        "No pricing rule matched this charge",
        "Location and time pricing rules are not configured yet",
        "Charge Pricing",
        "Pricing Rules",
        "Pricing Rule",
        "No pricing rules",
        "Add rules to estimate charging cost by location, time, and charger type.",
        "Add Pricing Rule",
        "Add Segment",
        "Rule",
        "Name",
        "Enabled",
        "Disabled",
        "Charger Type",
        "Any",
        "Address Keyword",
        "Latitude",
        "Longitude",
        "Radius Meters",
        "Time",
        "Start Time",
        "End Time",
        "Price",
        "Default Price per kWh",
        "Price Segments",
        "Session Fee",
        "Priority",
        "Cancel",
        "Delete",
        "Capacity Now",
        "Capacity New",
        "Capacity Loss",
        "Range Now",
        "Range New",
        "Range Loss",
        "Current SOC",
        "Rated Range",
        "At 100%",
        "Battery Calibration",
        "Battery Health Note",
        "New Battery Rated Range",
        "Recording Start Odometer",
        "Health Confidence",
        "Connection Test",
        "Test Connection",
        "Testing Connection",
        "6 Months",
        "AC / DC",
        "Automatic",
        "Average Gap",
        "Avg Duration",
        "Avg Efficiency",
        "Base",
        "Battery unavailable",
        "Car Image",
        "Charge Starting",
        "Charged",
        "Comparing drives",
        "Current",
        "Duration",
        "Efficiency",
        "Current Alerts",
        "Delete Trip",
        "Drive Distance",
        "Driving",
        "Edit",
        "Energy Added",
        "Last 6 Days",
        "Legs",
        "Loading comparison",
        "Loading current charge",
        "Loading trip",
        "Loading trips",
        "Longest Drive",
        "Longest",
        "Most Efficient",
        "Newest",
        "No Active Charge",
        "No comparable drives",
        "No curve data",
        "No trips found",
        "Oldest",
        "Records",
        "Regions",
        "Rename",
        "Route Drives",
        "Session",
        "Save Trip",
        "Saving",
        "Shows the latest read-only car status.",
        "TeslaMate has not published the active charge yet.",
        "The car is not currently charging.",
        "Trip not found",
        "Trip name",
        "Type",
        "Updates per Month",
        "Variant",
        "View Charge",
        "View Drive",
        "Active",
        "Idle",
        "Lock",
        "Locked",
        "Off",
        "On",
        "Ready",
        "Sentry active",
        "Unlocked",
        "Unknown",
        "Vehicle",
        "Commute",
        "Day Trip",
        "Road Trip",
        "No drive history",
        "Compare",
        "drives",
        "minutes",
        "drive",
        "trip"
    ]

    func testAllRequiredLocalesExist() throws {
        let catalog = try StringCatalog.load(resourceName: "Localizable")

        XCTAssertTrue(catalog.locales.contains("en"))
        XCTAssertTrue(catalog.locales.contains("zh-Hans"))
        XCTAssertTrue(catalog.locales.contains("zh-Hant"))
    }

    func testAllRequiredFeatureKeysExist() throws {
        let catalog = try StringCatalog.load(resourceName: "Localizable")
        let missingKeys = requiredFeatureKeys.subtracting(catalog.keys)

        XCTAssertTrue(missingKeys.isEmpty, "Missing localized feature keys: \(missingKeys.sorted().joined(separator: ", "))")
    }

    func testChineseSourceLocalizationsDoNotExposeShortEnglishChargeTypeLabels() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDriveApp/Resources/Localizable.xcstrings")

        XCTAssertEqual(sourceCatalog.value(for: "AC", locale: "zh-Hans"), "交流")
        XCTAssertEqual(sourceCatalog.value(for: "DC", locale: "zh-Hans"), "直流")
        XCTAssertEqual(sourceCatalog.value(for: "AC", locale: "zh-Hant"), "交流")
        XCTAssertEqual(sourceCatalog.value(for: "DC", locale: "zh-Hant"), "直流")
    }

    func testEuropeanPricingSurfacesAreActuallyTranslated() throws {
        throw XCTSkip("MateDrive 1.0 exposes English, Simplified Chinese, and Traditional Chinese.")
    }

    func testEuropeanBatteryAndDiagnosticSurfacesAreActuallyTranslated() throws {
        throw XCTSkip("MateDrive 1.0 exposes English, Simplified Chinese, and Traditional Chinese.")
    }

    func testEuropeanDashboardTripAndWidgetSurfacesAreActuallyTranslated() throws {
        throw XCTSkip("MateDrive 1.0 exposes English, Simplified Chinese, and Traditional Chinese.")
    }

    func testEuropeanChargeComparisonAndUpdateSurfacesAreActuallyTranslated() throws {
        throw XCTSkip("MateDrive 1.0 exposes English, Simplified Chinese, and Traditional Chinese.")
    }

    func testEuropeanEnglishEquivalentStringsAreExplicitlyAllowed() throws {
        throw XCTSkip("MateDrive 1.0 exposes English, Simplified Chinese, and Traditional Chinese.")
    }

    func testChineseSourceLocalizationsDoNotExposeUnexpectedEnglishWords() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDriveApp/Resources/Localizable.xcstrings")
        let unexpected = ["zh-Hans", "zh-Hant"].flatMap { locale in
            sourceCatalog.englishWords(in: locale).filter { entry in
                !Self.allowedChineseTechnicalWords.contains(entry.word)
            }.map { (locale, $0) }
        }

        XCTAssertTrue(
            unexpected.isEmpty,
            "Unexpected English words in Chinese localizations: \(unexpected.map { "\($0.0):\($0.1.key)=\($0.1.word)" }.joined(separator: ", "))"
        )
    }

    func testChineseFallbackStringsInSwiftSourcesDoNotExposeUnexpectedEnglishWords() throws {
        let callExpression = try XCTUnwrap(NSRegularExpression(pattern: #"(?:t|localized)\(\s*"(?:[^"\\]|\\.)*"\s*,\s*"((?:[^"\\]|\\.)*)""#))
        let interpolationExpression = try XCTUnwrap(NSRegularExpression(pattern: #"\\\([^)]+\)"#))
        let formatExpression = try XCTUnwrap(NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.\d+)?[A-Za-z@]"#))
        let wordExpression = try XCTUnwrap(NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9/+.-]*"#))
        let swiftSources = try swiftSourcePaths(in: ["MateDriveApp", "MateDriveWidget"])
        var checkedFallbacks = 0
        var unexpected: [String] = []

        for path in swiftSources {
            let text = try loadSourceText(path)
            let textRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = callExpression.matches(in: text, range: textRange)
            for match in matches {
                guard let fallbackRange = Range(match.range(at: 1), in: text) else {
                    continue
                }
                checkedFallbacks += 1
                let rawFallback = String(text[fallbackRange])
                let withoutInterpolation = interpolationExpression.stringByReplacingMatches(
                    in: rawFallback,
                    range: NSRange(rawFallback.startIndex..<rawFallback.endIndex, in: rawFallback),
                    withTemplate: ""
                )
                let fallback = formatExpression.stringByReplacingMatches(
                    in: withoutInterpolation,
                    range: NSRange(withoutInterpolation.startIndex..<withoutInterpolation.endIndex, in: withoutInterpolation),
                    withTemplate: ""
                )
                let cleanedFallbackRange = NSRange(fallback.startIndex..<fallback.endIndex, in: fallback)
                let words = wordExpression.matches(in: fallback, range: cleanedFallbackRange).compactMap { wordMatch -> String? in
                    guard let wordRange = Range(wordMatch.range, in: fallback) else {
                        return nil
                    }
                    return String(fallback[wordRange])
                }
                for word in words where !Self.allowedChineseTechnicalWords.contains(word) {
                    let line = lineNumber(in: text, atUTF16Location: match.range.location)
                    unexpected.append("\(path):\(line) \(word) in \(rawFallback)")
                }
            }
        }

        XCTAssertGreaterThan(checkedFallbacks, 0, "Expected Swift source fallback strings to be checked")
        XCTAssertTrue(unexpected.isEmpty, "Unexpected English words in Chinese Swift fallback strings: \(unexpected.joined(separator: ", "))")
    }

    func testDashboardFormatterLiteralTitlesHaveChineseMappings() throws {
        let callExpression = try XCTUnwrap(NSRegularExpression(pattern: #"DashboardTextFormatter\.title\(\s*"((?:[^"\\]|\\.)*)""#))
        let swiftSources = try swiftSourcePaths(in: ["MateDriveApp", "MateDriveWidget"])
        var missingMappings: [String] = []

        for path in swiftSources {
            let text = try loadSourceText(path)
            let textRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = callExpression.matches(in: text, range: textRange)
            for match in matches {
                guard let keyRange = Range(match.range(at: 1), in: text) else {
                    continue
                }
                let key = String(text[keyRange])
                let localized = DashboardTextFormatter.title(key, language: .chinese)
                if localized == key {
                    let line = lineNumber(in: text, atUTF16Location: match.range.location)
                    missingMappings.append("\(path):\(line) \(key)")
                }
            }
        }

        XCTAssertTrue(missingMappings.isEmpty, "Missing Chinese DashboardTextFormatter title mappings: \(missingMappings.joined(separator: ", "))")
    }

    func testRuntimeTeslaMateErrorMessagesUseChineseWhenLanguageIsChinese() {
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("Configure your TeslaMate server before loading charges.", language: .chinese),
            "请先配置 TeslaMate 服务器，再加载充电记录。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("TeslaMate returned HTTP 500.", language: .chinese),
            "TeslaMate 返回 HTTP 500."
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("No TeslaMate cars were returned.", language: .chinese),
            "TeslaMate 没有返回车辆。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("The TeslaMate server URL is invalid: ftp://bad", language: .chinese),
            "TeslaMate 服务器地址无效：ftp://bad"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("Invalid TeslaMate response: missing data", language: .chinese),
            "TeslaMate 响应无效：missing data"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("SSL certificate error: self-signed certificate", language: .chinese),
            "SSL 证书错误：self-signed certificate"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("Network error: connection reset", language: .chinese),
            "网络错误：connection reset"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("TeslaMate returned no charge data.", language: .chinese),
            "TeslaMate 没有返回充电数据。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("TeslaMate returned no drive data.", language: .chinese),
            "TeslaMate 没有返回行程数据。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("TeslaMate returned no analytics data.", language: .chinese),
            "TeslaMate 没有返回统计数据。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("Configure your TeslaMate server before loading charges.", language: .english),
            "Configure your TeslaMate server before loading charges."
        )
    }

    func testAuthenticationChineseCopyDoesNotExposeBasicOrTokenLabels() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsSource = try String(contentsOf: repositoryRoot.appendingPathComponent("MateDriveApp/Features/Settings/SettingsView.swift"), encoding: .utf8)
        let diagnosticSource = try String(contentsOf: repositoryRoot.appendingPathComponent("MateDriveApp/Core/API/TeslaMateConnectionDiagnostic.swift"), encoding: .utf8)

        XCTAssertFalse(settingsSource.contains(#""API Token", "API Token""#))
        XCTAssertFalse(settingsSource.contains(#""Basic Username", "Basic 用户名""#))
        XCTAssertFalse(settingsSource.contains(#""Basic Password", "Basic 密码""#))
        XCTAssertFalse(diagnosticSource.contains("API Token 或 Basic Auth"))
    }

    func testFeatureAPIErrorMessagesKeepTranslatableContext() {
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized(APIError.sslCertificate("self-signed certificate").chargeMessage, language: .chinese),
            "SSL 证书错误：self-signed certificate"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized(APIError.invalidResponse("missing data").driveMessage, language: .chinese),
            "TeslaMate 响应无效：missing data"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized(APIError.network("connection reset").analyticsMessage, language: .chinese),
            "网络错误：connection reset"
        )
    }

    func testRuntimeSystemAndDatabaseErrorsUseChineseWhenLanguageIsChinese() {
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("The Internet connection appears to be offline.", language: .chinese),
            "网络连接似乎已离线。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("The request timed out.", language: .chinese),
            "请求超时。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("SQLite error: database is locked", language: .chinese),
            "本地数据库正忙，请稍后重试。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("SQLite error: constraint failed", language: .chinese),
            "本地数据保存失败：约束检查未通过。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized(SQLiteError.prepareFailed("near FROM: syntax error").localizedDescription, language: .chinese),
            "本地数据库查询准备失败。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized(SQLiteError.noRows.localizedDescription, language: .chinese),
            "本地数据库没有找到对应记录。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("Enter a valid charge cost.", language: .chinese),
            "请输入有效的充电费用。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("Charge cost must be zero or greater.", language: .chinese),
            "充电费用必须大于或等于 0。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("Charge cost writeback is unavailable.", language: .chinese),
            "当前 TeslaMate API 不支持写回充电费用。"
        )
        XCTAssertEqual(
            UserFacingErrorLocalizer.localized("The request timed out.", language: .english),
            "The request timed out."
        )
    }

    func testAllLocalizedKeysCoverRequiredLocales() throws {
        let catalog = try StringCatalog.load(resourceName: "Localizable")
        let smartActivityKeys = Set(try smartActivitySourceFallbacks().keys)
        let missing = catalog.keysWithMissingLocalizations(requiredLocales: requiredLocales)
        let unsupportedMissingLocales = missing.filter { key, locales in
            guard smartActivityKeys.contains(key),
                  !Self.activityLabelEditorCompleteKeys.contains(key)
            else { return true }
            return !Set(locales).isSubset(of: ["ca", "de", "es", "it"])
        }

        XCTAssertTrue(
            unsupportedMissingLocales.isEmpty,
            "Missing required localizations: \(unsupportedMissingLocales)"
        )
    }

    func testSmartActivityStaticCopyHasEnglishAndChineseCatalogValues() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDriveApp/Resources/Localizable.xcstrings")
        let fallbacks = try smartActivitySourceFallbacks()
        var failures: [String] = []

        for key in fallbacks.keys.sorted() {
            guard let chinese = fallbacks[key] else { continue }
            if sourceCatalog.value(for: key, locale: "en") != key {
                failures.append("\(key):en")
            }
            if sourceCatalog.value(for: key, locale: "zh-Hans") != chinese {
                failures.append("\(key):zh-Hans")
            }
            if sourceCatalog.value(for: key, locale: "zh-Hant")?.isEmpty != false {
                failures.append("\(key):zh-Hant")
            }
        }

        XCTAssertFalse(fallbacks.isEmpty)
        XCTAssertTrue(failures.isEmpty, "Missing smart-activity catalog values: \(failures.joined(separator: ", "))")
    }

    func testActivityLabelEditorCopyHasCompleteTranslations() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDriveApp/Resources/Localizable.xcstrings")
        let europeanLocales = ["ca", "de", "es", "it"]
        var failures: [String] = []

        for key in Self.activityLabelEditorCompleteKeys.sorted() {
            for locale in requiredLocales {
                guard let value = sourceCatalog.value(for: key, locale: locale), !value.isEmpty else {
                    failures.append("\(key):\(locale)=missing")
                    continue
                }
                if europeanLocales.contains(locale), value == key {
                    failures.append("\(key):\(locale)=English fallback")
                }
            }
        }

        XCTAssertEqual(sourceCatalog.value(for: "Edit Activity Label", locale: "zh-Hant"), "編輯活動標籤")
        XCTAssertEqual(sourceCatalog.value(for: "Custom Name", locale: "zh-Hant"), "自訂名稱")
        XCTAssertEqual(sourceCatalog.value(for: "Teal", locale: "zh-Hant"), "青綠色")
        XCTAssertTrue(failures.isEmpty, "Incomplete ActivityLabelEditor translations: \(failures.joined(separator: ", "))")
    }

    private static let activityLabelEditorCompleteKeys: Set<String> = [
        "A valid place is required for future activities.",
        "Active Time",
        "Activity Purpose",
        "Apply To",
        "Blue",
        "Custom Name",
        "Custom activity name is required.",
        "Edit Activity Label",
        "Future activities here",
        "Green",
        "Indigo",
        "Limit to a time window",
        "Orange",
        "Overnight windows are supported, for example 22:00 to 06:00.",
        "Pink",
        "Purpose",
        "Start and end times are both required.",
        "Teal",
        "This activity",
        "Time must be between 00:00 and 23:59."
    ]

    private static let allowedChineseTechnicalWords: Set<String> = [
        "AC",
        "API",
        "Cloudflare",
        "DC",
        "DHCP",
        "HTTP",
        "HTTPS",
        "Mac",
        "MateDrive",
        "Model",
        "Open-Meteo",
        "Cybertruck",
        "Cyberbeast",
        "Highland",
        "Juniper",
        "Performance",
        "Plaid",
        "Roadster",
        "Aero",
        "Arachnid",
        "Crossflow",
        "Cyberstream",
        "Gemini",
        "Photon",
        "Slipstream",
        "Tempest",
        "Turbine",
        "berturbine",
        "S",
        "X",
        "Y",
        "SOC",
        "SSL",
        "TeslaMate",
        "Tailscale",
        "URL",
        "Wh",
        "iOS",
        "iPhone",
        "kW",
        "kWh",
        "km",
        "iCloud",
        "local",
        "mini"
    ]

    private func loadSourceText(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func smartActivitySourceFallbacks() throws -> [String: String] {
        let expression = try XCTUnwrap(NSRegularExpression(
            pattern: #"(?:t|localized|AppText\.localized)\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)""#,
            options: [.dotMatchesLineSeparators]
        ))
        let paths = [
            "MateDriveApp/Features/Activities/SmartActivityModels.swift",
            "MateDriveApp/Features/Activities/ActivitySessionCard.swift",
            "MateDriveApp/Features/Activities/ActivityTimelineView.swift",
            "MateDriveApp/Features/Activities/ActivitySessionDetailView.swift",
            "MateDriveApp/Features/Activities/ParkingActivityDetailView.swift",
            "MateDriveApp/Features/Activities/ActivityLabelEditorView.swift",
            "MateDriveApp/Features/Charges/ChargePriceConfirmationView.swift",
            "MateDriveApp/Features/Settings/SmartActivitySettingsView.swift",
            "MateDriveApp/Features/Settings/PrivacyDataView.swift"
        ]
        var values: [String: String] = [:]

        for path in paths {
            let source = try loadSourceText(path)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let englishRange = Range(match.range(at: 1), in: source),
                      let chineseRange = Range(match.range(at: 2), in: source)
                else { continue }
                let english = String(source[englishRange])
                guard !english.contains(#"\("#) else { continue }
                values[english] = String(source[chineseRange])
            }
        }
        return values
    }

    private func swiftSourcePaths(in directories: [String]) throws -> [String] {
        let root = repositoryRoot()
        let fileManager = FileManager.default

        return try directories.flatMap { directory -> [String] in
            let directoryURL = root.appendingPathComponent(directory, isDirectory: true)
            let files = try XCTUnwrap(fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ))
            return files.compactMap { item -> String? in
                guard let fileURL = item as? URL,
                      fileURL.pathExtension == "swift",
                      (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else {
                    return nil
                }
                return fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            }
        }.sorted()
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func lineNumber(in text: String, atUTF16Location location: Int) -> Int {
        let index = String.Index(utf16Offset: location, in: text)
        return text[..<index].filter { $0 == "\n" }.count + 1
    }
}

private struct StringCatalog {
    let locales: Set<String>
    let keys: Set<String>
    private let localizedLocalesByKey: [String: Set<String>]

    static func load(resourceName: String) throws -> StringCatalog {
        let bundle = Bundle.main
        let locales = Set(bundle.localizations).subtracting(["Base"])
        var localizedLocalesByKey: [String: Set<String>] = [:]

        for locale in locales {
            let stringsURL = bundle.bundleURL
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("\(resourceName).strings")
            guard FileManager.default.fileExists(atPath: stringsURL.path) else {
                continue
            }

            let data = try Data(contentsOf: stringsURL)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let strings = object as? [String: String] else {
                throw StringCatalogError.invalidStringsFile(stringsURL)
            }

            for (key, value) in strings where !value.isEmpty {
                localizedLocalesByKey[key, default: []].insert(locale)
            }
        }

        return StringCatalog(
            locales: locales,
            keys: Set(localizedLocalesByKey.keys),
            localizedLocalesByKey: localizedLocalesByKey
        )
    }

    func keysWithMissingLocalizations(requiredLocales: Set<String>) -> [String: [String]] {
        localizedLocalesByKey.reduce(into: [String: [String]]()) { partialResult, entry in
            let missing = requiredLocales.subtracting(entry.value)
            if !missing.isEmpty {
                partialResult[entry.key] = missing.sorted()
            }
        }
    }
}

private enum StringCatalogError: Error {
    case invalidStringsFile(URL)
}

private struct SourceStringCatalog {
    private let strings: [String: Any]

    var keys: Set<String> {
        Set(strings.keys)
    }

    static func load(relativePath: String) throws -> SourceStringCatalog {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let root = try XCTUnwrap(object as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        return SourceStringCatalog(strings: strings)
    }

    func value(for key: String, locale: String) -> String? {
        guard let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any],
              let localeEntry = localizations[locale] as? [String: Any],
              let stringUnit = localeEntry["stringUnit"] as? [String: Any]
        else {
            return nil
        }
        return stringUnit["value"] as? String
    }

    func englishWords(in locale: String) -> [(key: String, word: String)] {
        guard let expression = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9/+.-]*"#),
              let formatExpression = try? NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.\d+)?[A-Za-z@]"#),
              let variableExpression = try? NSRegularExpression(pattern: #"\$\{[^}]+\}"#)
        else {
            XCTFail("English word detection regular expression is invalid")
            return []
        }
        return strings.keys.sorted().flatMap { key -> [(key: String, word: String)] in
            guard let value = value(for: key, locale: locale) else {
                return []
            }
            let withoutFormats = formatExpression.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value),
                withTemplate: ""
            )
            let cleaned = variableExpression.stringByReplacingMatches(
                in: withoutFormats,
                range: NSRange(withoutFormats.startIndex..<withoutFormats.endIndex, in: withoutFormats),
                withTemplate: ""
            )
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            return expression.matches(in: cleaned, range: range).compactMap { match in
                guard let matchRange = Range(match.range, in: cleaned) else {
                    return nil
                }
                return (key: key, word: String(cleaned[matchRange]))
            }
        }
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
