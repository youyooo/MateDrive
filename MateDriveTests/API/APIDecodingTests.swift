import XCTest
@testable import MateDriveApp

final class APIDecodingTests: XCTestCase {
    func testCostReviewDecodesAPI26ContractWithoutConvertingMissingCostsToZero() throws {
        let data = #"{"contractVersion":1,"data":{"range":{"startDate":"2026-07-01T00:00:00+08:00","endDate":"2026-07-08T00:00:00+08:00","period":"day"},"summary":{"recordedSpend":27.83,"estimatedUseCost":210.89,"chargingCost":27.83,"parkingCost":null,"estimatedDrivingEnergyCost":113.25,"estimatedStandbyEnergyCost":97.64,"totalDistanceKm":527.14,"driveCount":31,"chargeCount":7,"costRecordedChargeCount":1,"missingChargeCostCount":6,"parkingEventCount":30,"missingParkingCostCount":30,"zeroParkingCostCount":0},"dataQuality":{"hasAnyActivity":true,"hasStatsSummary":true,"chargingCost":{"eventCount":7,"costRecordedCount":1,"missingCostCount":6,"zeroCostCount":0,"costCoverage":0.142857},"parkingCost":{"eventCount":30,"costRecordedCount":0,"missingCostCount":30,"zeroCostCount":0,"costCoverage":0},"energyEstimate":{"isAvailable":true,"pricePerKwh":1.287,"consumptionWhPerKm":266.1}},"buckets":[{"id":"day:1782835200000","dateFrom":1782835200000,"dateTo":1782921600000,"granularity":"day","estimatedUseCost":42.5,"recordedSpend":null,"chargingSpend":null,"estimatedDrivingEnergyCost":31.2,"estimatedStandbyEnergyCost":11.3,"parkingCost":null,"chargingEnergyKwh":18.2,"chargeCount":1,"driveCount":4}],"chargingModes":[{"mode":"AC","chargeCount":5,"energyKwh":88.2}],"placeRankings":{"charging":[{"kind":"charging","placeId":3,"displayName":"Home","chargeCount":5,"totalEnergyKwh":88.2,"totalCost":27.83,"costRecordedCount":1,"missingCostCount":4,"zeroCostCount":0}],"parking":[],"standby":[],"parkingZeroCostConfirmed":false},"comparison":{"previousRange":{"startDate":"2026-06-24T00:00:00+08:00","endDate":"2026-07-01T00:00:00+08:00","period":"day"},"estimatedUseCost":{"isEligible":false,"currentValue":210.89,"previousValue":218.34,"delta":null,"percentageChange":null,"reasonCodes":["current_missing_parking_cost"]}},"records":{"topCharges":[{"id":14,"type":"charge","title":"Home","startDate":"2026-06-25T12:00:00Z","energyKwh":21.62,"cost":27.83,"durationMin":42}],"missingChargeCosts":[{"id":15,"type":"charge","title":"Work","startDate":"2026-07-02T12:00:00Z","energyKwh":18.2,"durationMin":35}],"missingParkingCosts":[{"id":99,"type":"park","title":"Office","startDate":"2026-07-02T13:00:00Z","durationMin":120,"rangeLossKm":1.2}]}},"units":{"unit_of_length":"km","unit_of_pressure":"bar","unit_of_temperature":"C"}}"#.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CostReviewResponse.self, from: data)

        XCTAssertEqual(response.contractVersion, 1)
        XCTAssertEqual(response.data.range.period, "day")
        XCTAssertEqual(response.data.summary.recordedSpend, 27.83)
        XCTAssertNil(response.data.summary.parkingCost)
        XCTAssertEqual(response.data.dataQuality.chargingCost.missingCostCount, 6)
        XCTAssertEqual(response.data.dataQuality.parkingCost.zeroCostCount, 0)
        XCTAssertNil(response.data.buckets.first?.recordedSpend)
        XCTAssertEqual(response.data.comparison?.estimatedUseCost?.reasonCodes, ["current_missing_parking_cost"])
        XCTAssertEqual(response.data.records.missingChargeCosts.first?.id, 15)
        XCTAssertEqual(response.units?.unitOfLength, "km")
    }

    func testCarStatusLocationUsesGeofenceThenFallsBackToValidCoordinates() {
        let geofencedPoint = SyntheticCoordinates.point()
        let coordinateOnlyPoint = SyntheticCoordinates.point(latitudeOffset: 0.207471, longitudeOffset: 0.857773)
        let geofenced = CarStatus(carGeodata: CarGeodata(geofence: "Home", latitude: geofencedPoint.latitude, longitude: geofencedPoint.longitude))
        let coordinates = CarStatus(carGeodata: CarGeodata(geofence: "", latitude: coordinateOnlyPoint.latitude, longitude: coordinateOnlyPoint.longitude))
        let invalid = CarStatus(carGeodata: CarGeodata(geofence: "", latitude: SyntheticCoordinates.zero.latitude, longitude: SyntheticCoordinates.zero.longitude))

        XCTAssertEqual(geofenced.locationSummary, "Home")
        XCTAssertEqual(coordinates.locationSummary, "12.20747, 34.85777")
        XCTAssertNil(invalid.locationSummary)
    }

    func testGlobalSettingsDecodeNestedTeslaMateApiPayload() throws {
        let data = #"{"data":{"settings":{"teslamate_units":{"unit_of_length":"km","unit_of_temperature":"C"},"teslamate_webgui":{"language":"zh","preferred_range":"rated"}}}}"#.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(GlobalSettingsResponse.self, from: data)

        XCTAssertEqual(response.data?.settings?.unitOfLength, "km")
        XCTAssertEqual(response.data?.settings?.unitOfTemperature, "C")
        XCTAssertNil(response.data?.settings?.unitOfPressure)
        XCTAssertEqual(response.data?.settings?.preferredRange, "rated")
    }

    func testGlobalSettingsDecodeLegacyFlatPayload() throws {
        let data = #"{"data":{"settings":{"unit_of_length":"mi","unit_of_temperature":"F","unit_of_pressure":"psi","preferred_range":"ideal"}}}"#.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(GlobalSettingsResponse.self, from: data)

        XCTAssertEqual(
            response.data?.settings,
            GlobalSettingsData(unitOfLength: "mi", unitOfTemperature: "F", unitOfPressure: "psi", preferredRange: "ideal")
        )
    }

    func testDriveInsightsAndActivityEvaluationsDecodeMeasured241Fields() throws {
        let insightData = #"{"data":{"drive_stats":[{"start_latitude":28.207473,"start_longitude":112.857964,"end_latitude":28.311716,"end_longitude":112.822016,"start_address":"长科路, 岳麓区","end_address":"乌山街道","drive_count":7,"avg_distance_km":16.0644,"avg_duration_min":27.8571,"avg_energy_kwh":-2.988,"consumption_wh_km":186.0009,"last_drive_date":"2026-07-09T23:24:17.553Z","most_common_hour":7}],"units":{"unit_of_length":"km"}}}"#.data(using: .utf8)!
        let activityData = #"{"data":[{"id":136,"type":"drive","stats":{"regen_utilization":0.9219,"hard_braking_count":0,"is_new_place":false,"commute_route_id":3,"evaluations":[{"type":"short_trip_hvac","priority":3,"titleKey":"drive_eval_short_trip_title","messageKey":"drive_eval_short_trip_message","data":{"duration":64}}]}}]}"#.data(using: .utf8)!

        let insights = try JSONDecoder.teslamate.decode(TeslaMateDriveInsightsResponse.self, from: insightData)
        let activities = try JSONDecoder.teslamate.decode(TeslaMateActivitiesResponse.self, from: activityData)

        XCTAssertEqual(insights.data?.driveStats.first?.driveCount, 7)
        XCTAssertEqual(insights.data?.driveStats.first?.consumptionWhKm, 186.0009)
        XCTAssertEqual(insights.data?.driveStats.first?.avgEnergyKwh, -2.988)
        XCTAssertEqual(activities.data.first?.stats?.regenUtilization, 0.9219)
        XCTAssertEqual(activities.data.first?.stats?.commuteRouteId, 3)
        XCTAssertEqual(activities.data.first?.stats?.evaluations?.first?.type, "short_trip_hvac")
    }

    func testBatteryHistoryDecodesLateRecordingDataAndNormalizesEfficiencyByFieldContract() throws {
        let data = #"{"data":{"charts":{"capacity":[{"date":"2026-06-25","odometer":117512.799581,"capacity":69.527446}],"capacity_median":[{"bucket":"2026062","date":"2026-06-25","odometer":117512.799581,"capacity":69.5}],"range":[{"date":"2026-06-25","odometer":117500.163984,"range":476.946056},{"date":"2026-07-11","odometer":118651.256936,"range":471.762126}]},"efficiency":{"value":14.6,"source":"derived","ready":true,"qualifying_charge_count":7,"required_charge_count":2},"units":{"unit_of_length":"km","unit_of_energy":"kWh"}}}"#.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(BatteryHistoryResponse.self, from: data)

        XCTAssertEqual(response.data?.charts?.capacity.first?.capacity, 69.527446)
        XCTAssertEqual(response.data?.charts?.capacityMedian.first?.bucket, "2026062")
        XCTAssertEqual(response.data?.charts?.range.last?.range, 471.762126)
        XCTAssertEqual(response.data?.efficiency?.value, 14.6)
        XCTAssertEqual(response.data?.efficiency?.whPerKm, 146)
        XCTAssertEqual(response.data?.efficiency?.qualifyingChargeCount, 7)
        XCTAssertEqual(response.data?.units?.unitOfLength, "km")
    }

    func testActivitiesDecodeDriveChargeAndParkWithBroken241Pagination() throws {
        let data = #"{"data":[{"id":136,"type":"drive","startDate":"2026-07-10T09:48:12.837Z","durationMin":64,"kwh":-3.9201,"socDiff":-5,"distanceKm":17.9666},{"id":14,"type":"charge","durationMin":37,"kwh":39.82,"kwhUsed":43.26,"cost":18.5,"socDiff":58},{"id":1783641219835,"type":"park","durationMin":594.5672,"rangeDiffKm":-5.30459,"socDiff":-1}],"pagination":{"totalRecords":0,"totalPages":9999,"page":1,"limit":20},"units":{"unit_of_length":"km"}}"#.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(TeslaMateActivitiesResponse.self, from: data)

        XCTAssertEqual(response.data.map(\.kind), [.drive, .charge, .park])
        XCTAssertEqual(response.data[0].distanceKm, 17.9666)
        XCTAssertEqual(response.data[1].kwhUsed, 43.26)
        XCTAssertEqual(response.data[1].cost, 18.5)
        XCTAssertEqual(response.data[2].id, 1_783_641_219_835)
        XCTAssertEqual(response.pagination?.totalRecords, 0)
        XCTAssertEqual(response.pagination?.totalPages, 9_999)
        XCTAssertEqual(response.pagination?.limit, 20)
    }

    func testServerStatsDecodesMeasured241SummaryWithoutChangingUnits() throws {
        let data = #"{"summary":{"totalDistanceKm":1010.08468,"totalChargingCost":27.83,"avgConsumptionNet":188.7289,"avgConsumptionGross":252.0024,"avgRegenCaptureRate":0.9419688,"totalHardBrakingCount":62,"avgHardBrakingPer100km":6.1381,"avgPctSpeed120Plus":0.0123079,"totalStandbyRangeLossKm":499.318,"avgDrainRateKmH":1.6213,"parkingEventCount":37,"evaluations":{"goldenFootCount":2,"shortTripHVACCount":31}},"data":[{"date":"2026-07-10","distanceKm":34.4885,"consumptionNet":184.9525}],"pagination":{"totalRecords":15,"totalPages":1,"page":1,"limit":50},"units":{"unit_of_length":"km","unit_of_pressure":"bar","unit_of_temperature":"C"}}"#.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(TeslaMateServerStatsResponse.self, from: data)

        XCTAssertEqual(response.summary?.totalDistanceKm, 1010.08468)
        XCTAssertEqual(response.summary?.avgConsumptionNet, 188.7289)
        XCTAssertEqual(response.summary?.avgRegenCaptureRate, 0.9419688)
        XCTAssertEqual(response.summary?.totalHardBrakingCount, 62)
        XCTAssertEqual(response.summary?.evaluations?.shortTripHVACCount, 31)
        XCTAssertEqual(response.data.first?.consumptionNet, 184.9525)
        XCTAssertEqual(response.pagination?.totalRecords, 15)
        XCTAssertEqual(response.units?.unitOfLength, "km")
    }

    func testCarsResponseDecodesSnakeCasePayload() throws {
        let data = """
        {
          "data": {
            "cars": [
              {
                "car_id": 7,
                "display_name": "Model 3",
                "car_details": {
                  "model": "model3",
                  "trim_badging": "p"
                },
                "car_exterior": {
                  "exterior_color": "PPSW",
                  "wheel_type": "Pinwheel18"
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarsResponse.self, from: data)

        XCTAssertEqual(response.data?.cars.first?.carId, 7)
        XCTAssertEqual(response.data?.cars.first?.carDetails?.trimBadging, "p")
        XCTAssertEqual(response.data?.cars.first?.carExterior?.exteriorColor, "PPSW")
    }

    func testCarsResponseDecodesStringCarId() throws {
        let data = """
        {
          "data": {
            "cars": [
              {
                "car_id": "12",
                "display_name": "Model Y",
                "car_details": {
                  "model": "Y",
                  "trim_badging": "lr"
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarsResponse.self, from: data)
        let car = response.data?.cars.first

        XCTAssertEqual(car?.carId, 12)
        XCTAssertEqual(car?.displayName, "Model Y")
    }

    func testCarsResponseDecodesIdFallbackWhenCarIdIsMissing() throws {
        let data = """
        {
          "data": {
            "cars": [
              {
                "id": "13",
                "name": "Red S",
                "car_details": {
                  "model": "S",
                  "trim_badging": "plaid"
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarsResponse.self, from: data)
        let car = response.data?.cars.first

        XCTAssertEqual(car?.carId, 13)
        XCTAssertEqual(car?.vehicleModelName, "Model S Plaid")
    }

    func testCarsResponseDecodesVehicleSummaryPayload() throws {
        let data = """
        {
          "data": {
            "cars": [
              {
                "car_id": 3,
                "name": "Blue Y",
                "car_details": {
                  "model": "Y",
                  "trim_badging": "74D",
                  "efficiency": 167.4
                },
                "car_exterior": {
                  "exterior_color": "DeepBlueMetallic",
                  "wheel_type": "Gemini19"
                },
                "teslamate_stats": {
                  "total_charges": 41,
                  "total_drives": 802,
                  "total_updates": 19
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarsResponse.self, from: data)

        XCTAssertEqual(response.data?.cars.first?.displayName, "Blue Y")
        XCTAssertEqual(response.data?.cars.first?.teslamateStats?.totalCharges, 41)
        XCTAssertEqual(response.data?.cars.first?.teslamateStats?.totalUpdates, 19)
        XCTAssertEqual(response.data?.cars.first?.carDetails?.efficiency, 167.4)
    }

    func testCarsResponseDerivesModelYearWithoutExposingVIN() throws {
        let data = #"{"data":{"cars":[{"car_id":1,"name":"","car_details":{"vin":"TSTMODEL3N0000000","model":"3","trim_badging":"P74D"},"car_exterior":{"exterior_color":"MidnightSilver","wheel_type":"Pinwheel18CapKit"}}]}}"#.data(using: .utf8)!

        let car = try XCTUnwrap(JSONDecoder.teslamate.decode(CarsResponse.self, from: data).data?.cars.first)

        XCTAssertEqual(car.modelYear, 2022)
        XCTAssertEqual(car.vehicleModelName, "Model 3 Performance")
        XCTAssertEqual(car.vehicleModelDescription, "2022 Model 3 Performance")
        XCTAssertEqual(car.dashboardDisplayName, "2022 Model 3 Performance")
        XCTAssertFalse(car.dashboardDisplayName.contains("LRW"))
    }

    func testVINModelYearUsesCurrentThirtyYearCycle() {
        XCTAssertEqual(CarDetails.modelYear(fromVIN: "TSTMODEL3N0000000", currentYear: 2026), 2022)
        XCTAssertEqual(CarDetails.modelYear(fromVIN: "TSTMODEL3P0000000", currentYear: 2026), 2023)
        XCTAssertNil(CarDetails.modelYear(fromVIN: "invalid", currentYear: 2026))
    }

    func testCarsResponseResolvesModelIdentityWhenNameIsMissing() throws {
        let data = """
        {
          "data": {
            "cars": [
              {
                "car_id": 8,
                "car_details": {
                  "model": "model3",
                  "trim_badging": "P"
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarsResponse.self, from: data)
        let car = response.data?.cars.first

        XCTAssertEqual(car?.displayName, "Model 3 Performance")
        XCTAssertEqual(car?.vehicleModelName, "Model 3 Performance")
    }

    func testCarsResponseIgnoresCurrentAppNameWhenModelIdentityExists() throws {
        let data = """
        {
          "data": {
            "cars": [
              {
                "car_id": 10,
                "display_name": "MateDrive",
                "name": "MateDrive",
                "car_details": {
                  "model": "Y",
                  "trim_badging": "lr"
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarsResponse.self, from: data)
        let car = response.data?.cars.first

        XCTAssertEqual(car?.displayName, "Model Y Long Range")
        XCTAssertEqual(car?.vehicleModelName, "Model Y Long Range")
    }

    func testCarsResponseIgnoresAppNameVariantsWhenModelIdentityExists() throws {
        let data = """
        {
          "data": {
            "cars": [
              {
                "car_id": 11,
                "display_name": "MateDrive iOS",
                "name": "MateDrive - Model 3",
                "car_details": {
                  "model": "model3",
                  "trim_badging": "P"
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarsResponse.self, from: data)
        let car = response.data?.cars.first

        XCTAssertEqual(car?.displayName, "Model 3 Performance")
        XCTAssertEqual(car?.vehicleModelName, "Model 3 Performance")
    }

    func testCarStatusResponseDecodesNestedDashboardFields() throws {
        let data = """
        {
          "data": {
            "status": {
              "display_name": "Model Y",
              "car_status": {
                "locked": true,
                "sentry_mode": true,
                "center_display_state": "7"
              },
              "climate_details": {
                "inside_temp": 21.5,
                "outside_temp": 8.0
              },
              "battery_details": {
                "battery_level": 68
              },
              "charging_details": {
                "charging_state": "Charging",
                "charger_phases": 0,
                "plugged_in": true
              }
            },
            "units": {
              "unit_of_length": "km",
              "unit_of_temperature": "C",
              "unit_of_pressure": "bar"
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarStatusResponse.self, from: data)
        let status = response.data?.status

        XCTAssertEqual(status?.displayName, "Model Y")
        XCTAssertEqual(status?.batteryLevel, 68)
        XCTAssertTrue(status?.isCharging == true)
        XCTAssertTrue(status?.isDcCharging == true)
        XCTAssertTrue(status?.isSentryAlerted == true)
        XCTAssertEqual(status?.outsideTemp, 8.0)
        XCTAssertEqual(response.data?.units?.unitOfTemperature, "C")
    }

    func testCarStatusResponseDecodesNumericCenterDisplayState() throws {
        let data = """
        {
          "data": {
            "status": {
              "car_status": {
                "center_display_state": 7
              }
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarStatusResponse.self, from: data)

        XCTAssertEqual(response.data?.status?.centerDisplayState, "7")
        XCTAssertTrue(response.data?.status?.isSentryAlerted == true)
    }

    func testCarStatusDecodesTeslaMateAPITpmsFieldNames() throws {
        let data = #"{"data":{"status":{"tpms_details":{"tpms_pressure_fl":3.0,"tpms_pressure_fr":3.075,"tpms_pressure_rl":2.95,"tpms_pressure_rr":3.0,"tpms_soft_warning_fl":false,"tpms_soft_warning_fr":true,"tpms_soft_warning_rl":false,"tpms_soft_warning_rr":false}}}}"#.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(CarStatusResponse.self, from: data)
        let tpms = try XCTUnwrap(response.data?.status?.tpmsDetails)

        XCTAssertEqual(tpms.pressureFl, 3.0)
        XCTAssertEqual(tpms.pressureFr, 3.075)
        XCTAssertEqual(tpms.pressureRl, 2.95)
        XCTAssertEqual(tpms.pressureRr, 3.0)
        XCTAssertEqual(tpms.warningFr, true)
        XCTAssertTrue(tpms.hasAnyData)
        XCTAssertTrue(tpms.hasWarning)
    }

    func testChargeDetailResponseDecodesPointsAndNestedBatteryFields() throws {
        let data = """
        {
          "data": {
            "charge": {
              "charge_id": 42,
              "start_date": "2026-07-01T09:00:00Z",
              "address": "Supercharger",
              "charge_energy_added": 32.5,
              "duration_min": 28,
              "battery_details": {
                "start_battery_level": 18,
                "end_battery_level": 68
              },
              "charge_details": [
                {
                  "battery_level": 18,
                  "charger_details": {
                    "charger_power": 120,
                    "charger_voltage": 400,
                    "charger_actual_current": 300,
                    "charger_phases": 0
                  },
                  "conn_charge_cable": "GB_DC",
                  "fast_charger_info": {
                    "fast_charger_present": true,
                    "fast_charger_brand": "Tesla",
                    "fast_charger_type": "GB"
                  }
                }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(ChargeDetailResponse.self, from: data)
        let charge = response.data?.charge

        XCTAssertEqual(charge?.chargeId, 42)
        XCTAssertEqual(charge?.startBatteryLevel, 18)
        XCTAssertEqual(charge?.endBatteryLevel, 68)
        XCTAssertEqual(charge?.chargePoints?.first?.chargerPower, 120)
        XCTAssertEqual(charge?.chargePoints?.first?.chargerDetails?.chargerPhases, 0)
        XCTAssertEqual(charge?.chargePoints?.first?.connectorType, "GB_DC")
        XCTAssertEqual(charge?.chargePoints?.first?.chargerDetails?.fastChargerPresent, true)
        XCTAssertEqual(charge?.chargePoints?.first?.chargerDetails?.fastChargerBrand, "Tesla")
        XCTAssertEqual(charge?.chargePoints?.first?.chargerDetails?.fastChargerType, "GB")
        XCTAssertEqual(charge.map(ChargingSessionAnalyzer.chargerIdentity), .teslaSupercharger)
    }

    func testDriveDetailResponseDecodesPositionsAndNestedFields() throws {
        let data = """
        {
          "data": {
            "car": {
              "car_id": 1,
              "car_name": "Model 3"
            },
            "drive": {
              "drive_id": 77,
              "start_date": "2026-07-01T08:00:00Z",
              "end_date": "2026-07-01T08:30:00Z",
              "start_address": "Home",
              "end_address": "Work",
              "odometer_details": {
                "odometer_start": 1000.0,
                "odometer_end": 1024.5,
                "odometer_distance": 24.5
              },
              "battery_details": {
                "start_battery_level": 80,
                "end_battery_level": 72
              },
              "energy_consumed_net": 4.9,
              "drive_details": [
                {
                  "date": "2026-07-01T08:00:00Z",
                  "latitude": 48.1,
                  "longitude": 2.1,
                  "speed": 30,
                  "power": 12,
                  "battery_level": 80,
                  "elevation": 45,
                  "tpms_pressure_fl": 3.0,
                  "tpms_pressure_fr": 3.1,
                  "tpms_pressure_rl": 2.9,
                  "tpms_pressure_rr": 2.8,
                  "tire_pressure_gap": 0.3,
                  "climate_info": {
                    "inside_temp": 21.0,
                    "outside_temp": 12.5,
                    "is_climate_on": true
                  }
                }
              ]
            },
            "units": {
              "unit_of_length": "km",
              "unit_of_pressure": "bar",
              "unit_of_temperature": "C"
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(DriveDetailResponse.self, from: data)
        let drive = response.data?.drive

        XCTAssertEqual(response.data?.car?.carName, "Model 3")
        XCTAssertEqual(drive?.driveId, 77)
        XCTAssertEqual(drive?.distance, 24.5)
        XCTAssertEqual(drive?.startBatteryLevel, 80)
        XCTAssertEqual(drive?.positions?.first?.outsideTemp, 12.5)
        XCTAssertTrue(drive?.positions?.first?.isClimateOn == true)
        XCTAssertEqual(drive?.positions?.first?.latitude, 48.1)
        XCTAssertEqual(drive?.positions?.first?.tpmsPressureFl, 3.0)
        XCTAssertEqual(drive?.positions?.first?.tpmsPressureFr, 3.1)
        XCTAssertEqual(drive?.positions?.first?.tpmsPressureRl, 2.9)
        XCTAssertEqual(drive?.positions?.first?.tpmsPressureRr, 2.8)
        XCTAssertEqual(drive?.positions?.first?.tirePressureGap, 0.3)
        XCTAssertEqual(drive?.sourceUnits?.unitOfPressure, "bar")
    }

    func testBatteryHealthAndUpdatesDecodeAPIResponses() throws {
        let batteryData = """
        {
          "data": {
            "battery_health": {
              "max_range": 500.0,
              "current_range": 450.0,
              "max_capacity": 82.0,
              "current_capacity": 74.0,
              "rated_efficiency": 155.0,
              "battery_health_percentage": 90.2
            }
          }
        }
        """.data(using: .utf8)!
        let updatesData = """
        {
          "data": {
            "updates": [
              {
                "update_id": 5,
                "version": "2026.20.1 abc123",
                "start_date": "2026-07-01T08:00:00Z",
                "end_date": "2026-07-01T08:30:00Z"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let battery = try JSONDecoder.teslamate.decode(BatteryHealthResponse.self, from: batteryData)
        let updates = try JSONDecoder.teslamate.decode(UpdatesResponse.self, from: updatesData)

        XCTAssertEqual(battery.data?.batteryHealth?.batteryHealthPercentage, 90.2)
        XCTAssertEqual(updates.data?.updates?.first?.updateId, 5)
        XCTAssertEqual(updates.data?.updates?.first?.version, "2026.20.1 abc123")
    }

    func testBatteryHealthDecodesTeslaMateAPIBatteryDataPayload() throws {
        let data = """
        {
          "data": {
            "battery_data": {
              "max_capacity": 69.5,
              "current_capacity": 69.1,
              "max_range": 476.0,
              "current_max_range": 473.7,
              "rated_efficiency": 14.6,
              "battery_health": 99.4
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.teslamate.decode(BatteryHealthResponse.self, from: data)
        let health = response.data?.batteryHealth

        XCTAssertEqual(health?.currentRange, 473.7)
        XCTAssertEqual(health?.ratedEfficiency, 146.0)
        XCTAssertEqual(health?.batteryHealthPercentage, 99.4)
    }

    func testBatteryHealthNormalizesRatioAndOutlierPercentages() throws {
        let ratioData = """
        {
          "data": {
            "battery_data": {
              "battery_health": 0.912
            }
          }
        }
        """.data(using: .utf8)!
        let outlierData = """
        {
          "data": {
            "battery_health": {
              "battery_health_percentage": 104.5
            }
          }
        }
        """.data(using: .utf8)!

        let ratio = try JSONDecoder.teslamate.decode(BatteryHealthResponse.self, from: ratioData)
        let outlier = try JSONDecoder.teslamate.decode(BatteryHealthResponse.self, from: outlierData)

        XCTAssertEqual(ratio.data?.batteryHealth?.batteryHealthPercentage, 91.2)
        XCTAssertEqual(outlier.data?.batteryHealth?.batteryHealthPercentage, 100)
    }
}
