import Foundation

public enum TeslaMateDiagnosticCheckID: String, CaseIterable, Sendable {
    case configuration
    case cars
    case vehicleInfo
    case status
    case settings
    case drives
    case driveDetail
    case charges
    case chargeDetail
    case historyDataQuality
    case environmentHistory
    case batteryHealth
    case softwareUpdates
    case currentCharge
}

public enum TeslaMateDiagnosticStatus: String, Sendable {
    case passed
    case warning
    case failed
}

public struct TeslaMateDiagnosticCheck: Equatable, Sendable, Identifiable {
    public var id: TeslaMateDiagnosticCheckID { checkID }
    public let checkID: TeslaMateDiagnosticCheckID
    public let status: TeslaMateDiagnosticStatus
    public let title: String
    public let message: String

    public init(checkID: TeslaMateDiagnosticCheckID, status: TeslaMateDiagnosticStatus, title: String, message: String) {
        self.checkID = checkID
        self.status = status
        self.title = title
        self.message = message
    }
}

public struct TeslaMateDiagnosticReport: Equatable, Sendable {
    public let checks: [TeslaMateDiagnosticCheck]
    public let serverProfile: TeslaMateServerProfile?

    public init(checks: [TeslaMateDiagnosticCheck], serverProfile: TeslaMateServerProfile? = nil) {
        self.checks = checks
        self.serverProfile = serverProfile
    }

    public var hasFailure: Bool {
        checks.contains { $0.status == .failed }
    }

    public var hasWarning: Bool {
        checks.contains { $0.status == .warning }
    }

    public func summary(language: AppLanguage) -> String {
        let passedCount = checks.filter { $0.status == .passed }.count
        if hasFailure {
            return localized(
                "Connection test failed: \(passedCount)/\(checks.count) checks passed",
                "连接测试失败：\(passedCount)/\(checks.count) 项通过",
                language: language
            )
        }
        if hasWarning {
            return localized(
                "Connection test completed with warnings",
                "连接测试完成，但有警告",
                language: language
            )
        }
        return localized(
            "Connection test passed: TeslaMate data is readable",
            "连接测试通过：可以读取 TeslaMate 数据",
            language: language
        )
    }
}

public protocol TeslaMateConnectionDiagnosing: Sendable {
    func run(settings: AppSettings, authenticator: RequestAuthenticator, language: AppLanguage) async -> TeslaMateDiagnosticReport
}

public extension TeslaMateConnectionDiagnosing {
    func run(settings: AppSettings, token: String?, basicAuth: BasicAuth?, language: AppLanguage) async -> TeslaMateDiagnosticReport {
        await run(
            settings: settings,
            authenticator: RequestAuthenticator(bearerToken: token, basicAuth: basicAuth),
            language: language
        )
    }
}

public struct TeslaMateConnectionDiagnostic: TeslaMateConnectionDiagnosing {
    private let clientOverride: (any HTTPClient)?
    private let capabilityDiscovery: any TeslaMateCapabilityDiscovering

    public init(
        client: (any HTTPClient)? = nil,
        capabilityDiscovery: any TeslaMateCapabilityDiscovering = TeslaMateCapabilityService()
    ) {
        self.clientOverride = client
        self.capabilityDiscovery = capabilityDiscovery
    }

    public func run(settings: AppSettings, authenticator: RequestAuthenticator, language: AppLanguage) async -> TeslaMateDiagnosticReport {
        let client = clientOverride ?? URLSessionHTTPClient(acceptsInvalidCertificates: settings.acceptInvalidCerts)
        let serverURLs = [settings.serverURL, settings.secondaryServerURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !serverURLs.isEmpty else {
            let checks: [TeslaMateDiagnosticCheck] = [
                .failed(.configuration, "Server", "服务器", "TeslaMate server URL is empty.", "TeslaMate 服务器地址为空。", language: language)
            ]
            return TeslaMateDiagnosticReport(checks: checks)
        }

        var seenURLs: Set<String> = []
        var lastReport: TeslaMateDiagnosticReport?
        var selectedAPI: TeslamateAPI?
        var selectedCars: [CarData]?
        var checks: [TeslaMateDiagnosticCheck] = []

        for serverURL in serverURLs where seenURLs.insert(serverURL).inserted {
            guard let baseURL = URL(string: serverURL), baseURL.scheme != nil, baseURL.host != nil else {
                let report = TeslaMateDiagnosticReport(checks: [
                    .failed(.configuration, "Server", "服务器", "Invalid TeslaMate server URL: \(serverURL)", "TeslaMate 服务器地址无效：\(serverURL)", language: language)
                ])
                lastReport = report
                continue
            }

            var candidateChecks: [TeslaMateDiagnosticCheck] = [
                .passed(.configuration, "Server", "服务器", "Using \(baseURL.absoluteString)", "正在使用 \(baseURL.absoluteString)", language: language)
            ]
            let api = TeslamateAPI(baseURL: baseURL, authenticator: authenticator, client: client)
            switch await api.cars() {
            case let .success(value) where value.isEmpty:
                candidateChecks.append(.failed(.cars, "Vehicles", "车辆", "TeslaMate returned no vehicles.", "TeslaMate 没有返回车辆。", language: language))
                return TeslaMateDiagnosticReport(checks: candidateChecks)
            case let .success(value):
                selectedCars = value
                selectedAPI = api
                checks = candidateChecks
                checks.append(.passed(.cars, "Vehicles", "车辆", "Found \(value.count) vehicle(s).", "找到 \(value.count) 辆车。", language: language))
                checks.append(vehicleInfoCheck(for: value[0], language: language))
                break
            case let .failure(error):
                candidateChecks.append(.failed(.cars, "Vehicles", "车辆", "Vehicle list failed: \(message(for: error, language: .english))", "车辆列表失败：\(message(for: error, language: .chinese))", language: language))
                let report = TeslaMateDiagnosticReport(checks: candidateChecks)
                lastReport = report
                guard Self.shouldRetryWithSecondary(after: error) else {
                    return report
                }
            }

            if selectedAPI != nil {
                break
            }
        }

        guard let api = selectedAPI, let cars = selectedCars else {
            return lastReport ?? TeslaMateDiagnosticReport(checks: [
                .failed(.configuration, "Server", "服务器", "TeslaMate server URL is empty.", "TeslaMate 服务器地址为空。", language: language)
            ])
        }

        let car = settings.lastSelectedCarId.flatMap { selectedID in
            cars.first(where: { $0.carId == selectedID })
        } ?? cars[0]
        switch await api.carStatus(carId: car.carId) {
        case let .success(payload):
            checks.append(statusCheck(for: payload, language: language))
        case let .failure(error):
            checks.append(.failed(.status, "Status", "状态", "Vehicle status failed: \(message(for: error, language: .english))", "车辆状态失败：\(message(for: error, language: .chinese))", language: language))
        }

        switch await api.globalSettings() {
        case let .success(settings):
            checks.append(settingsCheck(for: settings, language: language))
        case let .failure(error):
            checks.append(.failed(.settings, "Settings", "设置", "Global settings failed: \(message(for: error, language: .english))", "全局设置读取失败：\(message(for: error, language: .chinese))", language: language))
        }

        let latestDrive: DriveData?
        switch await api.drives(carId: car.carId, page: 1, show: 1) {
        case let .success(value) where value.isEmpty:
            latestDrive = nil
            checks.append(.warning(.drives, "Drives", "行程", "No drive records returned yet.", "暂未返回行程记录。", language: language))
        case let .success(value):
            latestDrive = value.first
            checks.append(.passed(.drives, "Drives", "行程", "Drive records are readable.", "可以读取行程记录。", language: language))
        case let .failure(error):
            latestDrive = nil
            checks.append(.failed(.drives, "Drives", "行程", "Drive records failed: \(message(for: error, language: .english))", "行程记录失败：\(message(for: error, language: .chinese))", language: language))
        }

        if let latestDrive {
            if let driveId = latestDrive.driveId {
                switch await api.driveDetail(carId: car.carId, driveId: driveId) {
                case let .success(detail):
                    let positionCount = detail.positions?.count ?? 0
                    let hasDirectEnergy = detail.usableEnergyConsumedNet != nil || detail.usableConsumptionNet != nil
                    let estimate = DriveStatsCalculator.estimateEnergy(from: detail.positions ?? [])
                    if hasDirectEnergy {
                        checks.append(.passed(
                            .driveDetail,
                            "Drive detail",
                            "行程详情",
                            "Latest drive detail is readable with \(positionCount) position point(s) and direct energy fields.",
                            "可以读取最新行程详情，包含 \(positionCount) 个位置点和直接电耗字段。",
                            language: language
                        ))
                    } else if let estimate, estimate.isReliable {
                        let coverage = Int((estimate.coverage * 100).rounded())
                        checks.append(.warning(
                            .driveDetail,
                            "Drive detail",
                            "行程详情",
                            "Direct drive energy fields are missing; MateDrive can reconstruct net energy from \(positionCount) power samples with \(coverage)% coverage.",
                            "直接行程电耗字段缺失；MateDrive 可用 \(positionCount) 个功率采样重建净电耗，覆盖率 \(coverage)%。",
                            language: language
                        ))
                    } else {
                        checks.append(.warning(
                            .driveDetail,
                            "Drive detail",
                            "行程详情",
                            "Direct drive energy fields are missing and \(positionCount) position point(s) are insufficient for a reliable reconstruction.",
                            "直接行程电耗字段缺失，现有 \(positionCount) 个位置点不足以可靠重建电耗。",
                            language: language
                        ))
                    }
                case let .failure(error):
                    checks.append(.failed(.driveDetail, "Drive detail", "行程详情", "Latest drive detail failed: \(message(for: error, language: .english))", "最新行程详情失败：\(message(for: error, language: .chinese))", language: language))
                }
            } else {
                checks.append(.failed(.driveDetail, "Drive detail", "行程详情", "Latest drive record is missing drive_id.", "最新行程记录缺少 drive_id。", language: language))
            }
        }

        let latestCharge: ChargeData?
        switch await api.charges(carId: car.carId, page: 1, show: 1) {
        case let .success(value) where value.isEmpty:
            latestCharge = nil
            checks.append(.warning(.charges, "Charges", "充电", "No charge records returned yet.", "暂未返回充电记录。", language: language))
        case let .success(value):
            latestCharge = value.first
            checks.append(.passed(.charges, "Charges", "充电", "Charge records are readable.", "可以读取充电记录。", language: language))
        case let .failure(error):
            latestCharge = nil
            checks.append(.failed(.charges, "Charges", "充电", "Charge records failed: \(message(for: error, language: .english))", "充电记录失败：\(message(for: error, language: .chinese))", language: language))
        }

        if let latestCharge {
            if let chargeId = latestCharge.chargeId {
                switch await api.chargeDetail(carId: car.carId, chargeId: chargeId) {
                case let .success(detail):
                    let pointCount = detail.chargePoints?.count ?? 0
                    let englishMessage = pointCount > 0 ? "Latest charge detail is readable with \(pointCount) sample point(s)." : "Latest charge detail is readable, but has no charging samples."
                    let chineseMessage = pointCount > 0 ? "可以读取最新充电详情，包含 \(pointCount) 个采样点。" : "可以读取最新充电详情，但没有充电采样点。"
                    checks.append(pointCount > 0
                        ? .passed(.chargeDetail, "Charge detail", "充电详情", englishMessage, chineseMessage, language: language)
                        : .warning(.chargeDetail, "Charge detail", "充电详情", englishMessage, chineseMessage, language: language))
                case let .failure(error):
                    checks.append(.failed(.chargeDetail, "Charge detail", "充电详情", "Latest charge detail failed: \(message(for: error, language: .english))", "最新充电详情失败：\(message(for: error, language: .chinese))", language: language))
                }
            } else {
                checks.append(.failed(.chargeDetail, "Charge detail", "充电详情", "Latest charge record is missing charge_id.", "最新充电记录缺少 charge_id。", language: language))
            }
        }

        checks.append(await historyDataQualityCheck(api: api, carId: car.carId, language: language))
        checks.append(await environmentHistoryCheck(api: api, carId: car.carId, language: language))

        switch await api.batteryHealth(carId: car.carId) {
        case let .success(health):
            checks.append(batteryHealthCheck(for: health, language: language))
        case let .failure(error):
            checks.append(.warning(.batteryHealth, "Battery health", "电池健康", "Battery health failed: \(message(for: error, language: .english))", "电池健康读取失败：\(message(for: error, language: .chinese))", language: language))
        }

        switch await api.updates(carId: car.carId, page: 1, show: 1) {
        case let .success(updates):
            checks.append(softwareUpdatesCheck(for: updates, language: language))
        case let .failure(error):
            checks.append(.failed(.softwareUpdates, "Software updates", "软件更新", "Software updates failed: \(message(for: error, language: .english))", "软件更新读取失败：\(message(for: error, language: .chinese))", language: language))
        }

        switch await api.currentCharge(carId: car.carId) {
        case let .success(outcome):
            checks.append(currentChargeCheck(for: outcome, language: language))
        case let .failure(error):
            checks.append(.failed(.currentCharge, "Current charge", "当前充电", "Current charge failed: \(message(for: error, language: .english))", "当前充电读取失败：\(message(for: error, language: .chinese))", language: language))
        }

        let profile = await capabilityDiscovery.discover(api: api, carId: car.carId, force: true)
        return TeslaMateDiagnosticReport(checks: checks, serverProfile: profile)
    }

    private static func shouldRetryWithSecondary(after error: APIError) -> Bool {
        switch error {
        case .serverNotConfigured, .invalidURL, .sslCertificate, .network, .invalidResponse, .emptyBody:
            return true
        case let .httpStatus(status):
            return status >= 500 || status == 408 || status == 429
        }
    }

    private func statusCheck(for payload: CarStatusPayload, language: AppLanguage) -> TeslaMateDiagnosticCheck {
        guard let status = payload.status else {
            return .warning(
                .status,
                "Status",
                "状态",
                "Status endpoint is reachable, but returned no vehicle status payload.",
                "状态接口可访问，但没有返回车辆状态数据。",
                language: language
            )
        }

        let hasVehicleFields = status.displayName != nil ||
            status.batteryLevel != nil ||
            status.locked != nil ||
            status.sentryMode != nil ||
            status.outsideTemp != nil ||
            status.insideTemp != nil ||
            status.chargingDetails != nil
        let hasUnits = payload.units?.unitOfLength != nil ||
            payload.units?.unitOfTemperature != nil ||
            payload.units?.unitOfPressure != nil

        if !hasVehicleFields {
            return .warning(
                .status,
                "Status",
                "状态",
                "Status endpoint is reachable, but key vehicle fields are missing.",
                "状态接口可访问，但关键车辆字段缺失。",
                language: language
            )
        }
        if !hasUnits {
            return .warning(
                .status,
                "Status",
                "状态",
                "Current vehicle status is readable, but unit preferences are missing.",
                "可以读取当前车辆状态，但单位偏好缺失。",
                language: language
            )
        }

        return .passed(.status, "Status", "状态", "Current vehicle status is readable.", "可以读取当前车辆状态。", language: language)
    }

    private func vehicleInfoCheck(for car: CarData, language: AppLanguage) -> TeslaMateDiagnosticCheck {
        let modelName = car.vehicleModelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasModel = modelName?.isEmpty == false
        let hasUsableName = !CarData.isLegacyAppDisplayName(car.name) &&
            !CarData.isLegacyAppDisplayName(car.displayName) &&
            car.displayName.trimmingCharacters(in: .whitespacesAndNewlines) != "Tesla"
        let hasExteriorColor = car.carExterior?.exteriorColor?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasWheelType = car.carExterior?.wheelType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        if !hasModel && !hasUsableName {
            return .warning(
                .vehicleInfo,
                "Vehicle info",
                "车辆信息",
                "Vehicle list is readable, but model and vehicle name are missing. The dashboard may fall back to a generic Tesla.",
                "可以读取车辆列表，但车型和车辆名称缺失。首页可能会回退显示通用 Tesla。",
                language: language
            )
        }

        if !hasModel {
            return .warning(
                .vehicleInfo,
                "Vehicle info",
                "车辆信息",
                "Vehicle name is readable, but model is missing. The dashboard image may use a generic Tesla.",
                "可以读取车辆名称，但车型缺失。首页车辆图片可能会使用通用 Tesla。",
                language: language
            )
        }

        if !hasExteriorColor || !hasWheelType {
            let englishModel = modelName ?? "Tesla"
            let chineseModel = englishModel
            return .warning(
                .vehicleInfo,
                "Vehicle info",
                "车辆信息",
                "Vehicle model \(englishModel) is readable, but exterior color or wheel type is missing. The dashboard image may use default options.",
                "可以识别车型 \(chineseModel)，但外观颜色或轮毂类型缺失。首页车辆图片可能会使用默认配置。",
                language: language
            )
        }

        let displayModel = car.vehicleModelDescription ?? modelName ?? car.displayName
        let color = car.carExterior?.exteriorColor ?? "unknown"
        let wheel = car.carExterior?.wheelType ?? "unknown"
        return .passed(
            .vehicleInfo,
            "Vehicle info",
            "车辆信息",
            "Identified \(displayModel), exterior color \(color), and wheel type \(wheel).",
            "已识别 \(displayModel)，外观颜色 \(color)，轮毂类型 \(wheel)。",
            language: language
        )
    }

    private func settingsCheck(for settings: GlobalSettingsData?, language: AppLanguage) -> TeslaMateDiagnosticCheck {
        guard let settings else {
            return .warning(
                .settings,
                "Settings",
                "设置",
                "Global settings endpoint is reachable, but returned no settings payload.",
                "全局设置接口可访问，但没有返回设置数据。",
                language: language
            )
        }

        let hasUnitPreferences = settings.unitOfLength != nil ||
            settings.unitOfTemperature != nil ||
            settings.unitOfPressure != nil
        let hasRangePreference = settings.preferredRange != nil

        if !hasUnitPreferences && !hasRangePreference {
            return .warning(
                .settings,
                "Settings",
                "设置",
                "Global settings are readable, but unit and range preferences are missing.",
                "可以读取全局设置，但单位和续航偏好缺失。",
                language: language
            )
        }

        return .passed(.settings, "Settings", "设置", "Global settings are readable.", "可以读取全局设置。", language: language)
    }

    private func batteryHealthCheck(for health: BatteryHealth, language: AppLanguage) -> TeslaMateDiagnosticCheck {
        let hasHealthValue = health.batteryHealthPercentage != nil ||
            health.currentRange != nil ||
            health.maxRange != nil ||
            health.currentCapacity != nil ||
            health.maxCapacity != nil
        guard hasHealthValue else {
            return .warning(
                .batteryHealth,
                "Battery health",
                "电池健康",
                "Battery health endpoint is reachable, but did not return health, range, or capacity values.",
                "电池健康接口可访问，但没有返回健康度、续航或容量数据。",
                language: language
            )
        }

        let missingCoreValues = health.batteryHealthPercentage == nil && health.currentRange == nil
        if missingCoreValues {
            return .warning(
                .batteryHealth,
                "Battery health",
                "电池健康",
                "Battery health endpoint is readable, but health percentage and current range are both missing.",
                "可以读取电池健康接口，但健康度和当前续航都缺失。",
                language: language
            )
        }

        return .passed(.batteryHealth, "Battery health", "电池健康", "Battery health endpoint is readable.", "可以读取电池健康接口。", language: language)
    }

    private func historyDataQualityCheck(api: TeslamateAPI, carId: Int, language: AppLanguage) async -> TeslaMateDiagnosticCheck {
        async let drivesResult = api.drives(carId: carId, page: 1, show: 50_000)
        async let chargesResult = api.charges(carId: carId, page: 1, show: 50_000)
        let (resolvedDrives, resolvedCharges) = await (drivesResult, chargesResult)

        guard case let .success(drives) = resolvedDrives,
              case let .success(charges) = resolvedCharges
        else {
            return .warning(
                .historyDataQuality,
                "History data quality",
                "历史数据质量",
                "Could not read complete drive and charge history for completeness analysis.",
                "无法读取完整行程和充电历史进行完整性分析。",
                language: language
            )
        }

        let driveResults = await evaluateInBatches(drives, batchSize: 8) { drive in
            let distance = drive.distance
            guard let driveId = drive.driveId,
                  let distance,
                  distance > 0,
                  drive.startDate != nil,
                  drive.endDate != nil
            else { return DriveQualityResult(quality: .incomplete, distance: distance.map { max($0, 0) }) }
            if drive.usableEnergyConsumedNet != nil || drive.usableConsumptionNet != nil {
                return DriveQualityResult(quality: .direct, distance: distance)
            }
            guard case let .success(detail) = await api.driveDetail(carId: carId, driveId: driveId),
                  DriveStatsCalculator.estimateEnergy(from: detail.positions ?? [])?.isReliable == true
            else { return DriveQualityResult(quality: .incomplete, distance: distance) }
            return DriveQualityResult(quality: .reconstructable, distance: distance)
        }

        let chargeResults = await evaluateInBatches(charges, batchSize: 8) { charge in
            guard let chargeId = charge.chargeId,
                  (charge.chargeEnergyAdded ?? 0) > 0,
                  charge.startDate != nil,
                  charge.endDate != nil,
                  case let .success(detail) = await api.chargeDetail(carId: carId, chargeId: chargeId),
                  detail.chargePoints?.isEmpty == false
            else { return ChargeQuality.incomplete }
            let hasAddress = charge.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasLocation = GeoCoordinateValidator.location(latitude: detail.latitude, longitude: detail.longitude) != nil
            return hasAddress && hasLocation ? .complete : .missingMetadata
        }

        let direct = driveResults.filter { $0.quality == .direct }.count
        let reconstructable = driveResults.filter { $0.quality == .reconstructable }.count
        let incompleteDrives = driveResults.filter { $0.quality == .incomplete }
        let knownAffectedDistances = incompleteDrives.compactMap(\.distance)
        let affectedDistance = knownAffectedDistances.reduce(0, +)
        let completeCharges = chargeResults.filter { $0 == .complete }.count
        let metadataMissingCharges = chargeResults.filter { $0 == .missingMetadata }.count
        let incompleteCharges = chargeResults.filter { $0 == .incomplete }.count
        let distanceText = String(format: "%.1f", affectedDistance)
        let englishDistance: String
        let chineseDistance: String
        if knownAffectedDistances.count == incompleteDrives.count {
            englishDistance = "\(distanceText) km affected"
            chineseDistance = "影响 \(distanceText) km"
        } else {
            englishDistance = "\(distanceText) km known affected; distance coverage \(knownAffectedDistances.count)/\(incompleteDrives.count)"
            chineseDistance = "已知影响 \(distanceText) km；里程覆盖 \(knownAffectedDistances.count)/\(incompleteDrives.count)"
        }
        let english = "All \(drives.count) drives: \(direct) direct energy, \(reconstructable) reconstructable, \(incompleteDrives.count) incomplete (\(englishDistance)). All \(charges.count) charges: \(completeCharges) complete, \(metadataMissingCharges) missing location/address, \(incompleteCharges) missing core samples."
        let chinese = "全部 \(drives.count) 条行程：\(direct) 条有直接电耗、\(reconstructable) 条可重建、\(incompleteDrives.count) 条不完整（\(chineseDistance)）。全部 \(charges.count) 条充电：\(completeCharges) 条完整、\(metadataMissingCharges) 条缺位置或地址、\(incompleteCharges) 条缺核心采样。"

        if drives.isEmpty && charges.isEmpty {
            return .warning(.historyDataQuality, "History data quality", "历史数据质量", "No history records are available for completeness analysis.", "暂无历史记录可用于完整性分析。", language: language)
        }
        if !incompleteDrives.isEmpty || incompleteCharges > 0 || metadataMissingCharges > 0 || reconstructable > 0 {
            return .warning(.historyDataQuality, "History data quality", "历史数据质量", english, chinese, language: language)
        }
        return .passed(.historyDataQuality, "History data quality", "历史数据质量", english, chinese, language: language)
    }

    private func environmentHistoryCheck(api: TeslamateAPI, carId: Int, language: AppLanguage) async -> TeslaMateDiagnosticCheck {
        switch await api.environmentHistory(carId: carId, range: "30d", grain: "day") {
        case let .failure(error):
            return .warning(
                .environmentHistory,
                "Environment samples",
                "环境采样",
                "Environment history could not be verified: \(message(for: error, language: .english))",
                "无法验证环境历史：\(message(for: error, language: .chinese))",
                language: language
            )
        case let .success(response):
            let points = response.data.series.filter { $0.timestamp != nil }
            let temperaturePoints = points.filter { $0.outsideTemp != nil || $0.insideTemp != nil }.count
            let pressurePoints = points.filter {
                $0.tpmsPressureFl != nil || $0.tpmsPressureFr != nil || $0.tpmsPressureRl != nil || $0.tpmsPressureRr != nil
            }.count
            let sampleCount = response.data.summary?.sampleCount ?? points.compactMap(\.sampleCount).reduce(0, +)
            let english = "Last 30 days: \(points.count) dated points from \(sampleCount) samples; temperature coverage \(temperaturePoints)/\(points.count), tire pressure coverage \(pressurePoints)/\(points.count)."
            let chinese = "近 30 天：\(points.count) 个带时间数据点，来自 \(sampleCount) 次采样；温度覆盖 \(temperaturePoints)/\(points.count)，胎压覆盖 \(pressurePoints)/\(points.count)。"

            guard !points.isEmpty, sampleCount > 0 else {
                return .warning(.environmentHistory, "Environment samples", "环境采样", "The endpoint is readable, but no dated environment samples were returned for the last 30 days.", "接口可以读取，但近 30 天没有返回带时间的环境采样。", language: language)
            }
            if temperaturePoints < points.count || pressurePoints < points.count {
                return .warning(.environmentHistory, "Environment samples", "环境采样", english, chinese, language: language)
            }
            return .passed(.environmentHistory, "Environment samples", "环境采样", english, chinese, language: language)
        }
    }

    private enum DriveQuality: Equatable, Sendable {
        case direct
        case reconstructable
        case incomplete
    }

    private struct DriveQualityResult: Sendable {
        let quality: DriveQuality
        let distance: Double?
    }

    private enum ChargeQuality: Sendable {
        case complete
        case missingMetadata
        case incomplete
    }

    private func evaluateInBatches<Input: Sendable, Output: Sendable>(
        _ values: [Input],
        batchSize: Int,
        operation: @escaping @Sendable (Input) async -> Output
    ) async -> [Output] {
        var results: [Output] = []
        for offset in stride(from: 0, to: values.count, by: batchSize) {
            let batch = values[offset..<min(offset + batchSize, values.count)]
            let batchResults = await withTaskGroup(of: Output.self, returning: [Output].self) { group in
                for value in batch {
                    group.addTask { await operation(value) }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }
            results.append(contentsOf: batchResults)
        }
        return results
    }

    private func softwareUpdatesCheck(for updates: [UpdateData], language: AppLanguage) -> TeslaMateDiagnosticCheck {
        guard let latest = updates.first else {
            return .warning(
                .softwareUpdates,
                "Software updates",
                "软件更新",
                "Software updates endpoint is readable, but no update records were returned.",
                "软件更新接口可访问，但暂未返回更新记录。",
                language: language
            )
        }

        let versionText = latest.version.map { " \($0)" } ?? ""
        return .passed(
            .softwareUpdates,
            "Software updates",
            "软件更新",
            "Software updates are readable\(versionText).",
            "可以读取软件更新记录\(versionText)。",
            language: language
        )
    }

    private func currentChargeCheck(for outcome: CurrentChargeOutcome, language: AppLanguage) -> TeslaMateDiagnosticCheck {
        switch outcome {
        case .active:
            return .passed(
                .currentCharge,
                "Current charge",
                "当前充电",
                "Current charge endpoint is readable and returned an active charge.",
                "当前充电接口可访问，并返回了进行中的充电。",
                language: language
            )
        case .noActiveCharge:
            return .passed(
                .currentCharge,
                "Current charge",
                "当前充电",
                "Current charge endpoint is readable; no active charge is in progress.",
                "当前充电接口可访问；当前没有进行中的充电。",
                language: language
            )
        }
    }

    private func message(for error: APIError, language: AppLanguage) -> String {
        switch error {
        case .serverNotConfigured:
            return localized("Server is not configured.", "服务器未配置。", language: language)
        case let .invalidURL(url):
            return localized("Invalid URL: \(url)", "地址无效：\(url)", language: language)
        case let .httpStatus(status):
            if status == 401 || status == 403 {
                return localized("HTTP \(status), check API token or Basic Auth.", "HTTP \(status)，请检查 API 令牌或基础认证。", language: language)
            }
            return localized("HTTP \(status)", "HTTP \(status)", language: language)
        case let .sslCertificate(message):
            return localized("SSL certificate error: \(message)", "SSL 证书错误：\(message)", language: language)
        case let .invalidResponse(message):
            return localized("Invalid response: \(message)", "响应无效：\(message)", language: language)
        case let .network(message):
            return localized("Network error: \(message)", "网络错误：\(message)", language: language)
        case .emptyBody:
            return localized("Empty response.", "响应为空。", language: language)
        }
    }
}

private extension TeslaMateDiagnosticCheck {
    static func passed(_ id: TeslaMateDiagnosticCheckID, _ englishTitle: String, _ chineseTitle: String, _ englishMessage: String, _ chineseMessage: String, language: AppLanguage) -> Self {
        .init(checkID: id, status: .passed, title: localized(englishTitle, chineseTitle, language: language), message: localized(englishMessage, chineseMessage, language: language))
    }

    static func warning(_ id: TeslaMateDiagnosticCheckID, _ englishTitle: String, _ chineseTitle: String, _ englishMessage: String, _ chineseMessage: String, language: AppLanguage) -> Self {
        .init(checkID: id, status: .warning, title: localized(englishTitle, chineseTitle, language: language), message: localized(englishMessage, chineseMessage, language: language))
    }

    static func failed(_ id: TeslaMateDiagnosticCheckID, _ englishTitle: String, _ chineseTitle: String, _ englishMessage: String, _ chineseMessage: String, language: AppLanguage) -> Self {
        .init(checkID: id, status: .failed, title: localized(englishTitle, chineseTitle, language: language), message: localized(englishMessage, chineseMessage, language: language))
    }
}

private func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
    AppText.localized(english, chinese, language: language)
}
