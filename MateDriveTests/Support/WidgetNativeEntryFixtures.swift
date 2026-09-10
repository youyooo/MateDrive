import Foundation
@testable import MateDriveApp

extension WidgetCurrentChargeData {
    static func fixture(
        phase: WidgetChargePhase = .charging,
        quality: WidgetChargeDataQuality = .complete,
        batteryLevel: Int? = nil,
        chargeLimitSoc: Int? = nil,
        chargerPowerKW: Int? = nil,
        energyAddedKWh: Double? = nil,
        timeToFullMinutes: Int? = nil,
        isDC: Bool? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 1_786_320_000)
    ) -> Self {
        Self(
            phase: phase,
            quality: quality,
            batteryLevel: batteryLevel,
            chargeLimitSoc: chargeLimitSoc,
            chargerPowerKW: chargerPowerKW,
            energyAddedKWh: energyAddedKWh,
            timeToFullMinutes: timeToFullMinutes,
            isDC: isDC,
            updatedAt: updatedAt
        )
    }
}

extension WidgetVehicleSnapshot {
    static func fixture(
        id: String = String(repeating: "a", count: 64),
        data: WidgetDisplayData = .fixture(
            carName: "Model 3",
            displayLanguage: .english
        ),
        batteryTrend: WidgetBatteryTrendData? = nil,
        chargingTrend: WidgetChargingTrendData? = nil,
        currentCharge: WidgetCurrentChargeData? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 1_786_320_000)
    ) -> Self {
        Self(
            id: id,
            data: data,
            batteryTrend: batteryTrend,
            chargingTrend: chargingTrend,
            currentCharge: currentCharge,
            updatedAt: updatedAt
        )
    }
}

extension ChargeLiveActivitySnapshot {
    static func fixture(
        carName: String = "Model 3",
        batteryLevel: Int? = 64,
        chargeLimitSoc: Int? = 80,
        chargerPowerKW: Int? = 72,
        energyAddedKWh: Double? = 18.4,
        timeToFullMinutes: Int? = 65,
        isDC: Bool = false,
        isCharging: Bool = true,
        updatedAt: Date = Date(timeIntervalSince1970: 1_786_320_000)
    ) -> Self {
        Self(
            carName: carName,
            batteryLevel: batteryLevel,
            chargeLimitSoc: chargeLimitSoc,
            chargerPowerKW: chargerPowerKW,
            energyAddedKWh: energyAddedKWh,
            timeToFullMinutes: timeToFullMinutes,
            isDC: isDC,
            isCharging: isCharging,
            updatedAt: updatedAt
        )
    }
}
