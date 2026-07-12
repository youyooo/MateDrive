import Foundation

public struct GlobalSettingsResponse: Decodable, Sendable {
    public let data: GlobalSettingsPayload?
    public let error: String?
}

public struct GlobalSettingsPayload: Decodable, Sendable {
    public let settings: GlobalSettingsData?
}

public struct GlobalSettingsData: Decodable, Equatable, Sendable {
    public let unitOfLength: String?
    public let unitOfTemperature: String?
    public let unitOfPressure: String?
    public let preferredRange: String?

    public init(
        unitOfLength: String? = nil,
        unitOfTemperature: String? = nil,
        unitOfPressure: String? = nil,
        preferredRange: String? = nil
    ) {
        self.unitOfLength = unitOfLength
        self.unitOfTemperature = unitOfTemperature
        self.unitOfPressure = unitOfPressure
        self.preferredRange = preferredRange
    }

    private enum CodingKeys: String, CodingKey {
        case unitOfLength
        case unitOfTemperature
        case unitOfPressure
        case preferredRange
        case teslamateUnits
        case teslamateWebgui
    }

    private struct TeslaMateUnits: Decodable {
        let unitOfLength: String?
        let unitOfTemperature: String?
        let unitOfPressure: String?
    }

    private struct TeslaMateWebGUI: Decodable {
        let preferredRange: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let units = try container.decodeIfPresent(TeslaMateUnits.self, forKey: .teslamateUnits)
        let webGUI = try container.decodeIfPresent(TeslaMateWebGUI.self, forKey: .teslamateWebgui)
        func flatValue(_ key: CodingKeys) -> String? {
            try? container.decodeIfPresent(String.self, forKey: key)
        }

        unitOfLength = units?.unitOfLength ?? flatValue(.unitOfLength)
        unitOfTemperature = units?.unitOfTemperature ?? flatValue(.unitOfTemperature)
        unitOfPressure = units?.unitOfPressure ?? flatValue(.unitOfPressure)
        preferredRange = webGUI?.preferredRange ?? flatValue(.preferredRange)
    }
}
