import Foundation

public enum ChargePricingBatchChangeKind: Equatable, Sendable {
    case fillMissing
    case replaceRecorded
}

public struct ChargePricingBatchCandidate: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let startDate: String
    public let address: String?
    public let energyKWh: Double
    public let previousCost: Double?
    public let estimatedCost: Double
    public let ruleID: String
    public let ruleName: String
    public let changeKind: ChargePricingBatchChangeKind
}

public struct ChargePricingBatchWriteResult: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let startDate: String
    public let ruleID: String
    public let ruleName: String
    public let previousCost: Double?
    public let newCost: Double
    public let succeeded: Bool
    public let message: String?

    public init(
        chargeId: Int,
        startDate: String = "",
        ruleID: String = "",
        ruleName: String = "",
        previousCost: Double?,
        newCost: Double,
        succeeded: Bool,
        message: String?
    ) {
        self.chargeId = chargeId
        self.startDate = startDate
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.previousCost = previousCost
        self.newCost = newCost
        self.succeeded = succeeded
        self.message = message
    }
}

public struct ChargePricingBatchRollbackResult: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let restoredCost: Double?
    public let succeeded: Bool
    public let message: String?
}

public struct ChargePricingBatchReceipt: Equatable, Sendable {
    public let id: String
    public let createdAt: Date
    public let results: [ChargePricingBatchWriteResult]
    public var rollbackResults: [ChargePricingBatchRollbackResult]?

    public init(
        id: String = UUID().uuidString,
        createdAt: Date,
        results: [ChargePricingBatchWriteResult],
        rollbackResults: [ChargePricingBatchRollbackResult]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.results = results
        self.rollbackResults = rollbackResults
    }
}

public struct ChargePricingAuditRecord: Equatable, Identifiable, Sendable {
    public var id: String { receipt.id }

    public let carId: Int
    public let currencyCode: String
    public let receipt: ChargePricingBatchReceipt

    public init(carId: Int, currencyCode: String, receipt: ChargePricingBatchReceipt) {
        self.carId = carId
        self.currencyCode = currencyCode
        self.receipt = receipt
    }
}

public struct ChargePricingBatchState: Equatable, Sendable {
    public var candidates: [ChargePricingBatchCandidate]
    public var selectedChargeIDs: Set<Int>
    public var manualOverrideExcludedCount: Int
    public var alreadyCorrectCount: Int
    public var unmatchedCount: Int
    public var isApplying: Bool
    public var isRollingBack: Bool
    public var lastReceipt: ChargePricingBatchReceipt?
    public var auditHistory: [ChargePricingAuditRecord]
    public var auditErrorMessage: String?
    public var errorMessage: String?

    public init(
        candidates: [ChargePricingBatchCandidate] = [],
        selectedChargeIDs: Set<Int> = [],
        manualOverrideExcludedCount: Int = 0,
        alreadyCorrectCount: Int = 0,
        unmatchedCount: Int = 0,
        isApplying: Bool = false,
        isRollingBack: Bool = false,
        lastReceipt: ChargePricingBatchReceipt? = nil,
        auditHistory: [ChargePricingAuditRecord] = [],
        auditErrorMessage: String? = nil,
        errorMessage: String? = nil
    ) {
        self.candidates = candidates
        self.selectedChargeIDs = selectedChargeIDs
        self.manualOverrideExcludedCount = manualOverrideExcludedCount
        self.alreadyCorrectCount = alreadyCorrectCount
        self.unmatchedCount = unmatchedCount
        self.isApplying = isApplying
        self.isRollingBack = isRollingBack
        self.lastReceipt = lastReceipt
        self.auditHistory = auditHistory
        self.auditErrorMessage = auditErrorMessage
        self.errorMessage = errorMessage
    }
}
