import Foundation

public struct VehicleImageDescriptor: Equatable, Sendable {
    public let model: String?
    public let modelYear: Int?
    public let trimBadging: String?
    public let wheelType: String?
    public let exteriorColor: String?
    public let spoilerType: String?

    public init(
        model: String?,
        modelYear: Int?,
        trimBadging: String?,
        wheelType: String?,
        exteriorColor: String?,
        spoilerType: String?
    ) {
        self.model = model
        self.modelYear = modelYear
        self.trimBadging = trimBadging
        self.wheelType = wheelType
        self.exteriorColor = exteriorColor
        self.spoilerType = spoilerType
    }
}

public struct VehicleImageResolution: Equatable, Sendable {
    public let assetID: String?
    public let generationID: String?
    public let trimID: String?
    public let colorID: String?
    public let wheelID: String?
    public let assetPath: String
    public let presentationScale: Double
    public let confidence: VehicleImageConfidence
    public let evidence: [VehicleImageEvidence]
    public let conflicts: [VehicleImageConflict]
    public let usesLegacyAsset: Bool
}

public enum VehicleImageConfidence: String, Equatable, Sendable {
    case exact
    case inferred
    case fallback
    case manual
}

public enum VehicleImageEvidence: String, Equatable, Sendable, CustomStringConvertible {
    case override
    case model
    case year
    case explicitTrim
    case generationSpecificWheel
    case color
    case `default`

    public var description: String { rawValue }
}

public enum VehicleImageConflict: String, Equatable, Sendable {
    case reportedWheelContradictsFactoryTrim
    case invalidManualOverride
    case modelYearUnavailable
    case modelYearOutsideCatalog
    case unknownModel
}

public struct VehicleImageManualOverride: Equatable, Sendable {
    public let generationID: String
    public let trimID: String
    public let colorID: String
    public let wheelID: String
    public let assetID: String

    public init(
        generationID: String,
        trimID: String,
        colorID: String,
        wheelID: String,
        assetID: String
    ) {
        self.generationID = generationID
        self.trimID = trimID
        self.colorID = colorID
        self.wheelID = wheelID
        self.assetID = assetID
    }
}

public struct VehicleImageResolver: Sendable {
    public static let genericPlaceholderPath = "system://car.fill"

    private let catalog: VehicleImageCatalog

    public init(catalog: VehicleImageCatalog) {
        self.catalog = catalog
    }

    public func resolve(
        _ descriptor: VehicleImageDescriptor,
        manualOverride: VehicleImageManualOverride? = nil
    ) -> VehicleImageResolution {
        var conflicts: [VehicleImageConflict] = []

        if let manualOverride {
            if let resolution = manualResolution(for: manualOverride) {
                return resolution
            }
            conflicts.append(.invalidManualOverride)
        }

        let modelValue = Self.normalize(descriptor.model)
        var candidates = catalog.generations.filter { generation in
            Self.matches(modelValue, id: generation.model, aliases: generation.aliases)
        }
        guard !candidates.isEmpty else {
            return VehicleImageResolution(
                assetID: nil,
                generationID: nil,
                trimID: nil,
                colorID: nil,
                wheelID: nil,
                assetPath: Self.genericPlaceholderPath,
                presentationScale: 1,
                confidence: .fallback,
                evidence: [],
                conflicts: conflicts + [.unknownModel],
                usesLegacyAsset: false
            )
        }

        var evidence: [VehicleImageEvidence] = [.model]
        var inferred = false

        if let modelYear = descriptor.modelYear {
            let yearMatches = candidates.filter { generation in
                modelYear >= generation.yearStart && modelYear <= (generation.yearEnd ?? Int.max)
            }
            if yearMatches.isEmpty {
                conflicts.append(.modelYearOutsideCatalog)
                inferred = true
            } else {
                candidates = yearMatches
                evidence.append(.year)
            }
        } else {
            conflicts.append(.modelYearUnavailable)
            inferred = true
        }

        let trimValue = Self.normalize(descriptor.trimBadging)
        let trimMatches = candidates.compactMap { generation -> (VehicleGenerationRecord, VehicleTrimRecord)? in
            guard let trim = generation.trims.first(where: {
                Self.matches(trimValue, id: $0.id, aliases: $0.aliases)
            }) else { return nil }
            return (generation, trim)
        }
        if !trimMatches.isEmpty {
            candidates = trimMatches.map(\.0)
            evidence.append(.explicitTrim)
        }

        let wheelValue = Self.normalize(descriptor.wheelType)
        let wheelMatches = candidates.compactMap { generation -> (VehicleGenerationRecord, VehicleWheelRecord)? in
            guard let wheel = generation.wheels.first(where: {
                Self.matches(wheelValue, id: $0.id, aliases: $0.aliases, acceptsSuffix: true)
            }) else { return nil }
            return (generation, wheel)
        }
        if !wheelMatches.isEmpty {
            candidates = wheelMatches.map(\.0)
            evidence.append(.generationSpecificWheel)
        }

        let colorValue = Self.normalize(descriptor.exteriorColor)
        let colorMatches = candidates.compactMap { generation -> (VehicleGenerationRecord, VehicleColorRecord)? in
            guard let color = generation.colors.first(where: {
                Self.matches(colorValue, id: $0.id, aliases: $0.aliases)
            }) else { return nil }
            return (generation, color)
        }
        if !colorMatches.isEmpty {
            candidates = colorMatches.map(\.0)
            evidence.append(.color)
        }

        let generation = candidates.min { $0.matcherPriority < $1.matcherPriority }!
        let matchedTrim = generation.trims.first(where: {
            Self.matches(trimValue, id: $0.id, aliases: $0.aliases)
        })
        let trim = matchedTrim ?? generation.trims.first(where: { $0.id == generation.defaultTrimID })!
        let matchedWheel = generation.wheels.first(where: {
            Self.matches(wheelValue, id: $0.id, aliases: $0.aliases, acceptsSuffix: true)
        })
        let wheel = matchedWheel ?? generation.wheels.first(where: { $0.id == generation.defaultWheelID })!
        let matchedColor = generation.colors.first(where: {
            Self.matches(colorValue, id: $0.id, aliases: $0.aliases)
        })
        let color = matchedColor ?? generation.colors.first(where: { $0.id == generation.defaultColorID })!

        if matchedTrim == nil || matchedWheel == nil || matchedColor == nil {
            inferred = true
            evidence.append(.default)
        }

        if descriptor.wheelType != nil,
           evidence.contains(.explicitTrim),
           !evidence.contains(.generationSpecificWheel) {
            conflicts.append(.reportedWheelContradictsFactoryTrim)
            inferred = true
        }

        let exactReviewedAsset = catalog.reviewedAsset(
            generationID: generation.id,
            trimID: trim.id,
            colorID: color.id,
            wheelID: wheel.id
        )
        if let exactReviewedAsset {
            return resolution(
                asset: exactReviewedAsset,
                generation: generation,
                evidence: evidence,
                conflicts: conflicts,
                confidence: inferred ? .inferred : .exact
            )
        }

        let defaultWheelID = generation.defaultWheelID
        let defaultColorID = generation.defaultColorID
        let reviewedFallback = catalog.reviewedAsset(
            generationID: generation.id,
            trimID: trim.id,
            colorID: color.id,
            wheelID: defaultWheelID
        ) ?? catalog.reviewedAsset(
            generationID: generation.id,
            trimID: trim.id,
            colorID: defaultColorID,
            wheelID: defaultWheelID
        )
        if let reviewedFallback {
            return resolution(
                asset: reviewedFallback,
                generation: generation,
                evidence: Self.appendingDefault(to: evidence),
                conflicts: conflicts,
                confidence: .inferred
            )
        }

        let legacyAsset = catalog.assets.first { $0.id == generation.legacyFallback.assetID }
        guard let legacyAsset else {
            return VehicleImageResolution(
                assetID: nil,
                generationID: generation.id,
                trimID: trim.id,
                colorID: color.id,
                wheelID: wheel.id,
                assetPath: Self.genericPlaceholderPath,
                presentationScale: Self.presentationScale(for: generation.id),
                confidence: .fallback,
                evidence: Self.appendingDefault(to: evidence),
                conflicts: conflicts,
                usesLegacyAsset: false
            )
        }
        return resolution(
            asset: legacyAsset,
            generation: generation,
            evidence: Self.appendingDefault(to: evidence),
            conflicts: conflicts,
            confidence: .fallback
        )
    }

    private func manualResolution(for override: VehicleImageManualOverride) -> VehicleImageResolution? {
        guard let generation = catalog.generations.first(where: { $0.id == override.generationID }),
              let asset = catalog.preferredAsset(
                  generationID: override.generationID,
                  trimID: override.trimID,
                  colorID: override.colorID,
                  wheelID: override.wheelID,
                  requestedAssetID: override.assetID
              )
        else { return nil }

        return resolution(
            asset: asset,
            generation: generation,
            evidence: [.override],
            conflicts: [],
            confidence: .manual
        )
    }

    private func resolution(
        asset: VehicleAssetRecord,
        generation: VehicleGenerationRecord,
        evidence: [VehicleImageEvidence],
        conflicts: [VehicleImageConflict],
        confidence: VehicleImageConfidence
    ) -> VehicleImageResolution {
        VehicleImageResolution(
            assetID: asset.id,
            generationID: generation.id,
            trimID: asset.trimID,
            colorID: asset.colorID,
            wheelID: asset.wheelID,
            assetPath: asset.path,
            presentationScale: Self.presentationScale(for: generation.id),
            confidence: confidence,
            evidence: evidence,
            conflicts: conflicts,
            usesLegacyAsset: asset.reviewStatus == .legacy
        )
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map { String($0).lowercased() }
            .joined()
        return normalized.isEmpty ? nil : normalized
    }

    private static func matches(
        _ normalizedValue: String?,
        id: String,
        aliases: [String],
        acceptsSuffix: Bool = false
    ) -> Bool {
        guard let normalizedValue else { return false }
        return ([id] + aliases).contains { candidate in
            guard let normalizedCandidate = normalize(candidate) else { return false }
            return normalizedValue == normalizedCandidate ||
                (acceptsSuffix && normalizedValue.hasPrefix(normalizedCandidate))
        }
    }

    private static func presentationScale(for generationID: String) -> Double {
        if generationID.hasPrefix("model-3-highland") { return 1.35 }
        if generationID.hasPrefix("model-y-juniper") { return 1.25 }
        if generationID.hasPrefix("model-x") { return 1.4 }
        return 1
    }

    private static func appendingDefault(to evidence: [VehicleImageEvidence]) -> [VehicleImageEvidence] {
        evidence.last == .default ? evidence : evidence + [.default]
    }
}

public enum VINModelYearDecoder {
    private static let codes = Array("ABCDEFGHJKLMNPRSTVWXY123456789")

    public static func modelYear(from vin: String, validYears: ClosedRange<Int>) -> Int? {
        let rawScalars = vin.unicodeScalars
        guard rawScalars.count == 17,
              rawScalars.allSatisfy({ scalar in
                  scalar.isASCII &&
                      ((48...57).contains(scalar.value) ||
                          (65...90).contains(scalar.value) ||
                          (97...122).contains(scalar.value))
              })
        else { return nil }

        let normalizedVIN = vin.uppercased()
        let yearIndex = normalizedVIN.index(normalizedVIN.startIndex, offsetBy: 9)
        let yearCharacter = normalizedVIN[yearIndex]
        guard let codeIndex = codes.firstIndex(of: yearCharacter) else { return nil }

        let firstYear = 1980 + codeIndex
        let matches = stride(from: firstYear, through: validYears.upperBound, by: 30)
            .filter(validYears.contains)
        return matches.count == 1 ? matches[0] : nil
    }
}
