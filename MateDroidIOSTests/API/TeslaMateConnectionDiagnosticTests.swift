import Foundation
import XCTest
@testable import MateDroidIOS

final class TeslaMateConnectionDiagnosticTests: XCTestCase {
    func testDiagnosticExportIncludesSupportEvidenceWithoutServerIdentity() {
        let generatedAt = Date(timeIntervalSince1970: 1_788_739_200)
        let checkedAt = generatedAt.addingTimeInterval(-60)
        let report = TeslaMateDiagnosticReport(
            checks: [
                TeslaMateDiagnosticCheck(
                    checkID: .cars,
                    status: .passed,
                    title: "车辆",
                    message: "可以读取 1 辆车。"
                ),
                TeslaMateDiagnosticCheck(
                    checkID: .environmentHistory,
                    status: .warning,
                    title: "环境历史",
                    message: "近 30 天胎压覆盖不足。"
                )
            ],
            serverProfile: TeslaMateServerProfile(
                serverKey: "private-server-fingerprint",
                carId: 42,
                version: TeslaMateVersionInfo(apiVersion: "2.6.0", mtAPIVersion: "2.6.1", buildInfo: "release"),
                capabilities: [
                    .environmentHistory: TeslaMateCapabilityStatus(
                        state: .degraded,
                        reason: .emptyPayload,
                        source: .endpointProbe,
                        checkedAt: checkedAt
                    ),
                    .coreCars: TeslaMateCapabilityStatus(
                        state: .available,
                        source: .endpointProbe,
                        checkedAt: checkedAt,
                        lastSuccessfulAt: checkedAt
                    )
                ],
                checkedAt: checkedAt
            )
        )

        let text = TeslaMateDiagnosticExport.render(
            report: report,
            metadata: TeslaMateDiagnosticExportMetadata(
                appVersion: "1.0",
                appBuild: "7",
                languageCode: "zh-Hans",
                unitSystem: "metric",
                currencyCode: "CNY"
            ),
            generatedAt: generatedAt
        )

        XCTAssertTrue(text.contains("MateDrive Diagnostic Report"))
        XCTAssertTrue(text.contains("app_version: 1.0 (7)"))
        XCTAssertTrue(text.contains("api_version: 2.6.1"))
        XCTAssertTrue(text.contains("summary: passed=1 warning=1 failed=0"))
        XCTAssertTrue(text.contains("coreCars: available"))
        XCTAssertTrue(text.contains("environmentHistory: degraded; reason=emptyPayload; source=endpointProbe"))
        XCTAssertTrue(text.contains("[warning] environmentHistory | 环境历史 | 近 30 天胎压覆盖不足。"))
        XCTAssertFalse(text.contains("private-server-fingerprint"))
        XCTAssertFalse(text.contains("car_id"))
        XCTAssertEqual(TeslaMateDiagnosticExport.suggestedFilename(generatedAt: generatedAt), "MateDrive-Diagnostics-2026-09-07T00-00-00Z.txt")
    }

    func testDiagnosticExportRedactsCredentialsHostsAndCoordinates() {
        let report = TeslaMateDiagnosticReport(checks: [
            TeslaMateDiagnosticCheck(
                checkID: .configuration,
                status: .failed,
                title: "Server teslamate.example",
                message: "GET https://example-user:example-password@192.0.2.10:3030/api?token=example-token failed; Authorization: Bearer example-bearer; password=example-password; location 12.345678, 98.765432"
            )
        ])

        let text = TeslaMateDiagnosticExport.render(
            report: report,
            metadata: TeslaMateDiagnosticExportMetadata(
                appVersion: "1.0",
                appBuild: "7",
                languageCode: "en",
                unitSystem: "teslamate",
                currencyCode: "USD"
            ),
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        for secret in ["teslamate.example", "192.0.2.10", "example-user", "example-password", "token=example-token", "Bearer example-bearer", "12.345678", "98.765432"] {
            XCTAssertFalse(text.contains(secret), "Export leaked: \(secret)")
        }
        XCTAssertTrue(text.contains("[REDACTED_URL]"))
        XCTAssertTrue(text.contains("[REDACTED_HOST]"))
        XCTAssertTrue(text.contains("[REDACTED_CREDENTIAL]"))
        XCTAssertTrue(text.contains("[REDACTED_COORDINATES]"))
    }

    func testDiagnosticReportsReadableCoreEndpointsAndDataWarnings() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"}}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":{"battery_details":{"battery_level":50}},"units":{"unit_of_length":"km"}}}"#),
            "/api/v1/globalsettings": (200, #"{"data":{"settings":{"unit_of_length":"km","unit_of_temperature":"C","preferred_range":"rated"}}}"#),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[]}}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "/api/v1/cars/1/environment-history": (200, #"{"data":{"series":[],"summary":{"point_count":0,"sample_count":0},"temperature_energy_buckets":[],"leak_observations":[]}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#),
            "/api/v1/cars/1/updates": (200, #"{"data":{"updates":[]}}"#),
            "/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertFalse(report.hasFailure)
        XCTAssertTrue(report.hasWarning)
        XCTAssertEqual(report.checks.map(\.checkID), [.configuration, .cars, .vehicleInfo, .status, .settings, .drives, .charges, .historyDataQuality, .environmentHistory, .batteryHealth, .softwareUpdates, .currentCharge])
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .vehicleInfo })?.message, "可以识别车型 Model 3，但外观颜色或轮毂类型缺失。首页车辆图片可能会使用默认配置。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .settings })?.message, "可以读取全局设置。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .drives })?.status, .warning)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .charges })?.message, "暂未返回充电记录。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .environmentHistory })?.message, "接口可以读取，但近 30 天没有返回带时间的环境采样。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .softwareUpdates })?.message, "软件更新接口可访问，但暂未返回更新记录。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .currentCharge })?.message, "当前充电接口可访问；当前没有进行中的充电。")
        XCTAssertEqual(report.summary(language: .chinese), "连接测试完成，但有警告")
    }

    func testDiagnosticChecksLatestDriveAndChargeDetailsWhenRecordsExist() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"},"car_exterior":{"exterior_color":"PBSB","wheel_type":"W39B"}}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":{"battery_details":{"battery_level":50}},"units":{"unit_of_length":"km"}}}"#),
            "/api/v1/globalsettings": (200, #"{"data":{"settings":{"unit_of_length":"km","unit_of_temperature":"C","preferred_range":"rated"}}}"#),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[{"drive_id":42,"distance":12.3},{"drive_id":43}]}}"#),
            "/api/v1/cars/1/drives/42": (200, #"{"data":{"drive":{"drive_id":42,"drive_details":[{"date":"2026-07-01T10:00:00+08:00","latitude":28.1,"longitude":112.9}]}}}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[{"charge_id":77,"charge_energy_added":18.5}]}}"#),
            "/api/v1/cars/1/charges/77": (200, #"{"data":{"charge":{"charge_id":77,"charge_details":[{"date":"2026-07-01T12:00:00+08:00","charge_energy_added":2.5}]}}}"#),
            "/api/v1/cars/1/environment-history": (200, #"{"data":{"series":[{"date_from":1782316800000,"outside_temp":28.5,"inside_temp":22,"tpms_pressure_fl":2.9,"tpms_pressure_fr":2.9,"tpms_pressure_rl":2.8,"tpms_pressure_rr":2.8,"sample_count":5}],"summary":{"point_count":1,"sample_count":5},"temperature_energy_buckets":[],"leak_observations":[]},"units":{"unit_of_temperature":"C","unit_of_pressure":"bar"}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#),
            "/api/v1/cars/1/updates": (200, #"{"data":{"updates":[{"update_id":9,"version":"2026.20.1"}]}}"#),
            "/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertFalse(report.hasFailure)
        XCTAssertTrue(report.hasWarning)
        XCTAssertEqual(report.checks.map(\.checkID), [.configuration, .cars, .vehicleInfo, .status, .settings, .drives, .driveDetail, .charges, .chargeDetail, .historyDataQuality, .environmentHistory, .batteryHealth, .softwareUpdates, .currentCharge])
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .vehicleInfo })?.message, "已识别 Model 3，外观颜色 PBSB，轮毂类型 W39B。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .driveDetail })?.status, .warning)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .driveDetail })?.message, "直接行程电耗字段缺失，现有 1 个位置点不足以可靠重建电耗。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .chargeDetail })?.message, "可以读取最新充电详情，包含 1 个采样点。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .historyDataQuality })?.message, "全部 2 条行程：0 条有直接电耗、0 条可重建、2 条不完整（已知影响 12.3 km；里程覆盖 1/2）。全部 1 条充电：0 条完整、0 条缺位置或地址、1 条缺核心采样。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .environmentHistory })?.status, .passed)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .environmentHistory })?.message, "近 30 天：1 个带时间数据点，来自 5 次采样；温度覆盖 1/1，胎压覆盖 1/1。")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .softwareUpdates })?.message, "可以读取软件更新记录 2026.20.1。")
    }

    func testDiagnosticWarnsWhenVehicleInfoCannotIdentifyDashboardModel() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"MateDrive"}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":{"battery_details":{"battery_level":50}},"units":{"unit_of_length":"km"}}}"#),
            "/api/v1/globalsettings": (200, #"{"data":{"settings":{"unit_of_length":"km","unit_of_temperature":"C","preferred_range":"rated"}}}"#),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[]}}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#),
            "/api/v1/cars/1/updates": (200, #"{"data":{"updates":[]}}"#),
            "/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        let vehicleInfo = report.checks.first(where: { $0.checkID == .vehicleInfo })
        XCTAssertEqual(vehicleInfo?.status, .warning)
        XCTAssertEqual(vehicleInfo?.title, "车辆信息")
        XCTAssertEqual(vehicleInfo?.message, "可以读取车辆列表，但车型和车辆名称缺失。首页可能会回退显示通用 Tesla。")
    }

    func testDiagnosticWarnsWhenStatusEndpointReturnsNoVehiclePayload() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"}}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":null,"units":{"unit_of_length":"km"}}}"#),
            "/api/v1/globalsettings": (200, #"{"data":{"settings":{"unit_of_length":"km","unit_of_temperature":"C","preferred_range":"rated"}}}"#),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[]}}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#),
            "/api/v1/cars/1/updates": (200, #"{"data":{"updates":[]}}"#),
            "/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertFalse(report.hasFailure)
        XCTAssertTrue(report.hasWarning)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .status })?.status, .warning)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .status })?.message, "状态接口可访问，但没有返回车辆状态数据。")
    }

    func testDiagnosticWarnsWhenGlobalSettingsPayloadIsMissingPreferences() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"}}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":{"battery_details":{"battery_level":50}},"units":{"unit_of_length":"km"}}}"#),
            "/api/v1/globalsettings": (200, #"{"data":{"settings":{}}}"#),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[]}}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#),
            "/api/v1/cars/1/updates": (200, #"{"data":{"updates":[]}}"#),
            "/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertFalse(report.hasFailure)
        XCTAssertTrue(report.hasWarning)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .settings })?.status, .warning)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .settings })?.message, "可以读取全局设置，但单位和续航偏好缺失。")
    }

    func testDiagnosticFailsWhenGlobalSettingsEndpointFails() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"}}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":{"battery_details":{"battery_level":50}},"units":{"unit_of_length":"km"}}}"#),
            "/api/v1/globalsettings": (500, #"{"error":"broken"}"#),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[]}}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#),
            "/api/v1/cars/1/updates": (200, #"{"data":{"updates":[]}}"#),
            "/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertTrue(report.hasFailure)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .settings })?.status, .failed)
        XCTAssertTrue(report.checks.first(where: { $0.checkID == .settings })?.message.contains("全局设置读取失败：HTTP 500") == true)
    }

    func testDiagnosticWarnsWhenBatteryHealthEndpointReturnsNoCoreValues() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"}}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":{"battery_details":{"battery_level":50}},"units":{"unit_of_length":"km"}}}"#),
            "/api/v1/globalsettings": (200, #"{"data":{"settings":{"unit_of_length":"km","unit_of_temperature":"C","preferred_range":"rated"}}}"#),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[]}}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{}}}"#),
            "/api/v1/cars/1/updates": (200, #"{"data":{"updates":[]}}"#),
            "/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertFalse(report.hasFailure)
        XCTAssertTrue(report.hasWarning)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .batteryHealth })?.status, .warning)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .batteryHealth })?.message, "电池健康接口可访问，但没有返回健康度、续航或容量数据。")
    }

    func testDiagnosticFailsWhenLatestDetailEndpointFails() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"}}]}}"#),
            "/api/v1/cars/1/status": (200, #"{"data":{"status":{"battery_details":{"battery_level":50}},"units":{"unit_of_length":"km"}}}"#),
            "/api/v1/globalsettings": (200, #"{"data":{"settings":{"unit_of_length":"km","unit_of_temperature":"C","preferred_range":"rated"}}}"#),
            "/api/v1/cars/1/drives": (200, #"{"data":{"drives":[{"drive_id":42,"distance":12.3}]}}"#),
            "/api/v1/cars/1/drives/42": (500, #"{"error":"broken"}"#),
            "/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#),
            "/api/v1/cars/1/updates": (200, #"{"data":{"updates":[]}}"#),
            "/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertTrue(report.hasFailure)
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .driveDetail })?.status, .failed)
        XCTAssertTrue(report.checks.first(where: { $0.checkID == .driveDetail })?.message.contains("最新行程详情失败：HTTP 500") == true)
    }

    func testDiagnosticReportsAuthFailureWithActionableMessage() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "/api/v1/cars": (401, #"{"error":"unauthorized"}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: "https://teslamate.example"),
            token: "bad-token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertTrue(report.hasFailure)
        XCTAssertEqual(report.checks.map(\.checkID), [.configuration, .cars])
        XCTAssertEqual(report.checks.last?.status, .failed)
        XCTAssertTrue(report.checks.last?.message.contains("请检查 API 令牌或基础认证") == true)
    }

    func testDiagnosticFallsBackToSecondaryServerWhenPrimaryVehicleListIsRetryableFailure() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "primary.example/api/v1/cars": (500, #"{"error":"offline"}"#),
            "backup.example/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"}}]}}"#),
            "backup.example/api/v1/cars/1/status": (200, #"{"data":{"status":{"battery_details":{"battery_level":50}},"units":{"unit_of_length":"km"}}}"#),
            "backup.example/api/v1/globalsettings": (200, #"{"data":{"settings":{"unit_of_length":"km","unit_of_temperature":"C","preferred_range":"rated"}}}"#),
            "backup.example/api/v1/cars/1/drives": (200, #"{"data":{"drives":[]}}"#),
            "backup.example/api/v1/cars/1/charges": (200, #"{"data":{"charges":[]}}"#),
            "backup.example/api/v1/cars/1/battery-health": (200, #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#),
            "backup.example/api/v1/cars/1/updates": (200, #"{"data":{"updates":[]}}"#),
            "backup.example/api/v1/cars/1/charges/current": (204, #"{}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(
                serverURL: "https://primary.example",
                secondaryServerURL: "https://backup.example"
            ),
            token: "token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertFalse(report.hasFailure)
        XCTAssertTrue(report.hasWarning)
        XCTAssertEqual(report.checks.first?.message, "正在使用 https://backup.example")
        XCTAssertEqual(report.checks.first(where: { $0.checkID == .cars })?.message, "找到 1 辆车。")
    }

    func testDiagnosticDoesNotFallbackToSecondaryServerForAuthenticationFailure() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [
            "primary.example/api/v1/cars": (401, #"{"error":"unauthorized"}"#),
            "backup.example/api/v1/cars": (200, #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3"}]}}"#)
        ]))

        let report = await diagnostic.run(
            settings: AppSettings(
                serverURL: "https://primary.example",
                secondaryServerURL: "https://backup.example"
            ),
            token: "bad-token",
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertTrue(report.hasFailure)
        XCTAssertEqual(report.checks.first?.message, "正在使用 https://primary.example")
        XCTAssertTrue(report.checks.last?.message.contains("HTTP 401") == true)
    }

    func testDiagnosticFailsFastForMissingServerURL() async {
        let diagnostic = TeslaMateConnectionDiagnostic(client: RouteHTTPClient(routes: [:]))

        let report = await diagnostic.run(
            settings: AppSettings(serverURL: " "),
            token: nil,
            basicAuth: nil,
            language: .chinese
        )

        XCTAssertTrue(report.hasFailure)
        XCTAssertEqual(report.checks, [
            TeslaMateDiagnosticCheck(
                checkID: .configuration,
                status: .failed,
                title: "服务器",
                message: "TeslaMate 服务器地址为空。"
            )
        ])
    }
}

private struct RouteHTTPClient: HTTPClient, @unchecked Sendable {
    let routes: [String: (statusCode: Int, json: String)]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let hostPath = "\(request.url?.host ?? "")\(request.url?.path ?? "")"
        let path = request.url?.path ?? ""
        let route = routes[hostPath] ?? routes[path] ?? (404, #"{"error":"not found"}"#)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://teslamate.example")!,
            statusCode: route.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(route.json.utf8), response)
    }
}
