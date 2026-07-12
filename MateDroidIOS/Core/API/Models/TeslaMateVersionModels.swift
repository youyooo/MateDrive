import Foundation

public struct TeslaMateAPIVersion: Codable, Comparable, CustomStringConvertible, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ rawValue: String?) {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        let versionAndPrerelease = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard versionAndPrerelease.count == 1 || !versionAndPrerelease[1].isEmpty else {
            return nil
        }
        let core = String(versionAndPrerelease[0])
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = parts.count == 3 ? Int(parts[2]) : 0,
              major >= 0, minor >= 0, patch >= 0
        else {
            return nil
        }
        self.init(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public struct TeslaMateVersionInfo: Codable, Equatable, Sendable {
    public let apiVersion: String?
    public let mtAPIVersion: String?
    public let buildInfo: String?

    public init(apiVersion: String?, mtAPIVersion: String?, buildInfo: String?) {
        self.apiVersion = apiVersion
        self.mtAPIVersion = mtAPIVersion
        self.buildInfo = buildInfo
    }

    public var resolvedVersion: TeslaMateAPIVersion? {
        TeslaMateAPIVersion(mtAPIVersion) ?? TeslaMateAPIVersion(apiVersion)
    }

    public var displayVersion: String {
        resolvedVersion?.description ?? mtAPIVersion ?? apiVersion ?? "unknown"
    }
}

struct TeslaMateVersionResponse: Decodable {
    private let direct: TeslaMateVersionPayload
    private let nested: TeslaMateVersionPayload?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direct = TeslaMateVersionPayload(
            apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion),
            mtAPIVersion: try container.decodeIfPresent(String.self, forKey: .mtAPIVersion),
            buildInfo: try container.decodeIfPresent(String.self, forKey: .buildInfo)
        )
        nested = try container.decodeIfPresent(TeslaMateVersionPayload.self, forKey: .data)
    }

    var info: TeslaMateVersionInfo {
        let payload = nested ?? direct
        return TeslaMateVersionInfo(
            apiVersion: payload.apiVersion,
            mtAPIVersion: payload.mtAPIVersion,
            buildInfo: payload.buildInfo
        )
    }

    private enum CodingKeys: String, CodingKey {
        case apiVersion
        case mtAPIVersion = "mtApiVersion"
        case buildInfo
        case data
    }
}

private struct TeslaMateVersionPayload: Decodable {
    let apiVersion: String?
    let mtAPIVersion: String?
    let buildInfo: String?

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case mtAPIVersion = "mtApiVersion"
        case buildInfo
    }
}
