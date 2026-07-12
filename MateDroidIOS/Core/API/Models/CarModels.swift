import Foundation

public struct CarsResponse: Decodable, Sendable {
    public let data: CarsPayload?
    public let error: String?
}

public struct CarsPayload: Decodable, Sendable {
    public let cars: [CarData]
}

public struct CarData: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int { carId }

    public let carId: Int
    public let name: String?
    public let displayName: String
    public let carDetails: CarDetails?
    public let carExterior: CarExterior?
    public let carSettings: CarSettings?
    public let teslamateStats: TeslamateStats?
    public var vehicleModelName: String? {
        Self.resolvedModelName(model: carDetails?.model, trimBadging: carDetails?.trimBadging)
    }
    public var modelYear: Int? { carDetails?.modelYear }
    public var vehicleModelDescription: String? {
        guard let vehicleModelName else { return nil }
        return modelYear.map { "\($0) \(vehicleModelName)" } ?? vehicleModelName
    }
    public var dashboardDisplayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           !Self.isLegacyAppDisplayName(name)
        {
            return name
        }
        return vehicleModelDescription ?? displayName
    }
    public var dashboardPrimaryName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           !Self.isLegacyAppDisplayName(name)
        {
            return name
        }
        return vehicleModelName ?? displayName
    }

    public init(
        carId: Int,
        name: String? = nil,
        displayName: String? = nil,
        carDetails: CarDetails? = nil,
        carExterior: CarExterior? = nil,
        carSettings: CarSettings? = nil,
        teslamateStats: TeslamateStats? = nil
    ) {
        self.carId = carId
        self.name = name
        self.carDetails = carDetails
        self.carExterior = carExterior
        self.carSettings = carSettings
        self.teslamateStats = teslamateStats
        self.displayName = Self.resolvedDisplayName(
            name: name,
            displayName: displayName,
            model: carDetails?.model,
            trimBadging: carDetails?.trimBadging
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case carId
        case name
        case displayName
        case carDetails
        case carExterior
        case carSettings
        case teslamateStats
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        carId = try Self.decodeRequiredFlexibleInt(container, primaryKey: .carId, fallbackKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        carDetails = try container.decodeIfPresent(CarDetails.self, forKey: .carDetails)
        carExterior = try container.decodeIfPresent(CarExterior.self, forKey: .carExterior)
        carSettings = try container.decodeIfPresent(CarSettings.self, forKey: .carSettings)
        teslamateStats = try container.decodeIfPresent(TeslamateStats.self, forKey: .teslamateStats)
        displayName = Self.resolvedDisplayName(
            name: name,
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            model: carDetails?.model,
            trimBadging: carDetails?.trimBadging
        )
    }

    private static func decodeRequiredFlexibleInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        primaryKey: CodingKeys,
        fallbackKey: CodingKeys
    ) throws -> Int {
        if let value = try decodeFlexibleInt(container, forKey: primaryKey) {
            return value
        }
        if let value = try decodeFlexibleInt(container, forKey: fallbackKey) {
            return value
        }
        return try container.decode(Int.self, forKey: primaryKey)
    }

    private static func decodeFlexibleInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        }
        return nil
    }

    private static func resolvedDisplayName(name: String?, displayName: String?, model: String?, trimBadging: String?) -> String {
        if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            if !isLegacyAppDisplayName(displayName) {
                return displayName
            }
        }
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            if !isLegacyAppDisplayName(name) {
                return name
            }
        }
        if let modelName = resolvedModelName(model: model, trimBadging: trimBadging) {
            return modelName
        }
        return "Tesla"
    }

    public static func isLegacyAppDisplayName(_ value: String?) -> Bool {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }

        let compact = normalized
            .filter { $0.isLetter || $0.isNumber }

        return ["matedroid", "matedrive"].contains(compact)
            || compact.hasPrefix("matedroidios")
            || compact.hasPrefix("matedriveios")
            || compact.hasPrefix("matedroidmodel")
            || compact.hasPrefix("matedrivemodel")
    }

    private static func resolvedModelName(model: String?, trimBadging: String?) -> String? {
        guard let rawModel = model?.trimmingCharacters(in: .whitespacesAndNewlines), !rawModel.isEmpty else {
            return nil
        }

        let normalizedModel = rawModel
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        let baseName: String
        switch normalizedModel {
        case "3", "m3", "model3", "modelthree":
            baseName = "Model 3"
        case "y", "my", "modely":
            baseName = "Model Y"
        case "s", "ms", "models":
            baseName = "Model S"
        case "x", "mx", "modelx":
            baseName = "Model X"
        case "cybertruck", "ct":
            baseName = "Cybertruck"
        case "roadster":
            baseName = "Roadster"
        default:
            return rawModel.hasPrefix("Model ") ? rawModel : "Model \(rawModel)"
        }

        guard let rawTrim = trimBadging?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTrim.isEmpty else {
            return baseName
        }

        let normalizedTrim = rawTrim
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        if normalizedTrim.contains("plaid") {
            return "\(baseName) Plaid"
        }
        if normalizedTrim == "p" || normalizedTrim.hasPrefix("p") || normalizedTrim.contains("performance") {
            return "\(baseName) Performance"
        }
        if normalizedTrim == "lr" || normalizedTrim.contains("longrange") {
            return "\(baseName) Long Range"
        }

        return baseName
    }
}

public struct CarDetails: Decodable, Equatable, Sendable {
    public let model: String?
    public let trimBadging: String?
    public let vin: String?
    public let efficiency: Double?
    public var modelYear: Int? { Self.modelYear(fromVIN: vin) }

    public init(model: String? = nil, trimBadging: String? = nil, vin: String? = nil, efficiency: Double? = nil) {
        self.model = model
        self.trimBadging = trimBadging
        self.vin = vin
        self.efficiency = efficiency
    }

    public static func modelYear(fromVIN vin: String?, currentYear: Int = Calendar.current.component(.year, from: Date())) -> Int? {
        guard let vin = vin?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              vin.count == 17
        else {
            return nil
        }
        let code = vin[vin.index(vin.startIndex, offsetBy: 9)]
        let yearCodes = Array("ABCDEFGHJKLMNPRSTVWXY123456789")
        guard let offset = yearCodes.firstIndex(of: code) else { return nil }

        let candidates = stride(from: 1980 + offset, through: currentYear + 1, by: 30)
            .filter { $0 >= 2008 }
        return candidates.last
    }
}

public struct CarExterior: Decodable, Equatable, Sendable {
    public let exteriorColor: String?
    public let spoilerType: String?
    public let wheelType: String?

    public init(exteriorColor: String? = nil, spoilerType: String? = nil, wheelType: String? = nil) {
        self.exteriorColor = exteriorColor
        self.spoilerType = spoilerType
        self.wheelType = wheelType
    }
}

public struct CarSettings: Decodable, Equatable, Sendable {
    public let freeSupercharging: Bool?

    public init(freeSupercharging: Bool? = nil) {
        self.freeSupercharging = freeSupercharging
    }
}

public struct TeslamateStats: Decodable, Equatable, Sendable {
    public let totalCharges: Int?
    public let totalDrives: Int?
    public let totalUpdates: Int?

    public init(totalCharges: Int? = nil, totalDrives: Int? = nil, totalUpdates: Int? = nil) {
        self.totalCharges = totalCharges
        self.totalDrives = totalDrives
        self.totalUpdates = totalUpdates
    }
}
