import Foundation

public enum DriveClassification: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case unclassified, commute, personal, business, roadTrip, custom
    public var id: String { rawValue }

    public func title(language: AppLanguage) -> String {
        let key: String
        let chinese: String
        switch self {
        case .unclassified: (key, chinese) = ("Unclassified", "未分类")
        case .commute: (key, chinese) = ("Commute", "通勤")
        case .personal: (key, chinese) = ("Personal", "个人")
        case .business: (key, chinese) = ("Business", "商务")
        case .roadTrip: (key, chinese) = ("Road Trip", "长途")
        case .custom: (key, chinese) = ("Custom", "自定义")
        }
        return AppText.localized(key, chinese, language: language)
    }
}

public struct DriveAnnotation: Codable, Equatable, Sendable {
    public var classification: DriveClassification
    public var customLabel: String
    public var note: String

    public init(classification: DriveClassification = .unclassified, customLabel: String = "", note: String = "") {
        self.classification = classification
        self.customLabel = customLabel
        self.note = note
    }

    public var isEmpty: Bool {
        classification == .unclassified && customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func displayLabel(language: AppLanguage) -> String {
        if classification == .custom {
            let value = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return classification.title(language: language)
    }
}

public struct DriveRoutePoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct DriveRouteFingerprint: Codable, Equatable, Sendable {
    public let points: [DriveRoutePoint]

    public init(points: [DriveRoutePoint]) {
        self.points = points
    }

    public init(positions: [DrivePosition], maximumPointCount: Int = 16) {
        let valid = positions.compactMap { position -> DriveRoutePoint? in
            guard let latitude = position.latitude, let longitude = position.longitude,
                  GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil
            else { return nil }
            return DriveRoutePoint(latitude: latitude, longitude: longitude)
        }
        guard valid.count > maximumPointCount, maximumPointCount > 1 else {
            points = valid
            return
        }
        points = (0..<maximumPointCount).map { index in
            let position = Double(index) / Double(maximumPointCount - 1)
            let sourceIndex = Int((position * Double(valid.count - 1)).rounded())
            return valid[sourceIndex]
        }
    }

    public var isComplete: Bool { points.count >= 4 }
    public var start: DriveRoutePoint? { points.first }
    public var end: DriveRoutePoint? { points.last }

    public func reversed() -> DriveRouteFingerprint {
        DriveRouteFingerprint(points: points.reversed())
    }
}

public enum DriveRouteLabelDirection: String, Codable, Equatable, Sendable {
    case outbound
    case inbound
    case custom
}

public struct DriveRouteLabelRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var carId: Int
    public var name: String
    public var iconName: String
    public var colorHex: String
    public var direction: DriveRouteLabelDirection
    public var typicalDistanceKm: Double
    public var fingerprint: DriveRouteFingerprint
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        carId: Int,
        name: String,
        iconName: String = "briefcase.fill",
        colorHex: String = "22A65A",
        direction: DriveRouteLabelDirection = .custom,
        typicalDistanceKm: Double,
        fingerprint: DriveRouteFingerprint,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.carId = carId
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.direction = direction
        self.typicalDistanceKm = typicalDistanceKm
        self.fingerprint = fingerprint
        self.isEnabled = isEnabled
    }
}

public struct DriveCommuteSuggestion: Codable, Equatable, Sendable {
    public let name: String
    public let iconName: String
    public let colorHex: String
    public let direction: DriveRouteLabelDirection
    public let matchingDriveCount: Int
    public let typicalDistanceKm: Double
    public let fingerprint: DriveRouteFingerprint

    public init(
        name: String,
        iconName: String,
        colorHex: String,
        direction: DriveRouteLabelDirection,
        matchingDriveCount: Int,
        typicalDistanceKm: Double,
        fingerprint: DriveRouteFingerprint
    ) {
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.direction = direction
        self.matchingDriveCount = matchingDriveCount
        self.typicalDistanceKm = typicalDistanceKm
        self.fingerprint = fingerprint
    }
}

public enum DrivePerformanceAccent: String, Codable, Equatable, Sendable {
    case neutral, efficient, aboveBenchmark, gold, silver, bronze, personalBest
}

public struct DriveBenchmarkResult: Codable, Equatable, Sendable {
    public let currentEfficiency: Double?
    public let benchmarkEfficiency: Double?
    public let percentageDifference: Double?
    public let recentEfficiencies: [Double]
    public let currentTrendIndex: Int?
    public let rank: Int?
    public let previousBestEfficiency: Double?
    public let sampleCount: Int
    public let samplesNeeded: Int
    public let accent: DrivePerformanceAccent
    public let isThreeDriveStreak: Bool
    public let fiveDriveImprovementPercent: Double?

    public init(
        currentEfficiency: Double?,
        benchmarkEfficiency: Double?,
        percentageDifference: Double?,
        recentEfficiencies: [Double],
        currentTrendIndex: Int?,
        rank: Int?,
        previousBestEfficiency: Double?,
        sampleCount: Int,
        samplesNeeded: Int,
        accent: DrivePerformanceAccent,
        isThreeDriveStreak: Bool,
        fiveDriveImprovementPercent: Double?
    ) {
        self.currentEfficiency = currentEfficiency
        self.benchmarkEfficiency = benchmarkEfficiency
        self.percentageDifference = percentageDifference
        self.recentEfficiencies = recentEfficiencies
        self.currentTrendIndex = currentTrendIndex
        self.rank = rank
        self.previousBestEfficiency = previousBestEfficiency
        self.sampleCount = sampleCount
        self.samplesNeeded = samplesNeeded
        self.accent = accent
        self.isThreeDriveStreak = isThreeDriveStreak
        self.fiveDriveImprovementPercent = fiveDriveImprovementPercent
    }
}

public struct DriveIntelligenceResult: Codable, Equatable, Sendable {
    public let confirmedLabel: DriveRouteLabelRule?
    public let suggestion: DriveCommuteSuggestion?
    public let benchmark: DriveBenchmarkResult

    public init(
        confirmedLabel: DriveRouteLabelRule?,
        suggestion: DriveCommuteSuggestion?,
        benchmark: DriveBenchmarkResult
    ) {
        self.confirmedLabel = confirmedLabel
        self.suggestion = suggestion
        self.benchmark = benchmark
    }
}

public enum DriveIntelligenceEngine {
    public static let minimumCommuteOccurrences = 4
    public static let benchmarkWindowSize = 8
    public static let minimumBenchmarkSamples = 4

    public static func analyze(
        items: [DriveSummaryItem],
        carId: Int,
        routeLabels: [DriveRouteLabelRule],
        annotations: [String: DriveAnnotation],
        geofences: [GeofenceRule],
        calendar: Calendar = .current
    ) -> [Int: DriveIntelligenceResult] {
        let sorted = items.sorted { $0.startDate < $1.startDate }
        let enabledRules = routeLabels.filter { $0.isEnabled && $0.carId == carId }
        let morningClusters = commuteClusters(in: sorted, calendar: calendar, hours: 7..<10)

        var confirmedByDrive: [Int: DriveRouteLabelRule] = [:]
        var suggestionsByDrive: [Int: DriveCommuteSuggestion] = [:]

        for item in sorted {
            let key = "\(carId):\(item.driveId)"
            if let annotation = annotations[key], !annotation.isEmpty,
               annotation.classification != .unclassified,
               let fingerprint = item.routeFingerprint,
               let distance = item.distance {
                confirmedByDrive[item.driveId] = DriveRouteLabelRule(
                    carId: carId,
                    name: annotation.displayLabel(language: .chinese),
                    iconName: annotation.classification == .business ? "briefcase.fill" : "tag.fill",
                    colorHex: "3478F6",
                    typicalDistanceKm: distance,
                    fingerprint: fingerprint
                )
                continue
            }
            if let rule = bestMatchingRule(for: item, rules: enabledRules) {
                confirmedByDrive[item.driveId] = rule
                continue
            }
            if let cluster = morningClusters.first(where: { cluster in
                cluster.items.contains(where: { $0.driveId == item.driveId })
            }), let fingerprint = cluster.reference.routeFingerprint {
                let startKind = fingerprint.start.flatMap {
                    GeofenceRuleEngine.matchingRule(latitude: $0.latitude, longitude: $0.longitude, carId: carId, rules: geofences)?.kind
                }
                let endKind = fingerprint.end.flatMap {
                    GeofenceRuleEngine.matchingRule(latitude: $0.latitude, longitude: $0.longitude, carId: carId, rules: geofences)?.kind
                }
                if (startKind == nil || startKind == .home), (endKind == nil || endKind == .work) {
                    suggestionsByDrive[item.driveId] = DriveCommuteSuggestion(
                        name: "上班通勤",
                        iconName: "briefcase.fill",
                        colorHex: "22A65A",
                        direction: .outbound,
                        matchingDriveCount: cluster.items.count,
                        typicalDistanceKm: cluster.medianDistance,
                        fingerprint: fingerprint
                    )
                }
            }
            if suggestionsByDrive[item.driveId] == nil,
               let reverseRule = enabledRules.first(where: { $0.direction == .outbound && matches(item, rule: $0, reversed: true) }),
               let fingerprint = item.routeFingerprint,
               let distance = item.distance {
                suggestionsByDrive[item.driveId] = DriveCommuteSuggestion(
                    name: "下班通勤",
                    iconName: "house.fill",
                    colorHex: reverseRule.colorHex,
                    direction: .inbound,
                    matchingDriveCount: 1,
                    typicalDistanceKm: distance,
                    fingerprint: fingerprint
                )
            }
        }

        var results: [Int: DriveIntelligenceResult] = [:]
        for item in sorted {
            let rule = confirmedByDrive[item.driveId]
            let benchmark = benchmark(
                current: item,
                allItems: sorted,
                confirmedByDrive: confirmedByDrive,
                currentRule: rule
            )
            results[item.driveId] = DriveIntelligenceResult(
                confirmedLabel: rule,
                suggestion: rule == nil ? suggestionsByDrive[item.driveId] : nil,
                benchmark: benchmark
            )
        }
        return results
    }

    public static func confirmedRule(
        from suggestion: DriveCommuteSuggestion,
        carId: Int
    ) -> DriveRouteLabelRule {
        DriveRouteLabelRule(
            carId: carId,
            name: suggestion.name,
            iconName: suggestion.iconName,
            colorHex: suggestion.colorHex,
            direction: suggestion.direction,
            typicalDistanceKm: suggestion.typicalDistanceKm,
            fingerprint: suggestion.fingerprint
        )
    }

    public static func similarity(_ lhs: DriveRouteFingerprint, _ rhs: DriveRouteFingerprint) -> Double {
        guard lhs.isComplete, rhs.isComplete else { return 0 }
        let count = min(lhs.points.count, rhs.points.count)
        guard count >= 4 else { return 0 }
        let left = resample(lhs.points, count: count)
        let right = resample(rhs.points, count: count)
        let meanDistance = zip(left, right).map { distanceMeters($0, $1) }.reduce(0, +) / Double(count)
        return max(0, 1 - meanDistance / 2_000)
    }

    private struct CommuteCluster {
        var reference: DriveSummaryItem
        var items: [DriveSummaryItem]
        var medianDistance: Double
    }

    private static func commuteClusters(
        in items: [DriveSummaryItem],
        calendar: Calendar,
        hours: Range<Int>
    ) -> [CommuteCluster] {
        let candidates = items.filter { item in
            guard let date = DomainDateParser.date(from: item.startDate),
                  !calendar.isDateInWeekend(date),
                  hours.contains(calendar.component(.hour, from: date)),
                  item.routeFingerprint?.isComplete == true,
                  let distance = item.distance, distance > 0
            else { return false }
            return true
        }
        var clusters: [CommuteCluster] = []
        for item in candidates {
            if let index = clusters.firstIndex(where: { sameRoute(item, $0.reference) }) {
                clusters[index].items.append(item)
                clusters[index].medianDistance = median(clusters[index].items.compactMap(\.distance)) ?? clusters[index].medianDistance
            } else {
                clusters.append(CommuteCluster(reference: item, items: [item], medianDistance: item.distance ?? 0))
            }
        }
        return clusters.filter { $0.items.count >= minimumCommuteOccurrences }
    }

    private static func bestMatchingRule(
        for item: DriveSummaryItem,
        rules: [DriveRouteLabelRule]
    ) -> DriveRouteLabelRule? {
        rules
            .filter { matches(item, rule: $0, reversed: false) }
            .max { lhs, rhs in
                guard let fingerprint = item.routeFingerprint else { return false }
                return similarity(fingerprint, lhs.fingerprint) < similarity(fingerprint, rhs.fingerprint)
            }
    }

    private static func matches(_ item: DriveSummaryItem, rule: DriveRouteLabelRule, reversed: Bool) -> Bool {
        guard let distance = item.distance, distance > 0,
              abs(distance - rule.typicalDistanceKm) / rule.typicalDistanceKm <= 0.10,
              let fingerprint = item.routeFingerprint
        else { return false }
        let expected = reversed ? rule.fingerprint.reversed() : rule.fingerprint
        return endpointDistance(fingerprint, expected) <= 1_200 && similarity(fingerprint, expected) >= 0.72
    }

    private static func sameRoute(_ lhs: DriveSummaryItem, _ rhs: DriveSummaryItem) -> Bool {
        guard let leftDistance = lhs.distance, let rightDistance = rhs.distance,
              max(leftDistance, rightDistance) > 0,
              abs(leftDistance - rightDistance) / max(leftDistance, rightDistance) <= 0.10,
              let leftRoute = lhs.routeFingerprint, let rightRoute = rhs.routeFingerprint
        else { return false }
        return endpointDistance(leftRoute, rightRoute) <= 1_200 && similarity(leftRoute, rightRoute) >= 0.72
    }

    private static func benchmark(
        current: DriveSummaryItem,
        allItems: [DriveSummaryItem],
        confirmedByDrive: [Int: DriveRouteLabelRule],
        currentRule: DriveRouteLabelRule?
    ) -> DriveBenchmarkResult {
        guard let currentRule,
              let currentEfficiency = current.efficiency,
              currentEfficiency > 0,
              current.distance != nil,
              current.routeFingerprint?.isComplete == true
        else {
            return emptyBenchmark(currentEfficiency: current.efficiency)
        }
        let valid = allItems.filter { candidate in
            guard candidate.efficiency != nil,
                  candidate.distance != nil,
                  candidate.routeFingerprint?.isComplete == true,
                  let rule = confirmedByDrive[candidate.driveId],
                  rule.name == currentRule.name,
                  sameRoute(candidate, current)
            else { return false }
            return true
        }.sorted { $0.startDate < $1.startDate }
        let currentIndex = valid.firstIndex { $0.driveId == current.driveId }
        let previous = valid.filter { $0.startDate < current.startDate }
        let recentPrevious = Array(previous.suffix(benchmarkWindowSize))
        let previousEfficiencies = recentPrevious.compactMap(\.efficiency)
        let benchmark = previousEfficiencies.count >= minimumBenchmarkSamples ? median(previousEfficiencies) : nil
        let difference = benchmark.map { (currentEfficiency - $0) / $0 * 100 }
        let allEfficiencies = valid.compactMap(\.efficiency).sorted()
        let rank = allEfficiencies.firstIndex(of: currentEfficiency).map { $0 + 1 }
        let previousBest = previous.compactMap(\.efficiency).min()
        let isBest = previousBest.map { currentEfficiency < $0 } ?? false
        let accent: DrivePerformanceAccent
        if isBest {
            accent = .personalBest
        } else if rank == 1 {
            accent = .gold
        } else if rank == 2 {
            accent = .silver
        } else if rank == 3 {
            accent = .bronze
        } else if let difference, difference <= -5 {
            accent = .efficient
        } else if let difference, difference > 0 {
            accent = .aboveBenchmark
        } else {
            accent = .neutral
        }
        let recentTrendItems = Array(valid.suffix(benchmarkWindowSize))
        let recentTrend = recentTrendItems.compactMap(\.efficiency)
        let trendIndex = recentTrendItems.firstIndex { $0.driveId == current.driveId }
        let lastThree = Array(valid.filter { $0.startDate <= current.startDate }.suffix(3)).compactMap(\.efficiency)
        let threeDriveStreak = lastThree.count == 3 && benchmark.map { baseline in lastThree.allSatisfy { $0 < baseline } } == true
        let throughCurrent = valid.filter { $0.startDate <= current.startDate }
        let lastFive = Array(throughCurrent.suffix(5)).compactMap(\.efficiency)
        let priorFive = Array(throughCurrent.dropLast(min(5, throughCurrent.count)).suffix(5)).compactMap(\.efficiency)
        let improvement: Double?
        if lastFive.count == 5, priorFive.count == 5,
           let recentMedian = median(lastFive), let priorMedian = median(priorFive), priorMedian > 0 {
            improvement = max((priorMedian - recentMedian) / priorMedian * 100, 0)
        } else {
            improvement = nil
        }
        return DriveBenchmarkResult(
            currentEfficiency: currentEfficiency,
            benchmarkEfficiency: benchmark,
            percentageDifference: difference,
            recentEfficiencies: recentTrend,
            currentTrendIndex: trendIndex ?? currentIndex,
            rank: rank,
            previousBestEfficiency: previousBest,
            sampleCount: previousEfficiencies.count,
            samplesNeeded: max(minimumBenchmarkSamples - previousEfficiencies.count, 0),
            accent: accent,
            isThreeDriveStreak: threeDriveStreak,
            fiveDriveImprovementPercent: improvement
        )
    }

    private static func emptyBenchmark(currentEfficiency: Double?) -> DriveBenchmarkResult {
        DriveBenchmarkResult(
            currentEfficiency: currentEfficiency,
            benchmarkEfficiency: nil,
            percentageDifference: nil,
            recentEfficiencies: currentEfficiency.map { [$0] } ?? [],
            currentTrendIndex: currentEfficiency == nil ? nil : 0,
            rank: nil,
            previousBestEfficiency: nil,
            sampleCount: 0,
            samplesNeeded: minimumBenchmarkSamples,
            accent: .neutral,
            isThreeDriveStreak: false,
            fiveDriveImprovementPercent: nil
        )
    }

    private static func endpointDistance(_ lhs: DriveRouteFingerprint, _ rhs: DriveRouteFingerprint) -> Double {
        guard let lhsStart = lhs.start, let lhsEnd = lhs.end,
              let rhsStart = rhs.start, let rhsEnd = rhs.end
        else { return .infinity }
        return max(distanceMeters(lhsStart, rhsStart), distanceMeters(lhsEnd, rhsEnd))
    }

    private static func resample(_ points: [DriveRoutePoint], count: Int) -> [DriveRoutePoint] {
        guard points.count != count, count > 1 else { return points }
        return (0..<count).map { index in
            let position = Double(index) / Double(count - 1)
            let sourceIndex = Int((position * Double(points.count - 1)).rounded())
            return points[sourceIndex]
        }
    }

    private static func distanceMeters(_ lhs: DriveRoutePoint, _ rhs: DriveRoutePoint) -> Double {
        let radius = 6_371_000.0
        let latitudeDelta = (rhs.latitude - lhs.latitude) * .pi / 180
        let longitudeDelta = (rhs.longitude - lhs.longitude) * .pi / 180
        let lhsLatitude = lhs.latitude * .pi / 180
        let rhsLatitude = rhs.latitude * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(lhsLatitude) * cos(rhsLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

public enum DriveCSVExporter {
    public static func csv(detail: DriveDetail, stats: DriveDetailStats?, annotation: DriveAnnotation, units: UnitPreferences?) -> String {
        let rows: [(String, String)] = [
            ("drive_id", String(detail.driveId)),
            ("start_date", detail.startDate ?? ""),
            ("end_date", detail.endDate ?? ""),
            ("start_address", detail.startAddress ?? ""),
            ("end_address", detail.endAddress ?? ""),
            ("distance_km", number(stats?.distance ?? detail.distance)),
            ("duration_min", stats?.durationMin.map(String.init) ?? ""),
            ("average_speed_kmh", number(stats?.speedAvg)),
            ("max_speed_kmh", stats?.speedMax.map(String.init) ?? ""),
            ("energy_kwh", number(stats?.energyUsed)),
            ("efficiency_wh_km", number(stats?.efficiency)),
            ("classification", annotation.classification.rawValue),
            ("custom_label", annotation.customLabel),
            ("note", annotation.note),
            ("unit_of_length", units?.unitOfLength ?? "km")
        ]
        return "field,value\n" + rows.map { "\(escape($0.0)),\(escape($0.1))" }.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String { value.map { String(format: "%.6f", $0) } ?? "" }
    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
