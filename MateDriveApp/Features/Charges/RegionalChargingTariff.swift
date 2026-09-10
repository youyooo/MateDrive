import Foundation

public enum RegionalTariffStatus: String, Codable, Sendable {
    case active
    case historical
    case superseded
}

public enum RegionalTariffAvailability: String, Codable, Sendable {
    case verified
    case noVerifiedDedicatedTariff
}

public struct RegionalChargingTariffRegion: Codable, Equatable, Sendable {
    public let regionCode: String
    public let names: [String: String]
    public let availability: RegionalTariffAvailability
    public let verifiedAt: String
    public let tariffs: [RegionalChargingTariff]
}

public struct RegionalChargingTariff: Codable, Equatable, Sendable {
    public let id: String
    public let status: RegionalTariffStatus
    public let customerClass: String
    public let chargeType: ChargePricingChargeType
    public let currencyCode: String
    public let effectiveFromDate: String
    public let effectiveToDate: String?
    public let documentID: String
    public let sourceURL: URL
    public let basePricePerKWh: Double
    public let timeSegments: [ChargePricingTimeSegment]
    public let serviceFeePerKWh: Double
    public let sessionFee: Double
    public let applicableWeekdays: [Int]?
    public let applicableMonths: [Int]?
}

public enum RegionalChargingTariffCatalogError: Error, Equatable, Sendable {
    case resourceNotFound
    case duplicateRegionCode(String)
    case duplicateTariffID(String)
    case invalidEffectiveDate(String)
    case invalidEffectiveDateRange(String)
}

public struct RegionalChargingTariffCatalog: Codable, Equatable, Sendable {
    public let version: Int
    public let generatedAt: String
    public let regions: [RegionalChargingTariffRegion]

    public static func load(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "RegionalChargingTariffs", withExtension: "json") else {
            throw RegionalChargingTariffCatalogError.resourceNotFound
        }

        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try catalog.validateDateRanges()
        return catalog
    }

    public func entry(regionCode: String, date: Date) -> RegionalChargingTariff? {
        guard let region = regions.first(where: { $0.regionCode == regionCode }) else {
            return nil
        }

        guard let localDate = ChargePricingDate.localDate(from: date) else {
            return nil
        }
        return region.tariffs
            .filter { tariff in
                tariff.effectiveFromDate <= localDate &&
                    (tariff.effectiveToDate.map { localDate <= $0 } ?? true)
            }
            .sorted { lhs, rhs in
                if lhs.effectiveFromDate != rhs.effectiveFromDate {
                    return lhs.effectiveFromDate > rhs.effectiveFromDate
                }
                return lhs.id > rhs.id
            }
            .first
    }

    public func entryForEstimate(regionCode: String, date: Date) -> RegionalChargingTariff? {
        if let exact = entry(regionCode: regionCode, date: date) { return exact }
        return regions.first(where: { $0.regionCode == regionCode })?.tariffs
            .filter { $0.status != .superseded }
            .sorted { $0.effectiveFromDate > $1.effectiveFromDate }
            .first
    }

    public func estimationRule(regionCode: String, date: Date) -> ChargePricingRule? {
        guard let entry = entryForEstimate(regionCode: regionCode, date: date) else {
            return nil
        }
        var rule = makePricingRule(regionCode: regionCode, from: entry)
        if entry.effectiveToDate != nil, self.entry(regionCode: regionCode, date: date) == nil {
            rule.id += "-reference-estimate"
            rule.effectiveToDate = nil
        }
        return rule
    }

    public func localizedRuleName(
        regionCode: String,
        isHistoricalReference: Bool,
        language: AppLanguage
    ) -> String {
        let region = regions.first { $0.regionCode == regionCode }
        let englishRegion = region?.names["en"] ?? regionCode
        let chineseRegion = region?.names["zh-Hans"] ?? englishRegion
        if isHistoricalReference {
            return AppText.localized(
                "\(englishRegion) residential EV historical reference",
                "\(chineseRegion)居民电动汽车历史参考电价",
                language: language
            )
        }
        return AppText.localized(
            "\(englishRegion) residential EV tariff",
            "\(chineseRegion)居民电动汽车电价",
            language: language
        )
    }

    public func regionCode(matchingAddress address: String?) -> String? {
        guard let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else {
            return nil
        }
        let directMatch = regions
            .flatMap { region in region.names.values.map { (region.regionCode, $0) } }
            .filter { !$0.1.isEmpty && address.localizedCaseInsensitiveContains($0.1) }
            .sorted { $0.1.count > $1.1.count }
            .first?.0
        if let directMatch {
            return directMatch
        }
        return Self.mainlandAddressAliases.first { code, aliases in
            aliases.contains { address.localizedCaseInsensitiveContains($0) }
        }?.key
    }

    private static let mainlandAddressAliases: [String: [String]] = [
        "CN-11": ["北京"], "CN-12": ["天津"], "CN-13": ["石家庄"],
        "CN-14": ["太原"], "CN-15": ["呼和浩特"], "CN-21": ["沈阳"],
        "CN-22": ["长春"], "CN-23": ["哈尔滨"], "CN-31": ["上海"],
        "CN-32": ["南京"], "CN-33": ["杭州"], "CN-34": ["合肥"],
        "CN-35": ["福州"], "CN-36": ["南昌"], "CN-37": ["济南"],
        "CN-41": ["郑州"], "CN-42": ["武汉"],
        "CN-43": ["长沙", "岳麓区", "望城区"],
        "CN-44": ["广州"], "CN-45": ["南宁"], "CN-46": ["海口"],
        "CN-50": ["重庆"], "CN-51": ["成都"], "CN-52": ["贵阳"],
        "CN-53": ["昆明"], "CN-54": ["拉萨"], "CN-61": ["西安"],
        "CN-62": ["兰州"], "CN-63": ["西宁"], "CN-64": ["银川"],
        "CN-65": ["乌鲁木齐"]
    ]

    public func makePricingRule(regionCode: String, from entry: RegionalChargingTariff) -> ChargePricingRule {
        let region = regions.first(where: { $0.regionCode == regionCode })
        let regionalName = region?.names["en"] ?? regionCode
        return ChargePricingRule(
            id: entry.id,
            name: "\(regionalName) residential EV",
            chargeType: entry.chargeType,
            effectiveFromDate: entry.effectiveFromDate,
            effectiveToDate: entry.effectiveToDate,
            pricePerKWh: entry.basePricePerKWh,
            timeSegments: entry.timeSegments.map {
                ChargePricingTimeSegment(
                    id: $0.id,
                    startMinuteOfDay: $0.startMinuteOfDay,
                    endMinuteOfDay: $0.endMinuteOfDay,
                    pricePerKWh: $0.pricePerKWh
                )
            },
            sessionFee: entry.sessionFee,
            origin: .regionalOfficial,
            regionCode: regionCode,
            sourceURL: entry.sourceURL.absoluteString,
            verifiedAt: region?.verifiedAt,
            serviceFeePerKWh: entry.serviceFeePerKWh,
            applicableWeekdays: entry.applicableWeekdays,
            applicableMonths: entry.applicableMonths,
            currencyCode: entry.currencyCode
        )
    }

    private func validateDateRanges() throws {
        var regionCodes = Set<String>()
        var tariffIDs = Set<String>()
        for region in regions {
            guard regionCodes.insert(region.regionCode).inserted else {
                throw RegionalChargingTariffCatalogError.duplicateRegionCode(region.regionCode)
            }
            guard Self.isStrictDate(region.verifiedAt) else {
                throw RegionalChargingTariffCatalogError.invalidEffectiveDate(region.verifiedAt)
            }
            for tariff in region.tariffs {
                guard tariffIDs.insert(tariff.id).inserted else {
                    throw RegionalChargingTariffCatalogError.duplicateTariffID(tariff.id)
                }
                guard Self.isStrictDate(tariff.effectiveFromDate) else {
                    throw RegionalChargingTariffCatalogError.invalidEffectiveDate(tariff.effectiveFromDate)
                }
                if let effectiveToDate = tariff.effectiveToDate {
                    guard Self.isStrictDate(effectiveToDate) else {
                        throw RegionalChargingTariffCatalogError.invalidEffectiveDate(effectiveToDate)
                    }
                    guard tariff.effectiveFromDate <= effectiveToDate else {
                        throw RegionalChargingTariffCatalogError.invalidEffectiveDateRange(tariff.id)
                    }
                }
            }
        }
    }

    private static func isStrictDate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }
}
