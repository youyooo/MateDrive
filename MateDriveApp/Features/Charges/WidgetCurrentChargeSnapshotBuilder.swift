import Foundation

public enum WidgetCurrentChargeSnapshotBuilder {
    public static func build(
        statusResult: APIResult<CarStatusPayload>,
        currentChargeResult: APIResult<CurrentChargeOutcome>?,
        previous: WidgetCurrentChargeData?,
        now: Date
    ) -> WidgetCurrentChargeData? {
        guard case let .success(payload) = statusResult,
              let status = payload.status
        else {
            return previous?.markingOffline()
        }

        guard status.isCharging else {
            return WidgetCurrentChargeData(
                phase: .idle,
                quality: .complete,
                batteryLevel: status.batteryLevel,
                chargeLimitSoc: status.chargeLimitSoc,
                updatedAt: now
            )
        }

        switch currentChargeResult {
        case let .success(.active(detail)):
            return makeCharging(
                status: status,
                detail: detail,
                quality: .complete,
                now: now
            )
        case .success(.noActiveCharge):
            return makeStarting(status: status, now: now)
        case .failure, .none:
            return makeCharging(
                status: status,
                detail: nil,
                quality: .partial,
                now: now
            )
        }
    }

    private static func makeCharging(
        status: CarStatus,
        detail: ChargeDetail?,
        quality: WidgetChargeDataQuality,
        now: Date
    ) -> WidgetCurrentChargeData {
        let latestPoint = detail.flatMap(latestChargePoint)
        let chargingDetails = status.chargingDetails

        return WidgetCurrentChargeData(
            phase: .charging,
            quality: quality,
            batteryLevel: status.batteryLevel
                ?? detail?.currentOrEndBatteryLevel
                ?? latestPoint?.batteryLevel,
            chargeLimitSoc: status.chargeLimitSoc,
            chargerPowerKW: status.chargerPower ?? latestPoint?.chargerPower,
            energyAddedKWh: detail?.chargeEnergyAdded
                ?? chargingDetails?.chargeEnergyAdded
                ?? latestPoint?.chargeEnergyAdded,
            timeToFullMinutes: chargingDetails?.timeToFullCharge.map { Int(($0 * 60).rounded()) },
            isDC: chargingDetails?.chargerPhases.map { $0 == 0 }
                ?? latestPoint?.chargerDetails?.chargerPhases.map { $0 == 0 },
            updatedAt: now
        )
    }

    private static func makeStarting(status: CarStatus, now: Date) -> WidgetCurrentChargeData {
        let chargingDetails = status.chargingDetails
        return WidgetCurrentChargeData(
            phase: .starting,
            quality: .complete,
            batteryLevel: status.batteryLevel,
            chargeLimitSoc: status.chargeLimitSoc,
            chargerPowerKW: status.chargerPower,
            timeToFullMinutes: chargingDetails?.timeToFullCharge.map { Int(($0 * 60).rounded()) },
            isDC: chargingDetails?.chargerPhases.map { $0 == 0 },
            updatedAt: now
        )
    }

    private static func latestChargePoint(in detail: ChargeDetail) -> ChargePoint? {
        guard let chargePoints = detail.chargePoints, !chargePoints.isEmpty else { return nil }

        let datedPoints = chargePoints.compactMap { point -> (ChargePoint, Date)? in
            guard let date = point.date.flatMap(DomainDateParser.date(from:)) else { return nil }
            return (point, date)
        }
        return datedPoints.max { $0.1 < $1.1 }?.0 ?? chargePoints.first
    }
}
