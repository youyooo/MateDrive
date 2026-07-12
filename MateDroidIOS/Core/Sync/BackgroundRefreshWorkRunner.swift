import Foundation

public struct BackgroundRefreshReport: Equatable, Sendable {
    public let historySyncReport: HistorySyncReport
    public let vehicleStatusRefreshed: Bool
    public let wasCancelled: Bool

    public init(historySyncReport: HistorySyncReport, vehicleStatusRefreshed: Bool, wasCancelled: Bool = false) {
        self.historySyncReport = historySyncReport
        self.vehicleStatusRefreshed = vehicleStatusRefreshed
        self.wasCancelled = wasCancelled
    }

    public var isSuccessful: Bool {
        !wasCancelled && historySyncReport.failedCarIDs.isEmpty && vehicleStatusRefreshed
    }
}

public protocol BackgroundRefreshWorkRunning: Sendable {
    func run() async -> BackgroundRefreshReport
}

public struct BackgroundRefreshWorkRunner: BackgroundRefreshWorkRunning {
    private let historySyncRunner: any HistorySyncRunning
    private let refreshVehicleStatus: @Sendable () async -> Bool

    public init(
        historySyncRunner: any HistorySyncRunning,
        refreshVehicleStatus: @escaping @Sendable () async -> Bool
    ) {
        self.historySyncRunner = historySyncRunner
        self.refreshVehicleStatus = refreshVehicleStatus
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
        return BackgroundRefreshReport(
            historySyncReport: historyReport,
            vehicleStatusRefreshed: statusRefreshed,
            wasCancelled: Task.isCancelled
        )
    }

    private func cancelledReport() -> BackgroundRefreshReport {
        BackgroundRefreshReport(
            historySyncReport: HistorySyncReport(attemptedCarIDs: [], completedCarIDs: [], failedCarIDs: []),
            vehicleStatusRefreshed: false,
            wasCancelled: true
        )
    }
}
