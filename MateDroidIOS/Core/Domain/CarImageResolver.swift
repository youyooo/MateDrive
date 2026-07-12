import Foundation

public struct CarVariant: Equatable, Sendable {
    public let id: String
    public let displayNameIdentifier: String

    public init(id: String, displayNameIdentifier: String) {
        self.id = id
        self.displayNameIdentifier = displayNameIdentifier
    }
}

public struct WheelOption: Equatable, Sendable {
    public let code: String
    public let displayName: String
    public let assetPath: String

    public init(code: String, displayName: String, assetPath: String) {
        self.code = code
        self.displayName = displayName
        self.assetPath = assetPath
    }
}

public struct DetectedCarImageDefault: Equatable, Sendable {
    public let variant: String
    public let wheelCode: String

    public init(variant: String, wheelCode: String) {
        self.variant = variant
        self.wheelCode = wheelCode
    }
}

public enum CarImageResolver {
    public static func resolve(
        _ descriptor: VehicleImageDescriptor,
        catalog: VehicleImageCatalog,
        manualOverride: VehicleImageManualOverride? = nil
    ) -> VehicleImageResolution {
        VehicleImageResolver(catalog: catalog).resolve(
            descriptor,
            manualOverride: manualOverride
        )
    }

    private static let colorCodes = [
        "black": "PBSB",
        "solidblack": "PBSB",
        "obsidianblack": "PMBL",
        "midnightsilver": "PMNG",
        "midnightsilvermetallic": "PMNG",
        "steelgrey": "PMNG",
        "silver": "PMSS",
        "silvermetallic": "PMSS",
        "white": "PPSW",
        "pearlwhite": "PPSW",
        "pearlwhitemulticoat": "PPSW",
        "deepblue": "PPSB",
        "deepbluemetallic": "PPSB",
        "blue": "PPSB",
        "red": "PPMR",
        "redmulticoat": "PPMR",
        "quicksilver": "PN00",
        "stealthgrey": "PN01",
        "stealthgray": "PN01",
        "midnightcherryred": "PR00",
        "ultrared": "PR01",
        "diamondblack": "PX02",
        "blackdiamond": "PX02",
        "glacierblue": "PB01",
        "marineblue": "PB02"
    ]

    private static let highlandJuniperColors: Set<String> = ["PN00", "PN01", "PR01", "PX02", "PB01", "PB02"]
    private static let legacyOnlyColors: Set<String> = ["PMNG", "PMSS", "PPMR", "PMBL"]
    private static let modelYLegacyOnlyExtra: Set<String> = ["PBSB", "PPSB"]
    private static let juniperPremiumOnlyColors: Set<String> = ["PN00", "PR01", "PB01"]
    private static let juniperPerformanceOnlyColors: Set<String> = ["PB02"]

    private static let highlandModel3WheelTypes: Set<String> = ["photon18", "glider18", "nova18", "nova19", "helix19", "w38a"]
    private static let juniperModelYWheelTypes: Set<String> = ["photon18", "wy18p", "crossflow19", "wy19p", "helix20", "wy20a"]

    private static let legacyModel3Colors: Set<String> = ["PBSB", "PMNG", "PMSS", "PPSW", "PPSB", "PPMR", "PMBL"]
    private static let highlandModel3Colors: Set<String> = ["PBSB", "PPSW", "PPSB", "PN00", "PN01", "PR01", "PX02"]
    private static let legacyModelYColors: Set<String> = ["PBSB", "PMNG", "PPSW", "PPSB", "PPMR"]
    private static let juniperModelYStandardColors: Set<String> = ["PPSW", "PN01", "PX02"]
    private static let juniperModelYColors: Set<String> = ["PPSW", "PN01", "PX02", "PN00", "PR01", "PB01"]
    private static let juniperModelYPerformanceColors: Set<String> = ["PPSW", "PN01", "PX02", "PB02", "PN00", "PR01", "PB01"]
    private static let modelSXColors: Set<String> = ["PBSB", "PMNG", "PPSW", "PPSB", "PPMR"]

    private static let wheelPatternsModel3 = [
        ("pinwheel18", "W38B"),
        ("aero18", "W38B"),
        ("aeroturbine19", "W39B"),
        ("stiletto19", "W39B"),
        ("sport19", "W39B"),
        ("uberturbine20", "W32D"),
        ("performance20", "W32P"),
        ("19", "W39B"),
        ("20", "W32P"),
        ("18", "W38B")
    ]

    private static let wheelPatternsModel3Highland = [
        ("nova19", "W38A"),
        ("helix19", "W38A"),
        ("photon18", "W38A"),
        ("glider18", "W38A"),
        ("nova18", "W38A"),
        ("19", "W38A"),
        ("18", "W38A")
    ]

    private static let wheelPatternsModel3HighlandPerformance = [
        ("performance20", "W30P"),
        ("20", "W30P")
    ]

    private static let wheelPatternsModelY = [
        ("gemini19", "WY19B"),
        ("pinwheel18", "WY18B"),
        ("aero18", "WY18B"),
        ("aeroturbine19", "WY19B"),
        ("stiletto19", "WY19B"),
        ("sport19", "WY19B"),
        ("apollo19", "WY19B"),
        ("induction20", "WY20P"),
        ("performance20", "WY20P"),
        ("uberturbine21", "WY20P"),
        ("21", "WY20P"),
        ("20", "WY20P"),
        ("19", "WY19B"),
        ("18", "WY18B")
    ]

    private static let wheelPatternsModelYJuniper = [
        ("helix20", "WY20A"),
        ("crossflow19", "WY19P"),
        ("20", "WY20A"),
        ("19", "WY19P")
    ]

    private static let wheelPatternsModelYJuniperStandard = [
        ("photon18", "WY18P"),
        ("crossflow19", "WY19P"),
        ("19", "WY19P"),
        ("18", "WY18P")
    ]

    private static let wheelPatternsModelYJuniperPerformance = [
        ("uberturbine21", "WY21A"),
        ("arachnid21", "WY21A"),
        ("21", "WY21A")
    ]

    private static let wheelPatternsModelS = [
        ("tempest19", "WT19"),
        ("19", "WT19")
    ]

    private static let wheelPatternsModelX = [
        ("turbine22", "WT22"),
        ("cyberstream20", "WT20"),
        ("slipstream20", "WT20"),
        ("22", "WT22"),
        ("20", "WT20")
    ]

    private static let defaultWheels = [
        "m3": "W38B",
        "m3h": "W38A",
        "m3hp": "W30P",
        "my": "WY19B",
        "myjs": "WY18P",
        "myj": "WY19P",
        "myjp": "WY21A",
        "ms": "WT19",
        "mx": "WT20"
    ]

    private static let defaultColors = [
        "m3": "PPSW",
        "m3h": "PPSW",
        "m3hp": "PPSW",
        "my": "PPSW",
        "myjs": "PPSW",
        "myj": "PPSW",
        "myjp": "PPSW",
        "ms": "PPSW",
        "mx": "PPSW"
    ]

    private static let wheelDisplayNames = [
        "W38B": "18\" Aero",
        "W39B": "19\" Sport",
        "W32P": "20\" Performance",
        "W32D": "20\" Uberturbine",
        "W38A": "18\" Photon",
        "W30P": "20\" Performance",
        "WY18B": "18\" Aero",
        "WY19B": "19\" Gemini",
        "WY9S": "19\" Apollo",
        "WY0S": "20\" Induction",
        "WY20P": "20\" Performance",
        "WY1S": "21\" Uberturbine",
        "WY18P": "18\" Photon",
        "WY19P": "19\" Crossflow",
        "WY20A": "20\" Helix",
        "WY21A": "21\" Uberturbine",
        "WT19": "19\" Tempest",
        "WT20": "20\" Cyberstream",
        "WT22": "22\" Turbine"
    ]

    private static let variantWheels = [
        "m3": ["W38B", "W39B", "W32P", "W32D"],
        "m3h": ["W38A"],
        "m3hp": ["W30P"],
        "my": ["WY18B", "WY19B", "WY20P"],
        "myjs": ["WY18P", "WY19P"],
        "myj": ["WY19P", "WY20A"],
        "myjp": ["WY21A"],
        "ms": ["WT19"],
        "mx": ["WT20", "WT22"]
    ]

    public static func assetPath(
        model: String?,
        exteriorColor: String?,
        wheelType: String?,
        trimBadging: String? = nil
    ) -> String {
        let colorCode = mapColor(exteriorColor)
        let modelVariant = determineModelVariant(model: model, colorCode: colorCode, wheelType: wheelType, trimBadging: trimBadging)
        let resolvedColorCode = colorCode ?? defaultColors[modelVariant] ?? "PPSW"
        let wheelCode = mapWheel(modelVariant: modelVariant, wheelType: wheelType) ?? defaultWheels[modelVariant] ?? "W38B"
        let validatedColorCode = validateColor(forVariant: modelVariant, colorCode: resolvedColorCode)
        return "car_images/\(modelVariant)_\(validatedColorCode)_\(wheelCode).png"
    }

    public static func scaleFactor(
        model: String?,
        exteriorColor: String?,
        wheelType: String?,
        trimBadging: String? = nil
    ) -> Float {
        let colorCode = mapColor(exteriorColor)
        let modelVariant = determineModelVariant(model: model, colorCode: colorCode, wheelType: wheelType, trimBadging: trimBadging)
        return scaleFactor(forVariant: modelVariant)
    }

    public static func scaleFactor(forVariant modelVariant: String) -> Float {
        switch modelVariant {
        case "m3h", "m3hp":
            return 1.35
        case "myjs", "myj", "myjp":
            return 1.25
        case "mx":
            return 1.4
        default:
            return 1.0
        }
    }

    public static func defaultAssetPath(model: String?) -> String {
        let modelVariant: String
        switch normalizedBaseModel(model) {
        case "3":
            modelVariant = "m3"
        case "Y":
            modelVariant = "my"
        case "S":
            modelVariant = "ms"
        case "X":
            modelVariant = "mx"
        default:
            modelVariant = "m3"
        }

        return "car_images/\(modelVariant)_\(defaultColors[modelVariant] ?? "PPSW")_\(defaultWheels[modelVariant] ?? "W38B").png"
    }

    public static func fallbackAssetPath(
        model: String?,
        exteriorColor: String?,
        wheelType: String?,
        trimBadging: String? = nil,
        assetExists: (String) -> Bool
    ) -> String {
        let exactPath = assetPath(model: model, exteriorColor: exteriorColor, wheelType: wheelType, trimBadging: trimBadging)
        if assetExists(exactPath) {
            return exactPath
        }

        let colorCode = mapColor(exteriorColor)
        let modelVariant = determineModelVariant(model: model, colorCode: colorCode, wheelType: wheelType, trimBadging: trimBadging)
        let validatedColor = validateColor(forVariant: modelVariant, colorCode: colorCode ?? defaultColors[modelVariant] ?? "PPSW")
        let defaultWheelPath = "car_images/\(modelVariant)_\(validatedColor)_\(defaultWheels[modelVariant] ?? "W38B").png"
        if assetExists(defaultWheelPath) {
            return defaultWheelPath
        }

        let wheelCode = mapWheel(modelVariant: modelVariant, wheelType: wheelType) ?? defaultWheels[modelVariant] ?? "W38B"
        let defaultColorPath = "car_images/\(modelVariant)_\(defaultColors[modelVariant] ?? "PPSW")_\(wheelCode).png"
        if assetExists(defaultColorPath) {
            return defaultColorPath
        }

        return defaultAssetPath(model: model)
    }

    public static func validateColor(forVariant modelVariant: String, colorCode: String) -> String {
        let validColors: Set<String>
        switch modelVariant {
        case "m3":
            validColors = legacyModel3Colors
        case "m3h", "m3hp":
            validColors = highlandModel3Colors
        case "my":
            validColors = legacyModelYColors
        case "myjs":
            validColors = juniperModelYStandardColors
        case "myj":
            validColors = juniperModelYColors
        case "myjp":
            validColors = juniperModelYPerformanceColors
        case "ms", "mx":
            validColors = modelSXColors
        default:
            validColors = legacyModel3Colors
        }

        return validColors.contains(colorCode) ? colorCode : defaultColors[modelVariant] ?? "PPSW"
    }

    public static func mapColor(_ color: String?) -> String? {
        guard let color else {
            return nil
        }
        let normalized = normalize(color)
        let uppercased = normalized.uppercased()
        if allColorCodes.contains(uppercased) {
            return uppercased
        }
        return colorCodes[normalized]
    }

    public static func detectedDefault(
        model: String?,
        exteriorColor: String?,
        wheelType: String?,
        trimBadging: String?
    ) -> DetectedCarImageDefault {
        let colorCode = mapColor(exteriorColor)
        let variant = determineModelVariant(model: model, colorCode: colorCode, wheelType: wheelType, trimBadging: trimBadging)
        let wheelCode = mapWheel(modelVariant: variant, wheelType: wheelType) ?? defaultWheels[variant] ?? "W38B"
        return DetectedCarImageDefault(variant: variant, wheelCode: wheelCode)
    }

    public static func variantsForModel(
        model: String?,
        colorCode: String? = nil,
        trimBadging: String? = nil,
        wheelType: String? = nil
    ) -> [CarVariant] {
        let isNewOnlyColor = colorCode.map(highlandJuniperColors.contains) ?? false
        let isLegacyOnlyColor = colorCode.map(legacyOnlyColors.contains) ?? false
        let isPremiumOnlyColor = colorCode.map(juniperPremiumOnlyColors.contains) ?? false
        let isPerformanceOnlyColor = colorCode.map(juniperPerformanceOnlyColors.contains) ?? false
        let isPerformanceTrim = trimBadging?.uppercased().hasPrefix("P") == true
        let normalizedWheel = wheelType.map(normalize)
        let isPerformanceWheel = normalizedWheel.map {
            $0.hasPrefix("performance20") ||
                $0.hasPrefix("uberturbine21") ||
                $0.hasPrefix("arachnid21") ||
                $0.hasPrefix("21") ||
                $0.hasPrefix("20")
        } ?? false
        let showPerformance = isPerformanceTrim || isPerformanceWheel || (trimBadging == nil && wheelType == nil)

        let myLegacy = CarVariant(id: "my", displayNameIdentifier: variantDisplayNameIdentifier(forVariant: "my"))
        let myStandard = CarVariant(id: "myjs", displayNameIdentifier: variantDisplayNameIdentifier(forVariant: "myjs"))
        let myPremium = CarVariant(id: "myj", displayNameIdentifier: variantDisplayNameIdentifier(forVariant: "myj"))
        let myPerformance = CarVariant(id: "myjp", displayNameIdentifier: variantDisplayNameIdentifier(forVariant: "myjp"))
        let m3Legacy = CarVariant(id: "m3", displayNameIdentifier: variantDisplayNameIdentifier(forVariant: "m3"))
        let m3Highland = CarVariant(id: "m3h", displayNameIdentifier: variantDisplayNameIdentifier(forVariant: "m3h"))
        let m3HighlandPerformance = CarVariant(id: "m3hp", displayNameIdentifier: variantDisplayNameIdentifier(forVariant: "m3hp"))

        switch normalizedBaseModel(model) {
        case "Y":
            let isModelYLegacyOnly = colorCode.map(modelYLegacyOnlyExtra.contains) ?? false
            if isPerformanceOnlyColor {
                return [myPerformance]
            }
            if isLegacyOnlyColor || isModelYLegacyOnly {
                return [myLegacy]
            }
            if isPremiumOnlyColor {
                return [myPremium]
            }
            if isNewOnlyColor {
                return [myStandard, myPremium]
            }
            return showPerformance ? [myLegacy, myStandard, myPremium, myPerformance] : [myLegacy, myStandard, myPremium]

        case "3":
            if isLegacyOnlyColor {
                return [m3Legacy]
            }
            if isNewOnlyColor {
                return [m3Highland]
            }
            return showPerformance ? [m3Legacy, m3Highland, m3HighlandPerformance] : [m3Legacy, m3Highland]

        default:
            return []
        }
    }

    public static func wheelsForVariant(variant: String, colorCode: String?, wheelType: String? = nil) -> [WheelOption] {
        guard let wheels = variantWheels[variant] else {
            return []
        }
        let color = colorCode ?? defaultColors[variant] ?? "PPSW"
        let validatedColor = validateColor(forVariant: variant, colorCode: color)

        if let wheelType,
           let mappedWheel = mapWheel(modelVariant: variant, wheelType: wheelType),
           wheels.contains(mappedWheel) {
            return [
                WheelOption(
                    code: mappedWheel,
                    displayName: wheelDisplayNames[mappedWheel] ?? mappedWheel,
                    assetPath: "car_images/\(variant)_\(validatedColor)_\(mappedWheel).png"
                )
            ]
        }

        return wheels.map { wheelCode in
            WheelOption(
                code: wheelCode,
                displayName: wheelDisplayNames[wheelCode] ?? wheelCode,
                assetPath: "car_images/\(variant)_\(validatedColor)_\(wheelCode).png"
            )
        }
    }

    public static func assetPathForOverride(variant: String, colorCode: String?, wheelCode: String) -> String {
        let color = colorCode ?? defaultColors[variant] ?? "PPSW"
        let validatedColor = validateColor(forVariant: variant, colorCode: color)
        return "car_images/\(variant)_\(validatedColor)_\(wheelCode).png"
    }

    public static func variantDisplayNameIdentifier(forVariant variant: String) -> String {
        switch variant {
        case "my":
            return "car_variant_my_legacy"
        case "myjs":
            return "car_variant_my_standard"
        case "myj":
            return "car_variant_my_premium"
        case "myjp":
            return "car_variant_my_performance"
        case "m3":
            return "car_variant_m3_legacy"
        case "m3h":
            return "car_variant_m3_highland"
        case "m3hp":
            return "car_variant_m3_highland_perf"
        default:
            return variant
        }
    }

    private static func determineModelVariant(
        model: String?,
        colorCode: String?,
        wheelType: String?,
        trimBadging: String?
    ) -> String {
        let baseModel = normalizedBaseModel(model) ?? "3"
        let isHighlandJuniperColor = colorCode.map(highlandJuniperColors.contains) ?? false
        let normalizedWheel = wheelType.map(normalize)
        let isHighlandModel3Wheel = normalizedWheel.map { wheel in
            highlandModel3WheelTypes.contains { wheel.hasPrefix($0) }
        } ?? false
        let isJuniperModelYWheel = normalizedWheel.map { wheel in
            juniperModelYWheelTypes.contains { wheel.hasPrefix($0) }
        } ?? false
        let isPerformance = trimBadging?.uppercased().hasPrefix("P") == true ||
            trimBadging?.lowercased().contains("performance") == true
        let isJuniperPerformanceWheel = normalizedWheel.map {
            $0.hasPrefix("uberturbine21") || $0.hasPrefix("arachnid21") || $0.hasPrefix("21")
        } ?? false
        let isJuniperStandard = trimBadging?.uppercased() == "50"
        let isPhoton18Wheel = normalizedWheel?.hasPrefix("photon18") == true

        switch baseModel {
        case "3":
            if (isHighlandJuniperColor || isHighlandModel3Wheel), isPerformance {
                return "m3hp"
            }
            if isHighlandJuniperColor || isHighlandModel3Wheel {
                return "m3h"
            }
            return "m3"

        case "Y":
            if (isHighlandJuniperColor || isJuniperModelYWheel || isJuniperPerformanceWheel),
               isPerformance || isJuniperPerformanceWheel {
                return "myjp"
            }
            if (isHighlandJuniperColor || isJuniperModelYWheel),
               isJuniperStandard || isPhoton18Wheel {
                return "myjs"
            }
            if isHighlandJuniperColor || isJuniperModelYWheel {
                return "myj"
            }
            return "my"

        case "S":
            return "ms"
        case "X":
            return "mx"
        default:
            return "m3"
        }
    }

    private static func mapWheel(modelVariant: String, wheelType: String?) -> String? {
        guard let wheelType else {
            return nil
        }

        let normalized = normalize(wheelType)
        let uppercased = normalized.uppercased()
        if variantWheels[modelVariant]?.contains(uppercased) == true {
            return uppercased
        }

        let patterns: [(String, String)]
        switch modelVariant {
        case "m3":
            patterns = wheelPatternsModel3
        case "m3h":
            patterns = wheelPatternsModel3Highland
        case "m3hp":
            patterns = wheelPatternsModel3HighlandPerformance
        case "my":
            patterns = wheelPatternsModelY
        case "myj":
            patterns = wheelPatternsModelYJuniper
        case "myjs":
            patterns = wheelPatternsModelYJuniperStandard
        case "myjp":
            patterns = wheelPatternsModelYJuniperPerformance
        case "ms":
            patterns = wheelPatternsModelS
        case "mx":
            patterns = wheelPatternsModelX
        default:
            patterns = wheelPatternsModel3
        }

        return patterns.first { normalized.hasPrefix($0.0) }?.1
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static var allColorCodes: Set<String> {
        legacyModel3Colors
            .union(highlandModel3Colors)
            .union(legacyModelYColors)
            .union(juniperModelYStandardColors)
            .union(juniperModelYColors)
            .union(juniperModelYPerformanceColors)
            .union(modelSXColors)
    }

    private static func normalizedBaseModel(_ model: String?) -> String? {
        guard let model else {
            return nil
        }

        switch normalize(model) {
        case "3", "m3", "model3", "modelthree":
            return "3"
        case "y", "my", "modely":
            return "Y"
        case "s", "ms", "models":
            return "S"
        case "x", "mx", "modelx":
            return "X"
        default:
            return model.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }
}
