import SwiftUI
import UniformTypeIdentifiers

@MainActor
public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel

    @State private var serverURL: String
    @State private var secondaryServerURL: String
    @State private var apiToken = ""
    @State private var basicUsername = ""
    @State private var basicPassword = ""
    @State private var cloudflareClientID = ""
    @State private var cloudflareClientSecret = ""
    @State private var apiAccessKey = ""
    @State private var apiSecretKey = ""
    @State private var acceptInvalidCerts: Bool
    @State private var currencyCode: String
    @State private var displayUnitSystem: DisplayUnitSystem
    @State private var appLanguage: AppLanguage
    @State private var batteryReferenceRangeKm: String
    @State private var batteryReferenceCapacityKWh: String
    @State private var batteryRecordingStartOdometerKm: String
    @State private var diagnosticExportDocument: DiagnosticTextDocument?
    @State private var diagnosticExportFilename = "MateDrive-Diagnostics"
    @State private var exportsDiagnostics = false
    @State private var diagnosticExportError: String?

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _serverURL = State(initialValue: viewModel.settings.serverURL)
        _secondaryServerURL = State(initialValue: viewModel.settings.secondaryServerURL)
        _acceptInvalidCerts = State(initialValue: viewModel.settings.acceptInvalidCerts)
        _currencyCode = State(initialValue: viewModel.settings.currencyCode)
        _displayUnitSystem = State(initialValue: viewModel.settings.displayUnitSystem)
        _appLanguage = State(initialValue: viewModel.settings.appLanguage)
        _batteryReferenceRangeKm = State(initialValue: Self.referenceRangeText(viewModel.settings.batteryReferenceRangeKm))
        let calibration = viewModel.settings.lastSelectedCarId.map { viewModel.settings.batteryCalibration(for: $0) }
        _batteryReferenceCapacityKWh = State(initialValue: Self.numberText(calibration?.referenceCapacityKWh))
        _batteryRecordingStartOdometerKm = State(initialValue: Self.numberText(viewModel.settings.batteryRecordingStartOdometerKm))
    }

    public var body: some View {
        Form {
            Section(t("Server", "服务器")) {
                TextField(t("Server URL", "服务器地址"), text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                TextField(t("Secondary Server URL", "备用服务器地址"), text: $secondaryServerURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                Toggle(t("Accept Invalid Certificates", "允许无效证书"), isOn: $acceptInvalidCerts)
            }

            Section(t("Authentication", "认证")) {
                SecureField(t("API Token", "API 令牌"), text: $apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(t("Basic Username", "基础认证用户名"), text: $basicUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(t("Basic Password", "基础认证密码"), text: $basicPassword)
                SecureField(t("Cloudflare Access Client ID", "Cloudflare 访问客户端标识"), text: $cloudflareClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(t("Cloudflare Access Client Secret", "Cloudflare 访问客户端密钥"), text: $cloudflareClientSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(t("MyTesS API Access Key", "接口访问密钥"), text: $apiAccessKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(t("MyTesS API Secret Key", "接口签名密钥"), text: $apiSecretKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(t("AK/SK authentication requires MyTesS API 2.5 or later.", "密钥签名认证需要接口版本 2.5 或更高版本。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(t("Leave secret fields blank to keep saved credentials.", "密钥字段留空会保留已保存的凭据。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(t("Connection Test", "连接测试")) {
                Button {
                    Task {
                        await viewModel.testConnection(
                            serverURL: serverURL,
                            secondaryServerURL: secondaryServerURL,
                            acceptInvalidCerts: acceptInvalidCerts,
                            apiToken: apiToken,
                            basicUsername: basicUsername,
                            basicPassword: basicPassword,
                            cloudflareClientID: cloudflareClientID,
                            cloudflareClientSecret: cloudflareClientSecret,
                            apiAccessKey: apiAccessKey,
                            apiSecretKey: apiSecretKey
                        )
                    }
                } label: {
                    Label(viewModel.isTestingConnection ? t("Testing Connection", "正在测试连接") : t("Test Connection", "测试连接"), systemImage: "network")
                }
                .disabled(viewModel.isTestingConnection || viewModel.isSaving)

                if let report = viewModel.connectionReport {
                    Text(verbatim: report.summary(language: appLanguage))
                        .font(.footnote.weight(.semibold))
                    ForEach(report.checks) { check in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: diagnosticIcon(check.status))
                                .foregroundStyle(diagnosticColor(check.status))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: check.title)
                                Text(verbatim: check.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let profile = report.serverProfile {
                        LabeledContent(t("Server Version", "服务器版本")) {
                            Text(verbatim: profile.version.displayVersion)
                        }
                        versionCompatibility(profile.version)
                        Text(t("API Capabilities", "API 能力"))
                            .font(.footnote.weight(.semibold))
                        ForEach(TeslaMateCapabilityPresentation.visibleCapabilities, id: \.self) { capability in
                            if let status = profile.status(for: capability) {
                                HStack(spacing: 10) {
                                    Image(systemName: TeslaMateCapabilityPresentation.icon(for: status.state))
                                        .foregroundStyle(capabilityColor(status.state))
                                    Text(localizedCapabilityTitle(capability))
                                    Spacer()
                                    Text(localizedCapabilityState(status.state))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(profile.checkedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        exportDiagnostics(report)
                    } label: {
                        Label(t("Export Diagnostics", "导出诊断报告"), systemImage: "square.and.arrow.up")
                    }
                    Text(t(
                        "The report excludes server addresses, credentials, vehicle identifiers, and coordinates.",
                        "报告不会包含服务器地址、认证凭据、车辆标识或坐标。"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section(t("Geography Data Quality", "地理数据质量")) {
                if let health = viewModel.geographyCacheHealth {
                    LabeledContent(t("Cached Locations", "已缓存位置"), value: "\(health.cachedLocationCount)")
                    LabeledContent(t("Pending Locations", "待处理位置"), value: "\(health.pendingLocationCount)")
                    if let updatedAt = health.lastUpdatedAt {
                        LabeledContent(t("Last Updated", "最后更新")) {
                            Text(geographyDate(updatedAt))
                        }
                    }
                    Label(
                        health.pendingLocationCount > 0
                            ? t("Some synchronized locations are waiting for geography completion.", "部分同步位置仍在等待地理信息补全。")
                            : t("Geography cache is ready.", "地理信息缓存状态正常。"),
                        systemImage: health.pendingLocationCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(health.pendingLocationCount > 0 ? .orange : .green)
                    if health.pendingLocationCount > 0 {
                        Button {
                            Task { await viewModel.processPendingGeography() }
                        } label: {
                            Label(
                                viewModel.isProcessingGeographyQueue ? t("Processing Locations", "正在处理位置") : t("Process Pending Locations", "处理待补全位置"),
                                systemImage: "location.magnifyingglass"
                            )
                        }
                        .disabled(viewModel.isProcessingGeographyQueue)
                    }
                    if let report = viewModel.geographyProcessingReport {
                        Text(geographyProcessingText(report))
                            .font(.caption)
                            .foregroundStyle(report.failedCount > 0 ? .orange : .secondary)
                    }
                } else if let error = viewModel.geographyHealthError {
                    Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    ProgressView(t("Checking geography cache", "正在检查地理信息缓存"))
                }
                Button {
                    Task { await viewModel.refreshGeographyHealth() }
                } label: {
                    Label(t("Refresh Geography Status", "刷新地理状态"), systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshingGeographyHealth)
            }

            historySyncSection

            Section(t("Notifications", "通知")) {
                LabeledContent(t("Permission", "权限"), value: notificationStatusText)
                if viewModel.notificationAuthorizationStatus == .notDetermined {
                    Button {
                        Task { await viewModel.requestNotificationAuthorization() }
                    } label: {
                        Label(t("Enable Notifications", "开启通知"), systemImage: "bell.badge")
                    }
                    .disabled(viewModel.isRequestingNotificationAuthorization)
                } else if viewModel.notificationAuthorizationStatus == .denied {
                    Label(
                        t("Notifications are disabled. Enable them in iOS Settings.", "通知已关闭，请前往 iOS 系统设置中开启。"),
                        systemImage: "bell.slash"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
                Button {
                    Task { await viewModel.sendTestNotification() }
                } label: {
                    Label(t("Test Charging Notification", "测试充电通知"), systemImage: "bolt.car")
                }
                .disabled(!viewModel.notificationAuthorizationStatus.canDeliver)
                Button {
                    Task { await viewModel.sendTestSentryNotification() }
                } label: {
                    Label(t("Test Sentry Notification", "测试哨兵通知"), systemImage: "shield.lefthalf.filled")
                }
                .disabled(!viewModel.notificationAuthorizationStatus.canDeliver)
                Button {
                    Task { await viewModel.sendTestTyrePressureNotification() }
                } label: {
                    Label(t("Test Tyre Pressure Notification", "测试胎压通知"), systemImage: "exclamationmark.circle")
                }
                .disabled(!viewModel.notificationAuthorizationStatus.canDeliver)
                if let message = viewModel.notificationMessage {
                    Text(UserFacingErrorLocalizer.localized(message, language: appLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(t(
                    "Charging progress and new tyre-pressure warnings are checked when MateDrive refreshes vehicle data.",
                    "MateDrive 刷新车辆数据时，会检查充电进度和新的胎压告警。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section(t("Preferences", "偏好")) {
                Picker(t("Language", "语言"), selection: $appLanguage) {
                    Text(t("Follow System", "跟随系统")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("简体中文").tag(AppLanguage.chinese)
                    Text("繁體中文").tag(AppLanguage.traditionalChinese)
                    Text("Deutsch").tag(AppLanguage.german)
                    Text("Español").tag(AppLanguage.spanish)
                    Text("Italiano").tag(AppLanguage.italian)
                    Text("Català").tag(AppLanguage.catalan)
                }
                .pickerStyle(.menu)

                Picker(t("Currency", "货币"), selection: $currencyCode) {
                    Text(automaticCurrencyLabel).tag(MateDroidCurrencyFormatter.automaticCode)
                    ForEach(MateDroidCurrencyFormatter.supportedCodes, id: \.self) { code in
                        Text(currencyLabel(code)).tag(code)
                    }
                }
                .pickerStyle(.menu)

                Picker(t("Units", "单位"), selection: $displayUnitSystem) {
                    Text(t("Follow TeslaMate", "跟随 TeslaMate")).tag(DisplayUnitSystem.teslamate)
                    Text(t("Metric (km, °C, bar)", "公制（公里、摄氏度、巴）")).tag(DisplayUnitSystem.metric)
                    Text(t("Imperial (mi, °F, psi)", "英制（英里、华氏度、磅力每平方英寸）")).tag(DisplayUnitSystem.imperial)
                }
                .pickerStyle(.menu)
            }

            Section(t("Battery Calibration", "电池校准")) {
                TextField(t("New Battery Usable Capacity (kWh)", "新车可用容量（千瓦时）"), text: $batteryReferenceCapacityKWh)
                    .keyboardType(.decimalPad)
                TextField(t("New Battery Rated Range", "新车额定续航"), text: $batteryReferenceRangeKm)
                    .keyboardType(.decimalPad)
                TextField(t("Recording Start Odometer", "开始记录时里程表"), text: $batteryRecordingStartOdometerKm)
                    .keyboardType(.decimalPad)
                Text(t("Battery Health Note", "如果知道车辆新车时的可用容量，请优先填写；否则可填写新车满电额定续航作为次级估算。请勿仅凭车型名称猜测容量。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(t("Privacy", "隐私")) {
                NavigationLink {
                    PrivacyDataView()
                } label: {
                    Label(t("Privacy & Local Data", "隐私与本地数据"), systemImage: "hand.raised")
                }
            }

            Section(t("Charge Pricing", "充电价格")) {
                NavigationLink {
                    ChargePricingRulesView(viewModel: viewModel)
                } label: {
                    HStack {
                        Label(t("Pricing Rules", "价格规则"), systemImage: "location.magnifyingglass")
                        Spacer()
                        Text(pricingHealthSummary)
                            .font(.caption)
                            .foregroundStyle(viewModel.chargePricingRulesHealth.needsAttention ? .red : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                NavigationLink {
                    ParkingFeeRulesView(viewModel: viewModel)
                } label: {
                    HStack {
                        Label(t("Parking Fee Rules", "停车费用规则"), systemImage: "parkingsign.circle")
                        Spacer()
                        Text("\(viewModel.settings.parkingFeeRules.filter(\.isEnabled).count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(t("Settings", "设置"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Save", "保存")) {
                    Task {
                        await viewModel.save(
                            serverURL: serverURL,
                            secondaryServerURL: secondaryServerURL,
                            apiToken: apiToken,
                            basicUsername: basicUsername,
                            basicPassword: basicPassword,
                            cloudflareClientID: cloudflareClientID,
                            cloudflareClientSecret: cloudflareClientSecret,
                            apiAccessKey: apiAccessKey,
                            apiSecretKey: apiSecretKey,
                            acceptInvalidCerts: acceptInvalidCerts,
                            currencyCode: currencyCode,
                            displayUnitSystem: displayUnitSystem,
                            appLanguage: appLanguage,
                            batteryReferenceRangeKm: parsedReferenceRange(),
                            batteryReferenceCapacityKWh: parsedReferenceCapacity(),
                            batteryRecordingStartOdometerKm: parsedRecordingStartOdometer()
                        )
                        if !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            await viewModel.testConnection(
                                serverURL: serverURL,
                                secondaryServerURL: secondaryServerURL,
                                acceptInvalidCerts: acceptInvalidCerts,
                                apiToken: apiToken,
                                basicUsername: basicUsername,
                                basicPassword: basicPassword,
                                cloudflareClientID: cloudflareClientID,
                                cloudflareClientSecret: cloudflareClientSecret,
                                apiAccessKey: apiAccessKey,
                                apiSecretKey: apiSecretKey
                            )
                        }
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .onChange(of: appLanguage) { _, language in
            Task {
                await viewModel.saveAppLanguage(language)
            }
        }
        .onChange(of: viewModel.settings) { _, settings in
            syncFields(with: settings)
        }
        .fileExporter(
            isPresented: $exportsDiagnostics,
            document: diagnosticExportDocument,
            contentType: .plainText,
            defaultFilename: diagnosticExportFilename
        ) { result in
            if case let .failure(error) = result {
                diagnosticExportError = error.localizedDescription
            }
            diagnosticExportDocument = nil
        }
        .alert(t("Export Failed", "导出失败"), isPresented: Binding(
            get: { diagnosticExportError != nil },
            set: { if !$0 { diagnosticExportError = nil } }
        )) {
            Button(t("OK", "确定"), role: .cancel) {}
        } message: {
            Text(diagnosticExportError ?? "")
        }
    }

    @ViewBuilder
    private var historySyncSection: some View {
        Section(t("Local History Sync", "本地历史同步")) {
            if let health = viewModel.historySyncHealth {
                LabeledContent(t("Drive Details", "行程详情"), value: "\(health.driveDetailCount)/\(health.driveSummaryCount)")
                LabeledContent(t("Charge Details", "充电详情"), value: "\(health.chargeDetailCount)/\(health.chargeSummaryCount)")
                LabeledContent(t("Pending Records", "待处理记录"), value: pendingRecordCountText(health))
                if let milliseconds = health.lastSyncAtMilliseconds {
                    LabeledContent(t("Last Sync", "最后同步")) {
                        Text(syncDate(milliseconds: milliseconds))
                    }
                }
                Label(syncHealthMessage(health), systemImage: syncHealthIcon(health))
                    .font(.footnote)
                    .foregroundStyle(syncHealthColor(health))
            } else if let error = viewModel.historySyncHealthError {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                ProgressView(t("Checking local history", "正在检查本地历史"))
            }
            if let report = viewModel.lastHistorySyncReport {
                Label(historySyncReportMessage(report), systemImage: historySyncReportIcon(report))
                    .font(.footnote)
                    .foregroundStyle(historySyncReportColor(report))
            }
            Button {
                Task { await viewModel.syncHistoryNow() }
            } label: {
                Label(
                    viewModel.isSyncingHistory ? t("Syncing History", "正在同步历史") : t("Sync Now", "立即同步"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSyncingHistory || viewModel.isSaving)
            Button {
                Task { await viewModel.refreshHistorySyncHealth() }
            } label: {
                Label(t("Refresh Sync Status", "刷新同步状态"), systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshingHistorySyncHealth || viewModel.isSyncingHistory)
        }
    }

    private var pricingHealthSummary: String {
        let health = viewModel.chargePricingRulesHealth
        if health.invalidCount > 0 {
            return t("\(health.activeCount) active · \(health.invalidCount) need attention", "\(health.activeCount) 个可用 · \(health.invalidCount) 个需修正")
        }
        if health.disabledCount > 0 {
            return t("\(health.activeCount) active · \(health.disabledCount) disabled", "\(health.activeCount) 个可用 · \(health.disabledCount) 个停用")
        }
        return t("\(health.activeCount) active", "\(health.activeCount) 个可用")
    }

    private var notificationStatusText: String {
        switch viewModel.notificationAuthorizationStatus {
        case .notDetermined: t("Not Requested", "尚未请求")
        case .denied: t("Disabled", "已关闭")
        case .authorized: t("Enabled", "已开启")
        case .provisional: t("Provisional", "临时授权")
        case .ephemeral: t("Temporary", "临时允许")
        }
    }

    @ViewBuilder
    private func versionCompatibility(_ version: TeslaMateVersionInfo) -> some View {
        let minimum = TeslaMateCapabilityPresentation.enhancedFeatureMinimumDisplayVersion
        switch TeslaMateCapabilityPresentation.meetsEnhancedFeatureMinimum(version) {
        case true:
            Label(t("API version baseline met (\(minimum)+); capability checks below determine availability.", "接口版本达到基线（\(minimum)+）；实际可用性以下方能力检测为准。"), systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case false:
            Label(t("MyTesS recommends API \(minimum)+ for all features; available capabilities are still detected individually.", "官方建议使用接口 \(minimum)+ 以获得完整功能；现有能力仍会逐项检测。"), systemImage: "arrow.up.circle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        case nil:
            Label(t("API version could not be identified.", "无法识别接口版本。"), systemImage: "questionmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func syncFields(with settings: AppSettings) {
        serverURL = settings.serverURL
        secondaryServerURL = settings.secondaryServerURL
        acceptInvalidCerts = settings.acceptInvalidCerts
        currencyCode = settings.currencyCode
        displayUnitSystem = settings.displayUnitSystem
        appLanguage = settings.appLanguage
        let calibration = settings.lastSelectedCarId.map { settings.batteryCalibration(for: $0) }
        batteryReferenceRangeKm = Self.referenceRangeText(calibration?.referenceRangeKm ?? settings.batteryReferenceRangeKm)
        batteryReferenceCapacityKWh = Self.numberText(calibration?.referenceCapacityKWh)
        batteryRecordingStartOdometerKm = Self.numberText(calibration?.recordingStartOdometerKm ?? settings.batteryRecordingStartOdometerKm)
    }

    private func exportDiagnostics(_ report: TeslaMateDiagnosticReport) {
        let generatedAt = Date()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let resolvedCurrency = currencyCode == MateDroidCurrencyFormatter.automaticCode
            ? MateDroidCurrencyFormatter.systemCurrencyCode()
            : currencyCode
        let metadata = TeslaMateDiagnosticExportMetadata(
            appVersion: version,
            appBuild: build,
            languageCode: appLanguage.localeIdentifier ?? "system",
            unitSystem: displayUnitSystem.rawValue,
            currencyCode: resolvedCurrency
        )
        diagnosticExportDocument = DiagnosticTextDocument(text: TeslaMateDiagnosticExport.render(
            report: report,
            metadata: metadata,
            generatedAt: generatedAt
        ))
        diagnosticExportFilename = TeslaMateDiagnosticExport.suggestedFilename(generatedAt: generatedAt)
        exportsDiagnostics = true
    }

    private var automaticCurrencyLabel: String {
        let code = MateDroidCurrencyFormatter.systemCurrencyCode()
        return "\(t("Follow Device Region", "跟随设备地区")) · \(code) \(MateDroidCurrencyFormatter.symbol(for: code))"
    }

    private func currencyLabel(_ code: String) -> String {
        let locale = appLanguage.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
        let name = locale.localizedString(forCurrencyCode: code) ?? code
        return "\(MateDroidCurrencyFormatter.symbol(for: code)) \(name) · \(code)"
    }

    private func parsedReferenceRange() -> Double? {
        let normalized = batteryReferenceRangeKm
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return normalized.isEmpty ? nil : Double(normalized)
    }

    private func parsedReferenceCapacity() -> Double? {
        let normalized = batteryReferenceCapacityKWh
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = normalized.isEmpty ? nil : Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }

    private func geographyDate(_ value: String) -> String {
        DomainDateParser.date(from: value)?.formatted(date: .abbreviated, time: .shortened) ?? value
    }

    private func syncDate(milliseconds: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func pendingRecordCountText(_ health: HistorySyncHealth) -> String {
        String(health.pendingDriveCount + health.pendingChargeCount)
    }

    private func syncHealthMessage(_ health: HistorySyncHealth) -> String {
        guard health.lastSyncAtMilliseconds != nil else {
            return t("Local history has not completed its first sync yet.", "本地历史尚未完成首次同步。")
        }
        if health.isComplete {
            return t("All summarized drives and charges have current detail data.", "全部行程和充电摘要均已有当前版本详情数据。")
        }
        return t(
            "Some history details are pending and will retry automatically.",
            "部分历史详情仍待补齐，应用会自动重试。"
        )
    }

    private func syncHealthIcon(_ health: HistorySyncHealth) -> String {
        guard health.lastSyncAtMilliseconds != nil else { return "clock.badge.questionmark" }
        return health.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func syncHealthColor(_ health: HistorySyncHealth) -> Color {
        guard health.lastSyncAtMilliseconds != nil else { return .secondary }
        return health.isComplete ? .green : .orange
    }

    private func historySyncReportMessage(_ report: HistorySyncReport) -> String {
        if report.attemptedCarIDs.isEmpty {
            return t("History sync could not start. Check the server connection.", "历史同步未能启动，请检查服务器连接。")
        }
        if !report.failedCarIDs.isEmpty {
            return t(
                "Synced \(report.completedCarIDs.count) vehicle(s); \(report.failedCarIDs.count) need retry.",
                "已同步 \(report.completedCarIDs.count) 辆车，\(report.failedCarIDs.count) 辆需要重试。"
            )
        }
        return t(
            "History sync completed for \(report.completedCarIDs.count) vehicle(s).",
            "已完成 \(report.completedCarIDs.count) 辆车的历史同步。"
        )
    }

    private func historySyncReportIcon(_ report: HistorySyncReport) -> String {
        report.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func historySyncReportColor(_ report: HistorySyncReport) -> Color {
        report.isComplete ? .green : .orange
    }

    private func geographyProcessingText(_ report: GeocodeQueueProcessingReport) -> String {
        if MateDroidUnitFormatter.usesChineseLabels(language: appLanguage) {
            return "已尝试 \(report.attemptedCount) · 已完成 \(report.completedCount) · 失败 \(report.failedCount)"
        }
        return "Attempted \(report.attemptedCount) · Completed \(report.completedCount) · Failed \(report.failedCount)"
    }

    private func parsedRecordingStartOdometer() -> Double? {
        parseOptionalDouble(batteryRecordingStartOdometerKm)
    }

    private func parseOptionalDouble(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return normalized.isEmpty ? nil : Double(normalized)
    }

    private static func referenceRangeText(_ value: Double?) -> String {
        numberText(value)
    }

    private static func numberText(_ value: Double?) -> String {
        value.map { String(format: "%.0f", $0) } ?? ""
    }

    private func diagnosticIcon(_ status: TeslaMateDiagnosticStatus) -> String {
        switch status {
        case .passed:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func diagnosticColor(_ status: TeslaMateDiagnosticStatus) -> Color {
        switch status {
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        }
    }

    private func localizedCapabilityTitle(_ capability: TeslaMateCapability) -> String {
        switch capability {
        case .serverStats: t("Server Statistics", "服务端统计")
        case .costReview: t("Vehicle Cost Review", "用车成本回顾")
        case .unifiedActivities: t("Unified Activities", "统一活动")
        case .batteryHealthHistory: t("Battery History", "电池历史")
        case .driveInsights: t("Drive Insights", "行程洞察")
        case .environmentHistory: t("Environment History", "环境与胎压")
        case .stateHistory: t("Sleep History", "休眠历史")
        case .topDrainLocations: t("Standby Hotspots", "待机耗电热点")
        case .commuteRoutes: t("Commute Routes", "通勤路线")
        case .statsExtremes: t("Driving Records", "驾驶纪录")
        case .drivingCoordinates: t("Recent Driving Map", "近期行驶地图")
        case .serverPlaces: t("Smart Places", "智能地点")
        default: capability.rawValue
        }
    }

    private func localizedCapabilityState(_ state: TeslaMateCapabilityState) -> String {
        switch state {
        case .available: t("Available", "可用")
        case .degraded: t("Limited", "受限")
        case .unavailable: t("Unavailable", "不可用")
        case .unknown: t("Unknown", "未知")
        }
    }

    private func capabilityColor(_ state: TeslaMateCapabilityState) -> Color {
        switch state {
        case .available: .green
        case .degraded: .orange
        case .unavailable: .gray
        case .unknown: .secondary
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DiagnosticTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
