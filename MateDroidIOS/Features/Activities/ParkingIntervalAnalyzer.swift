import Foundation

public enum ParkingIntervalAnalyzer {
    public static func analyze(_ input: ParkingIntervalInput) -> ParkingIntervalMetrics? {
        guard input.parking.kind == .park,
              let start = input.parking.startDate.flatMap(DomainDateParser.date(from:)),
              let end = input.parking.endDate.flatMap(DomainDateParser.date(from:)),
              start < end else { return nil }

        let previousEndSOC = input.previousDrive?.soc.flatMap { startSOC in
            input.previousDrive?.socDiff.map { startSOC + $0 }
        }
        let startSOC = input.parking.soc ?? previousEndSOC
        let recordedEndSOC = input.parking.soc.flatMap { startSOC in
            input.parking.socDiff.map { startSOC + $0 }
        }
        let endSOC = recordedEndSOC ?? input.nextDrive?.soc
        let netSOC = input.parking.socDiff ?? startSOC.flatMap { start in endSOC.map { $0 - start } }
        let chargeDeltas = input.charges.compactMap(\.socDiff)
        let chargeGain: Int? = input.charges.isEmpty
            ? nil
            : (chargeDeltas.count == input.charges.count ? chargeDeltas.filter { $0 > 0 }.reduce(0, +) : nil)
        let standby = input.charges.isEmpty
            ? netSOC
            : netSOC.flatMap { net in chargeGain.map { net - $0 } }
        let sleep = SleepDurationCalculator.total(intervals: input.sleepIntervals, from: start, to: end)
        let wakeCount = input.sleepIntervals.filter { interval in
            interval.start < end && interval.end > start && interval.end < end
        }.count
        let nextDriveStartRange = input.nextDrive?.endRangeKm.flatMap { endRange in
            input.nextDrive?.rangeDiffKm.map { endRange - $0 }
        }
        let endRange = input.parking.endRangeKm ?? nextDriveStartRange
        let startRange = input.parking.endRangeKm.flatMap { endRange in
            input.parking.rangeDiffKm.map { endRange - $0 }
        } ?? input.previousDrive?.endRangeKm
        let rangeDelta = input.parking.rangeDiffKm ?? startRange.flatMap { start in endRange.map { $0 - start } }
        let missing = [
            startSOC == nil ? "missing_start_soc" : nil,
            netSOC == nil ? "missing_soc_change" : nil,
            (!input.charges.isEmpty && chargeGain == nil) ? "missing_charge_soc_change" : nil,
            endRange == nil ? "missing_end_range" : nil
        ].compactMap { $0 }

        return ParkingIntervalMetrics(
            startDate: start,
            endDate: end,
            duration: end.timeIntervalSince(start),
            startBatteryPercent: startSOC,
            endBatteryPercent: endSOC,
            netBatteryChangePercent: netSOC,
            chargeGainPercent: chargeGain,
            standbyBatteryChangePercent: standby,
            startRatedRangeKm: startRange,
            endRatedRangeKm: endRange,
            ratedRangeChangeKm: rangeDelta,
            vehicleReportedChargeEnergyKWh: input.charges.compactMap(\.kwh).nilIfEmpty?.reduce(0, +),
            sleepDuration: sleep,
            awakeDuration: max(0, end.timeIntervalSince(start) - sleep),
            wakeCount: wakeCount,
            quality: missing.isEmpty ? .complete : .partial,
            missingReasonCodes: missing
        )
    }
}

private extension Collection {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
