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
