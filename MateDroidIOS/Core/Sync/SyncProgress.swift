import Foundation

public struct SyncProgress: Equatable, Sendable {
    public let carId: Int
    public let phase: SyncPhase
    public let currentItem: Int
    public let totalItems: Int
    public let message: String?

    public var percentage: Float {
        totalItems > 0 ? Float(currentItem) / Float(totalItems) : 0
    }

    public var percentageInt: Int {
        Int(percentage * 100)
    }

    public var isComplete: Bool {
        phase == .complete
    }

    public init(carId: Int, phase: SyncPhase, currentItem: Int, totalItems: Int, message: String? = nil) {
        self.carId = carId
        self.phase = phase
        self.currentItem = currentItem
        self.totalItems = totalItems
        self.message = message
    }
}

public struct OverallSyncStatus: Equatable, Sendable {
    public let carProgresses: [Int: SyncProgress]
    public let isAnySyncing: Bool
    public let allComplete: Bool

    public static let idle = OverallSyncStatus(carProgresses: [:], isAnySyncing: false, allComplete: false)
}
