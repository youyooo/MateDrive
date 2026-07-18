import Foundation

public struct BackgroundRefreshReport: Equatable, Sendable {
    public let historySyncReport: HistorySyncReport
    public let vehicleStatusRefreshed: Bool
    public let smartActivitiesIndexed: Bool
    public let wasCancelled: Bool

    public init(
        historySyncReport: HistorySyncReport,
        vehicleStatusRefreshed: Bool,
        smartActivitiesIndexed: Bool = true,
        wasCancelled: Bool = false
    ) {
        self.historySyncReport = historySyncReport
        self.vehicleStatusRefreshed = vehicleStatusRefreshed
        self.smartActivitiesIndexed = smartActivitiesIndexed
        self.wasCancelled = wasCancelled
    }

    public var isSuccessful: Bool {
        !wasCancelled && historySyncReport.failedCarIDs.isEmpty && vehicleStatusRefreshed && smartActivitiesIndexed
    }
}

public protocol BackgroundRefreshWorkRunning: Sendable {
    func run() async -> BackgroundRefreshReport
}

public struct BackgroundRefreshWorkRunner: BackgroundRefreshWorkRunning {
    private let historySyncRunner: any HistorySyncRunning
    private let refreshVehicleStatus: @Sendable () async -> Bool
    private let rebuildSmartActivities: @Sendable ([Int]) async -> Bool

    public init(
        historySyncRunner: any HistorySyncRunning,
        refreshVehicleStatus: @escaping @Sendable () async -> Bool,
        rebuildSmartActivities: @escaping @Sendable ([Int]) async -> Bool = { _ in true }
    ) {
        self.historySyncRunner = historySyncRunner
        self.refreshVehicleStatus = refreshVehicleStatus
        self.rebuildSmartActivities = rebuildSmartActivities
    }

    public func run() async -> BackgroundRefreshReport {
        guard !Task.isCancelled else {
            return cancelledReport()
        }
        let historyReport = await historySyncRunner.run()
        guard !Task.isCancelled else {
            return BackgroundRefreshReport(
                historySyncReport: historyReport,
                vehicleStatusRefreshed: false,
                wasCancelled: true
            )
        }
        let statusRefreshed = await refreshVehicleStatus()
        guard !Task.isCancelled else {
            return BackgroundRefreshReport(
                historySyncReport: historyReport,
                vehicleStatusRefreshed: statusRefreshed,
                smartActivitiesIndexed: false,
                wasCancelled: true
            )
        }
        let smartActivitiesIndexed = await rebuildSmartActivities(historyReport.completedCarIDs)
        return BackgroundRefreshReport(
            historySyncReport: historyReport,
            vehicleStatusRefreshed: statusRefreshed,
            smartActivitiesIndexed: smartActivitiesIndexed,
            wasCancelled: Task.isCancelled
        )
    }

    private func cancelledReport() -> BackgroundRefreshReport {
        BackgroundRefreshReport(
            historySyncReport: HistorySyncReport(attemptedCarIDs: [], completedCarIDs: [], failedCarIDs: []),
            vehicleStatusRefreshed: false,
            smartActivitiesIndexed: false,
            wasCancelled: true
        )
    }
}
