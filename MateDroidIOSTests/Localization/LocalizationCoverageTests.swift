import Foundation
import XCTest
@testable import MateDroidIOS

final class LocalizationCoverageTests: XCTestCase {
    func testAppTextUsesSelectedBundledLocalization() {
        XCTAssertEqual(AppText.localized("Settings", "设置", language: .german), "Einstellungen")
        XCTAssertEqual(AppText.localized("Save", "保存", language: .spanish), "Guardar")
        XCTAssertEqual(AppText.localized("Currency", "货币", language: .italian), "Valuta")
        XCTAssertEqual(AppText.localized("Follow System", "跟随系统", language: .catalan), "Segueix el sistema")
        XCTAssertEqual(AppText.localized("Battery Calibration", "电池校准", language: .german), "Batteriekalibrierung")
        XCTAssertEqual(AppText.localized("API Capabilities", "API 能力", language: .spanish), "Capacidades de la API")
        XCTAssertEqual(AppText.localized("Range Now", "当前续航", language: .italian), "Autonomia attuale")
        XCTAssertEqual(AppText.localized("Server Statistics", "服务端统计", language: .catalan), "Estadístiques del servidor")
        XCTAssertEqual(AppText.localized("Drive", "行驶", language: .german), "Fahrt")
        XCTAssertEqual(AppText.localized("Delete Trip", "删除路程", language: .spanish), "Eliminar viaje")
        XCTAssertEqual(AppText.localized("Shows the latest read-only car status.", "显示最新的只读车辆状态。", language: .italian), "Mostra lo stato più recente del veicolo in sola lettura.")
        XCTAssertEqual(AppText.localized("Current Alerts", "当前警报", language: .catalan), "Alertes actuals")
        XCTAssertEqual(AppText.localized("No Active Charge", "没有正在充电", language: .german), "Kein aktiver Ladevorgang")
        XCTAssertEqual(AppText.localized("No comparable charges", "暂无可比较充电", language: .spanish), "No hay cargas comparables")
        XCTAssertEqual(AppText.localized("Updates per Month", "每月更新", language: .italian), "Aggiornamenti al mese")
        XCTAssertEqual(AppText.localized("Comparing drives", "正在比较行程", language: .catalan), "Comparant trajectes")
        XCTAssertEqual(AppText.localized("AC Charge", "交流充电", language: .german), "AC-Ladevorgang")
        XCTAssertEqual(AppText.localized("Sort", "排序", language: .spanish), "Ordenar")
        XCTAssertEqual(AppText.localized("Fallback", "回退", language: .italian), "Alternativa")
        XCTAssertEqual(AppText.localized("Imperial (mi, °F, psi)", "英制（mi、°F、psi）", language: .catalan), "Unitats imperials (mi, °F, psi)")
        XCTAssertEqual(AppText.localized("Settings", "设置", language: .chinese), "设置")
        XCTAssertEqual(AppText.localized("Settings", "设置", language: .traditionalChinese), "設定")
        XCTAssertEqual(AppText.localized("Settings", "设置", language: .english), "Settings")
    }

    func testTraditionalChineseRegionDetectionIsExplicit() {
        XCTAssertTrue(AppText.usesTraditionalChinese(language: .traditionalChinese))
        XCTAssertTrue(AppText.usesTraditionalChinese(language: .system, preferredLanguage: "zh-Hant-TW"))
        XCTAssertTrue(AppText.usesTraditionalChinese(language: .system, preferredLanguage: "zh-HK"))
        XCTAssertFalse(AppText.usesTraditionalChinese(language: .system, preferredLanguage: "zh-Hans-CN"))
        XCTAssertFalse(AppText.usesTraditionalChinese(language: .system, preferredLanguage: "zh"))
        XCTAssertFalse(AppText.usesTraditionalChinese(language: .chinese))
    }

    private let requiredLocales: Set<String> = ["en", "it", "es", "ca", "de", "zh-Hans", "zh-Hant"]
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
        XCTAssertTrue(catalog.locales.contains("it"))
        XCTAssertTrue(catalog.locales.contains("es"))
        XCTAssertTrue(catalog.locales.contains("ca"))
        XCTAssertTrue(catalog.locales.contains("de"))
        XCTAssertTrue(catalog.locales.contains("zh-Hans"))
        XCTAssertTrue(catalog.locales.contains("zh-Hant"))
    }

    func testAllRequiredFeatureKeysExist() throws {
        let catalog = try StringCatalog.load(resourceName: "Localizable")
        let missingKeys = requiredFeatureKeys.subtracting(catalog.keys)

        XCTAssertTrue(missingKeys.isEmpty, "Missing localized feature keys: \(missingKeys.sorted().joined(separator: ", "))")
    }

    func testChineseSourceLocalizationsDoNotExposeShortEnglishChargeTypeLabels() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDroidIOS/Resources/Localizable.xcstrings")

        XCTAssertEqual(sourceCatalog.value(for: "AC", locale: "zh-Hans"), "交流")
        XCTAssertEqual(sourceCatalog.value(for: "DC", locale: "zh-Hans"), "直流")
        XCTAssertEqual(sourceCatalog.value(for: "AC", locale: "zh-Hant"), "交流")
        XCTAssertEqual(sourceCatalog.value(for: "DC", locale: "zh-Hant"), "直流")
    }

    func testEuropeanPricingSurfacesAreActuallyTranslated() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDroidIOS/Resources/Localizable.xcstrings")
        let pricingKeys = [
            "API Cost", "Charge Cost", "Charge Curves", "Charge Energy", "Clear Manual Cost",
            "Cost Source", "Has Cost", "Local manual price", "Manual Cost", "No Cost",
            "No cost recorded", "No pricing rule matched this charge", "Price per kWh",
            "Pricing Rule", "Charge Pricing", "Pricing Rules", "No pricing rules",
            "Add rules to estimate charging cost by location, time, and charger type.",
            "Add Pricing Rule", "Add Segment", "Rule", "Name", "Enabled", "Disabled",
            "Charger Type", "Default Price per kWh", "Delete", "Any", "Address Keyword",
            "Latitude", "Longitude", "Radius Meters", "Time", "Start Time", "End Time",
            "Price", "Price Segments", "Session Fee", "Priority", "Cancel", "Save Cost",
            "TeslaMate API price", "Total Cost", "segments", "Any location", "All day",
            "All dates", "From", "Through", "Enter a valid non-negative default price.",
            "Session fee must be a non-negative number.",
            "Latitude, longitude, and radius must be entered together.",
            "Enter valid coordinates and a radius greater than zero.",
            "Start and end time must be entered together.", "Enter a valid rule time in HH:mm format.",
            "The effective start date must not be after the end date.",
            "Complete every price segment with valid times and a non-negative price.",
            "Price segments cannot overlap."
        ]
        let locales = ["ca", "de", "es", "it"]
        let untranslated = locales.flatMap { locale in
            pricingKeys.compactMap { key -> String? in
                guard let localized = sourceCatalog.value(for: key, locale: locale),
                      let english = sourceCatalog.value(for: key, locale: "en")
                else { return "\(locale):\(key)=missing" }
                return localized == english ? "\(locale):\(key)" : nil
            }
        }

        XCTAssertTrue(untranslated.isEmpty, "Untranslated European pricing strings: \(untranslated.joined(separator: ", "))")
    }

    func testEuropeanBatteryAndDiagnosticSurfacesAreActuallyTranslated() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDroidIOS/Resources/Localizable.xcstrings")
        let featureKeys = [
            "Battery Calibration", "Battery Health Note", "At 100%", "Capacity Loss",
            "Capacity New", "Capacity Now", "Current SOC", "New Battery Rated Range",
            "Recording Start Odometer", "Health Confidence", "Range Loss", "Range New",
            "Range Now", "Rated Range", "Battery History", "Battery unavailable",
            "Server Version", "API Capabilities", "Server Statistics", "Unified Activities",
            "Drive Insights", "Available", "Limited", "Unavailable"
        ]
        let locales = ["ca", "de", "es", "it"]
        let untranslated = locales.flatMap { locale in
            featureKeys.compactMap { key -> String? in
                guard let localized = sourceCatalog.value(for: key, locale: locale),
                      let english = sourceCatalog.value(for: key, locale: "en")
                else { return "\(locale):\(key)=missing" }
                return localized == english ? "\(locale):\(key)" : nil
            }
        }

        XCTAssertTrue(untranslated.isEmpty, "Untranslated European battery/diagnostic strings: \(untranslated.joined(separator: ", "))")
    }

    func testEuropeanDashboardTripAndWidgetSurfacesAreActuallyTranslated() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDroidIOS/Resources/Localizable.xcstrings")
        let featureKeys = [
            "Car Image", "Charge Starting", "Charged", "Current", "Current Alerts",
            "Driving", "Last 6 Days", "Sentry", "Drive", "Delete Trip", "Drive Distance",
            "Legs", "Loading trip", "Loading trips", "No trips found", "Rename",
            "Route Drives", "Session", "Trip not found", "View Charge", "View Drive",
            "Shows the latest read-only car status.", "Edit", "Type"
        ]
        let locales = ["ca", "de", "es", "it"]
        let untranslated = locales.flatMap { locale in
            featureKeys.compactMap { key -> String? in
                guard let localized = sourceCatalog.value(for: key, locale: locale),
                      let english = sourceCatalog.value(for: key, locale: "en")
                else { return "\(locale):\(key)=missing" }
                return localized == english ? "\(locale):\(key)" : nil
            }
        }

        XCTAssertTrue(untranslated.isEmpty, "Untranslated European dashboard/trip/widget strings: \(untranslated.joined(separator: ", "))")
    }

    func testEuropeanChargeComparisonAndUpdateSurfacesAreActuallyTranslated() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDroidIOS/Resources/Localizable.xcstrings")
        let featureKeys = [
            "6 Months", "Average Gap", "Avg Duration", "Avg Efficiency", "Comparing drives",
            "Energy Added", "Loading comparison", "Loading current charge", "Longest",
            "Longest Drive", "Most Efficient", "Newest", "No Active Charge",
            "No comparable charges", "No comparable drives", "No curve data", "Oldest",
            "Records", "Similar Charges",
            "TeslaMate has not published the active charge yet.",
            "The car is not currently charging.", "Updates per Month", "Variant"
        ]
        let locales = ["ca", "de", "es", "it"]
        let untranslated = locales.flatMap { locale in
            featureKeys.compactMap { key -> String? in
                guard let localized = sourceCatalog.value(for: key, locale: locale),
                      let english = sourceCatalog.value(for: key, locale: "en")
                else { return "\(locale):\(key)=missing" }
                return localized == english ? "\(locale):\(key)" : nil
            }
        }

        XCTAssertTrue(untranslated.isEmpty, "Untranslated European charge/compare/update strings: \(untranslated.joined(separator: ", "))")
    }

    func testEuropeanEnglishEquivalentStringsAreExplicitlyAllowed() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDroidIOS/Resources/Localizable.xcstrings")
        let allowed: [String: Set<String>] = [
            "ca": ["AC", "Accent", "Cost", "SOC", "DC", "Error", "MateDrive", "Quicksilver", "Vehicle", "AC / DC", "Regions"],
            "de": ["AC", "Tesla Supercharger", "SOC", "DC", "MateDrive", "Midnight Cherry", "Midnight Silver", "Pearl White", "Quicksilver", "Server", "Solid Black", "Start", "Stealth Grey", "Trips", "Ultra Red", "Version", "Widget", "AC / DC"],
            "es": ["AC", "SOC", "DC", "Error", "MateDrive", "Quicksilver", "Widget", "AC / DC"],
            "it": ["AC", "SOC", "DC", "MateDrive", "Quicksilver", "Server", "Widget", "AC / DC"]
        ]

        for locale in allowed.keys.sorted() {
            let equivalent = Set(sourceCatalog.keys.compactMap { key -> String? in
                guard let localized = sourceCatalog.value(for: key, locale: locale),
                      let english = sourceCatalog.value(for: key, locale: "en"),
                      localized == english
                else { return nil }
                return key
            })
            XCTAssertEqual(equivalent, allowed[locale], "Unexpected or stale English-equivalent strings for \(locale)")
        }
    }

    func testChineseSourceLocalizationsDoNotExposeUnexpectedEnglishWords() throws {
        let sourceCatalog = try SourceStringCatalog.load(relativePath: "MateDroidIOS/Resources/Localizable.xcstrings")
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
        let swiftSources = try swiftSourcePaths(in: ["MateDroidIOS", "MateDroidWidget"])
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
        let swiftSources = try swiftSourcePaths(in: ["MateDroidIOS", "MateDroidWidget"])
        var checkedTitles = 0
        var missingMappings: [String] = []

        for path in swiftSources {
            let text = try loadSourceText(path)
            let textRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = callExpression.matches(in: text, range: textRange)
            for match in matches {
                guard let keyRange = Range(match.range(at: 1), in: text) else {
                    continue
                }
                checkedTitles += 1
                let key = String(text[keyRange])
                let localized = DashboardTextFormatter.title(key, language: .chinese)
                if localized == key {
                    let line = lineNumber(in: text, atUTF16Location: match.range.location)
                    missingMappings.append("\(path):\(line) \(key)")
                }
            }
        }

        XCTAssertGreaterThan(checkedTitles, 0, "Expected DashboardTextFormatter title calls to be checked")
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
        let settingsSource = try String(contentsOf: repositoryRoot.appendingPathComponent("MateDroidIOS/Features/Settings/SettingsView.swift"), encoding: .utf8)
        let diagnosticSource = try String(contentsOf: repositoryRoot.appendingPathComponent("MateDroidIOS/Core/API/TeslaMateConnectionDiagnostic.swift"), encoding: .utf8)

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
            UserFacingErrorLocalizer.localized("The request timed out.", language: .english),
            "The request timed out."
        )
    }

    func testAllLocalizedKeysCoverRequiredLocales() throws {
        let catalog = try StringCatalog.load(resourceName: "Localizable")
        let missing = catalog.keysWithMissingLocalizations(requiredLocales: requiredLocales)

        XCTAssertTrue(missing.isEmpty, "Missing localizations: \(missing)")
    }

    private static let allowedChineseTechnicalWords: Set<String> = [
        "AC",
        "API",
        "Cloudflare",
        "DC",
        "HTTP",
        "MateDrive",
        "SOC",
        "SSL",
        "TeslaMate",
        "URL",
        "Wh",
        "iOS",
        "kW",
        "kWh",
        "km"
    ]

    private func loadSourceText(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
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
              let formatExpression = try? NSRegularExpression(pattern: #"%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.\d+)?[A-Za-z@]"#)
        else {
            XCTFail("English word detection regular expression is invalid")
            return []
        }
        return strings.keys.sorted().flatMap { key -> [(key: String, word: String)] in
            guard let value = value(for: key, locale: locale) else {
                return []
            }
            let cleaned = formatExpression.stringByReplacingMatches(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value),
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
