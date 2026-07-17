import CryptoKit
import Foundation

public enum TeslaMateCapability: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case coreCars
    case vehicleStatus
    case chargeList
    case chargeDetail
    case currentCharge
    case driveList
    case driveDetail
    case batteryHealthSummary
    case serverStats
    case costReview
    case unifiedActivities
    case batteryHealthHistory
    case driveInsights
    case environmentHistory
    case stateHistory
    case achievements
    case geofences
    case standbyDrain
    case topDrainLocations
    case commuteRoutes
    case statsExtremes
    case drivingCoordinates
    case serverPlaces
}

public enum TeslaMateCapabilityState: String, Codable, Equatable, Sendable {
    case available
    case degraded
    case unavailable
    case unknown
}

public enum TeslaMateCapabilityReason: String, Codable, Equatable, Sendable {
    case endpointNotFound
    case methodNotAllowed
    case authenticationRequired
    case invalidPayload
    case paginationMetadataInvalid
    case emptyPayload
    case temporaryServerFailure
    case networkFailure
    case notProbed
    case parametersRequired
}

public enum TeslaMateCapabilitySource: String, Codable, Equatable, Sendable {
    case endpointProbe
    case legacyDiagnostic
    case cached
}

public struct TeslaMateCapabilityStatus: Codable, Equatable, Sendable {
    public let state: TeslaMateCapabilityState
    public let reason: TeslaMateCapabilityReason?
    public let source: TeslaMateCapabilitySource
    public let checkedAt: Date
    public let lastSuccessfulAt: Date?

    public init(
        state: TeslaMateCapabilityState,
        reason: TeslaMateCapabilityReason? = nil,
        source: TeslaMateCapabilitySource,
        checkedAt: Date,
        lastSuccessfulAt: Date? = nil
    ) {
        self.state = state
        self.reason = reason
        self.source = source
        self.checkedAt = checkedAt
        self.lastSuccessfulAt = lastSuccessfulAt
    }
}

public enum TeslaMateConnectionIssue: Codable, Equatable, Sendable {
    case authentication(statusCode: Int)
    case temporaryServerFailure(statusCode: Int)
    case network
}

public struct TeslaMateServerProfile: Codable, Equatable, Sendable {
    public let serverKey: String
    public let carId: Int
    public let version: TeslaMateVersionInfo
    public let capabilities: [TeslaMateCapability: TeslaMateCapabilityStatus]
    public let connectionIssue: TeslaMateConnectionIssue?
    public let checkedAt: Date
    public let lastSuccessfulCheckAt: Date?

    public init(
        serverKey: String,
        carId: Int,
        version: TeslaMateVersionInfo,
        capabilities: [TeslaMateCapability: TeslaMateCapabilityStatus],
        connectionIssue: TeslaMateConnectionIssue? = nil,
        checkedAt: Date,
        lastSuccessfulCheckAt: Date? = nil
    ) {
        self.serverKey = serverKey
        self.carId = carId
        self.version = version
        self.capabilities = capabilities
        self.connectionIssue = connectionIssue
        self.checkedAt = checkedAt
        self.lastSuccessfulCheckAt = lastSuccessfulCheckAt
    }

    public func status(for capability: TeslaMateCapability) -> TeslaMateCapabilityStatus? {
        capabilities[capability]
    }
}

public struct TeslaMateProbeResponse: Equatable, Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public enum TeslaMateServerIdentity {
    public static func key(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let normalizedHost = host.contains(":") ? "[\(host)]" : host
        let port = url.port.flatMap { port in
            (scheme == "http" && port == 80) || (scheme == "https" && port == 443) ? nil : port
        }
        let authority = port.map { "\(normalizedHost):\($0)" } ?? normalizedHost
        let path = normalizedPath(url.path)
        let canonical = "\(scheme)://\(authority)\(path)"
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedPath(_ path: String) -> String {
        var path = path
        while path.last == "/" {
            path.removeLast()
        }
        return path
    }
}
