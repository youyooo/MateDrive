import Foundation

public struct VehicleImageCatalog: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generations: [VehicleGenerationRecord]
    public let assets: [VehicleAssetRecord]

    public init(
        schemaVersion: Int,
        generations: [VehicleGenerationRecord],
        assets: [VehicleAssetRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.generations = generations
        self.assets = assets
    }

    public static func decode(
        from data: Data,
        bundledAssetPaths: Set<String>
    ) throws -> VehicleImageCatalog {
        let catalog = try JSONDecoder().decode(VehicleImageCatalog.self, from: data)
        try catalog.validate(bundledAssetPaths: bundledAssetPaths)
        return catalog
    }

    public func validate(bundledAssetPaths: Set<String>) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw VehicleImageCatalogValidationError.unsupportedSchemaVersion(schemaVersion)
        }

        try validateUniqueIDs(generations.map(\.id), duplicate: VehicleImageCatalogValidationError.duplicateGenerationID)
        try validateUniqueIDs(assets.map(\.id), duplicate: VehicleImageCatalogValidationError.duplicateAssetID)

        for generation in generations {
            if let yearEnd = generation.yearEnd, generation.yearStart > yearEnd {
                throw VehicleImageCatalogValidationError.invalidYearRange(
                    generationID: generation.id,
                    start: generation.yearStart,
                    end: yearEnd
                )
            }
            guard generation.trims.contains(where: { $0.id == generation.defaultTrimID }) else {
                throw VehicleImageCatalogValidationError.missingDefaultTrim(
                    generationID: generation.id,
                    trimID: generation.defaultTrimID
                )
            }
            guard generation.wheels.contains(where: { $0.id == generation.defaultWheelID }) else {
                throw VehicleImageCatalogValidationError.missingDefaultWheel(
                    generationID: generation.id,
                    wheelID: generation.defaultWheelID
                )
            }
            guard generation.colors.contains(where: { $0.id == generation.defaultColorID }) else {
                throw VehicleImageCatalogValidationError.missingDefaultColor(
                    generationID: generation.id,
                    colorID: generation.defaultColorID
                )
            }
            guard let fallbackAsset = assets.first(where: { $0.id == generation.legacyFallback.assetID }),
                  fallbackAsset.generationID == generation.id,
                  fallbackAsset.path == generation.legacyFallback.path
            else {
                throw VehicleImageCatalogValidationError.invalidLegacyFallback(generationID: generation.id)
            }
        }

        for (model, records) in Dictionary(grouping: generations, by: \.model) {
            let priorities = records.map(\.matcherPriority)
            if let priority = priorities.first(where: { value in priorities.filter({ $0 == value }).count > 1 }) {
                throw VehicleImageCatalogValidationError.tiedMatcherPriority(model: model, priority: priority)
            }
        }

        let generationsByID = Dictionary(uniqueKeysWithValues: generations.map { ($0.id, $0) })
        for asset in assets {
            guard let generation = generationsByID[asset.generationID],
                  generation.trims.contains(where: { $0.id == asset.trimID }),
                  generation.wheels.contains(where: { $0.id == asset.wheelID }),
                  generation.colors.contains(where: { $0.id == asset.colorID })
            else {
                throw VehicleImageCatalogValidationError.invalidAssetReference(assetID: asset.id)
            }
            guard bundledAssetPaths.contains(asset.path) else {
                throw VehicleImageCatalogValidationError.missingBundledAssetPath(asset.path)
            }
        }
    }

    public var preferredAssets: [VehicleAssetRecord] {
        var seen = Set<VehicleAssetConfiguration>()
        return assets.compactMap { asset in
            let configuration = VehicleAssetConfiguration(asset)
            guard seen.insert(configuration).inserted else { return nil }
            return preferredAsset(
                generationID: asset.generationID,
                trimID: asset.trimID,
                colorID: asset.colorID,
                wheelID: asset.wheelID
            )
        }
    }

    public func reviewedAsset(
        generationID: String,
        trimID: String,
        colorID: String,
        wheelID: String
    ) -> VehicleAssetRecord? {
        matchingAssets(
            generationID: generationID,
            trimID: trimID,
            colorID: colorID,
            wheelID: wheelID
        ).first { $0.reviewStatus == .reviewed }
    }

    public func preferredAsset(
        generationID: String,
        trimID: String,
        colorID: String,
        wheelID: String,
        requestedAssetID: String? = nil
    ) -> VehicleAssetRecord? {
        guard let generation = generations.first(where: { $0.id == generationID }) else { return nil }
        let matches = matchingAssets(
            generationID: generationID,
            trimID: trimID,
            colorID: colorID,
            wheelID: wheelID
        )
        if let requestedAssetID, !matches.contains(where: { $0.id == requestedAssetID }) {
            return nil
        }
        return matches.first { $0.reviewStatus == .reviewed } ?? matches.first {
            $0.reviewStatus == .legacy &&
                $0.id == generation.legacyFallback.assetID &&
                $0.path == generation.legacyFallback.path
        }
    }

    private func matchingAssets(
        generationID: String,
        trimID: String,
        colorID: String,
        wheelID: String
    ) -> [VehicleAssetRecord] {
        assets.filter {
            $0.generationID == generationID &&
                $0.trimID == trimID &&
                $0.colorID == colorID &&
                $0.wheelID == wheelID
        }
    }

    private func validateUniqueIDs(
        _ ids: [String],
        duplicate: (String) -> VehicleImageCatalogValidationError
    ) throws {
        var seen = Set<String>()
        for id in ids where !seen.insert(id).inserted {
            throw duplicate(id)
        }
    }
}

private struct VehicleAssetConfiguration: Hashable {
    let generationID: String
    let trimID: String
    let colorID: String
    let wheelID: String

    init(_ asset: VehicleAssetRecord) {
        generationID = asset.generationID
        trimID = asset.trimID
        colorID = asset.colorID
        wheelID = asset.wheelID
    }
}

public struct VehicleGenerationRecord: Codable, Equatable, Sendable {
    public let id: String
    public let model: String
    public let aliases: [String]
    public let yearStart: Int
    public let yearEnd: Int?
    public let matcherPriority: Int
    public let localizationKey: String
    public let trims: [VehicleTrimRecord]
    public let wheels: [VehicleWheelRecord]
    public let colors: [VehicleColorRecord]
    public let defaultTrimID: String
    public let defaultWheelID: String
    public let defaultColorID: String
    public let legacyFallback: VehicleLegacyFallbackRecord
}

public struct VehicleTrimRecord: Codable, Equatable, Sendable {
    public let id: String
    public let aliases: [String]
    public let localizationKey: String
}

public struct VehicleWheelRecord: Codable, Equatable, Sendable {
    public let id: String
    public let aliases: [String]
    public let localizationKey: String
}

public struct VehicleColorRecord: Codable, Equatable, Sendable {
    public let id: String
    public let aliases: [String]
    public let localizationKey: String
}

public enum VehicleImageReviewStatus: String, Codable, Equatable, Sendable {
    case legacy
    case reviewed
}

public struct VehicleAssetRecord: Codable, Equatable, Sendable {
    public let id: String
    public let generationID: String
    public let trimID: String
    public let wheelID: String
    public let colorID: String
    public let path: String
    public let reviewStatus: VehicleImageReviewStatus
}

public struct VehicleLegacyFallbackRecord: Codable, Equatable, Sendable {
    public let assetID: String
    public let path: String
}

public enum VehicleImageCatalogValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case duplicateGenerationID(String)
    case duplicateAssetID(String)
    case invalidYearRange(generationID: String, start: Int, end: Int)
    case missingDefaultTrim(generationID: String, trimID: String)
    case missingDefaultWheel(generationID: String, wheelID: String)
    case missingDefaultColor(generationID: String, colorID: String)
    case tiedMatcherPriority(model: String, priority: Int)
    case invalidLegacyFallback(generationID: String)
    case invalidAssetReference(assetID: String)
    case missingBundledAssetPath(String)
}

@MainActor
public protocol VehicleImageCatalogProviding: Sendable {
    func catalog() throws -> VehicleImageCatalog
}

public enum BundledVehicleImageCatalogProviderError: Error, Equatable, Sendable {
    case resourceNotFound
}

@MainActor
public final class BundledVehicleImageCatalogProvider: VehicleImageCatalogProviding, @unchecked Sendable {
    private let bundle: Bundle
    private var cachedCatalog: VehicleImageCatalog?

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func catalog() throws -> VehicleImageCatalog {
        if let cachedCatalog {
            return cachedCatalog
        }
        guard let url = bundle.url(forResource: "VehicleImageCatalog", withExtension: "json") else {
            throw BundledVehicleImageCatalogProviderError.resourceNotFound
        }

        let data = try Data(contentsOf: url)
        let unvalidatedCatalog = try JSONDecoder().decode(VehicleImageCatalog.self, from: data)
        let paths = Set(unvalidatedCatalog.assets.map(\.path)).filter { bundledAssetExists(at: $0) }
        let catalog = try VehicleImageCatalog.decode(from: data, bundledAssetPaths: paths)
        cachedCatalog = catalog
        return catalog
    }

    private func bundledAssetExists(at path: String) -> Bool {
        let components = path.split(separator: "/")
        guard let fileName = components.last else { return false }
        let fileURL = URL(fileURLWithPath: String(fileName))
        let name = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        let directory = components.dropLast().map(String.init).joined(separator: "/")
        return bundle.url(forResource: name, withExtension: ext, subdirectory: directory) != nil ||
            bundle.url(forResource: name, withExtension: ext) != nil
    }
}
