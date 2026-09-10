import SwiftUI

@MainActor
public struct ChargePricingRulesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @ObservedObject private var viewModel: SettingsViewModel
    @State private var editingRule: ChargePricingRule?

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            let health = viewModel.chargePricingRulesHealth
            Section(t("Rule Health", "规则状态")) {
                LabeledContent(t("Active", "可用"), value: "\(health.activeCount)")
                LabeledContent(t("Disabled", "已停用"), value: "\(health.disabledCount)")
                LabeledContent(t("Needs Attention", "需要修正"), value: "\(health.invalidCount)")
                    .foregroundStyle(health.needsAttention ? .red : .primary)
            }

            if !sortedTemplates.isEmpty {
                Section {
                    ForEach(sortedTemplates) { template in
                        Button {
                            editingRule = template.makeRule()
                        } label: {
                            ChargeTariffTemplateRow(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteTemplates)
                } header: {
                    Text(t("Tariff Templates", "电价模板"))
                } footer: {
                    Text(t(
                        "Templates reuse pricing schedules without copying locations or effective dates.",
                        "模板只复用价格时段，不会复制位置或生效日期。"
                    ))
                }
            }

            if viewModel.settings.chargePricingRules.isEmpty {
                ContentUnavailableView(
                    t("No pricing rules", "暂无价格规则"),
                    systemImage: "location.slash",
                    description: Text(t("Add rules to estimate charging cost by location, time, and charger type.", "添加规则后，可按位置、时间和充电类型估算每笔充电费用。"))
                )
            } else {
                ForEach(sortedRules) { rule in
                    Button {
                        editingRule = rule
                    } label: {
                        ChargePricingRuleRow(rule: rule)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteRules)
            }
        }
        .navigationTitle(t("Pricing Rules", "价格规则"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        editingRule = ChargePricingRule(name: "", pricePerKWh: 0)
                    } label: {
                        Label(t("New Blank Rule", "新建空白规则"), systemImage: "plus")
                    }
                    if !sortedTemplates.isEmpty {
                        Menu(t("New from Template", "从模板新建")) {
                            ForEach(sortedTemplates) { template in
                                Button(template.name) {
                                    editingRule = template.makeRule()
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text(t("Add Pricing Rule", "添加价格规则")))
            }
        }
        .sheet(item: $editingRule) { rule in
            NavigationStack {
                ChargePricingRuleEditorView(
                    rule: rule,
                    onSave: { updatedRule in
                        Task {
                            await upsertRule(updatedRule)
                        }
                    },
                    onSaveTemplate: { template in
                        Task {
                            await upsertTemplate(template)
                        }
                    }
                )
            }
        }
    }

    private var sortedRules: [ChargePricingRule] {
        viewModel.settings.chargePricingRules.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var sortedTemplates: [ChargeTariffTemplate] {
        viewModel.settings.chargeTariffTemplates.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func upsertRule(_ rule: ChargePricingRule) async {
        var rules = viewModel.settings.chargePricingRules
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        await viewModel.saveChargePricingRules(rules)
        editingRule = nil
    }

    private func deleteRules(at offsets: IndexSet) {
        let ids = Set(offsets.map { sortedRules[$0].id })
        let rules = viewModel.settings.chargePricingRules.filter { !ids.contains($0.id) }
        Task {
            await viewModel.saveChargePricingRules(rules)
        }
    }

    private func upsertTemplate(_ template: ChargeTariffTemplate) async {
        var templates = viewModel.settings.chargeTariffTemplates
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        await viewModel.saveChargeTariffTemplates(templates)
    }

    private func deleteTemplates(at offsets: IndexSet) {
        let ids = Set(offsets.map { sortedTemplates[$0].id })
        let templates = viewModel.settings.chargeTariffTemplates.filter { !ids.contains($0.id) }
        Task {
            await viewModel.saveChargeTariffTemplates(templates)
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct ChargeTariffTemplateRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let template: ChargeTariffTemplate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: template.name)
                    .font(.body.weight(.medium))
                Text(verbatim: summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityHint(t("Create a new rule from this template", "使用此模板新建规则"))
    }

    private var summary: String {
        let type = template.chargeType.displayText(language: appLanguage)
        let price = template.timeSegments.isEmpty
            ? String(format: "%.2f/kWh", template.pricePerKWh)
            : "\(template.timeSegments.count) \(t("segments", "时段"))"
        return "\(type) · \(price)"
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct ChargePricingRuleRow: View {
    @Environment(\.appLanguage) private var appLanguage

    let rule: ChargePricingRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if rule.name.isEmpty {
                    Text(t("Pricing Rule", "价格规则"))
                        .font(.body.weight(.medium))
                } else {
                    Text(verbatim: rule.name)
                        .font(.body.weight(.medium))
                }
                Spacer()
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            Text(verbatim: summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var isValid: Bool {
        ChargePricingRuleValidator.issues(for: rule).isEmpty
    }

    private var statusText: String {
        if !isValid { return t("Needs attention", "需要修正") }
        return rule.isEnabled ? t("Enabled", "已启用") : t("Disabled", "已停用")
    }

    private var statusColor: Color {
        if !isValid { return .red }
        return rule.isEnabled ? .green : .secondary
    }

    private var summary: String {
        let type = switch rule.chargeType {
        case .any: ChargePricingChargeType.any.displayText(language: appLanguage)
        case .ac: ChargePricingChargeType.ac.displayText(language: appLanguage)
        case .dc: ChargePricingChargeType.dc.displayText(language: appLanguage)
        case .teslaSupercharger: ChargePricingChargeType.teslaSupercharger.displayText(language: appLanguage)
        case .otherDC: ChargePricingChargeType.otherDC.displayText(language: appLanguage)
        }
        let price: String
        if rule.timeSegments.isEmpty {
            price = String(format: "%.2f/kWh", rule.pricePerKWh)
        } else {
            price = "\(rule.timeSegments.count) \(t("segments", "时段"))"
        }
        let location = if let address = rule.addressKeyword, !address.isEmpty {
            address
        } else {
            t("Any location", "任意位置")
        }
        let time = timeSummary(start: rule.startMinuteOfDay, end: rule.endMinuteOfDay)
        let effectiveDates = effectiveDateSummary(rule: rule)
        return "\(type) · \(price) · \(location) · \(time) · \(effectiveDates)"
    }

    private func timeSummary(start: Int?, end: Int?) -> String {
        guard let start, let end else {
            return t("All day", "全天")
        }
        return "\(Self.timeText(start))-\(Self.timeText(end))"
    }

    private static func timeText(_ minute: Int) -> String {
        String(format: "%02d:%02d", max(0, min(minute, 1_439)) / 60, max(0, min(minute, 1_439)) % 60)
    }

    private func effectiveDateSummary(rule: ChargePricingRule) -> String {
        switch (rule.effectiveFromDate, rule.effectiveToDate) {
        case (nil, nil): return t("All dates", "全部日期")
        case let (from?, nil): return "\(t("From", "自")) \(from)"
        case let (nil, to?): return "\(t("Through", "至")) \(to)"
        case let (from?, to?): return "\(from)–\(to)"
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct ChargePricingRuleEditorView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isEnabled: Bool
    @State private var chargeType: ChargePricingChargeType
    @State private var addressKeyword: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var radiusMeters: String
    @State private var startTime: String
    @State private var endTime: String
    @State private var hasEffectiveFromDate: Bool
    @State private var effectiveFromDate: Date
    @State private var hasEffectiveToDate: Bool
    @State private var effectiveToDate: Date
    @State private var pricePerKWh: String
    @State private var timeSegments: [ChargePricingTimeSegmentDraft]
    @State private var sessionFee: String
    @State private var priority: String
    @State private var templateName: String
    @State private var templateID = UUID().uuidString
    @State private var didSaveTemplate = false

    private let originalRule: ChargePricingRule
    private let onSave: (ChargePricingRule) -> Void
    private let onSaveTemplate: (ChargeTariffTemplate) -> Void

    init(
        rule: ChargePricingRule,
        onSave: @escaping (ChargePricingRule) -> Void,
        onSaveTemplate: @escaping (ChargeTariffTemplate) -> Void
    ) {
        self.originalRule = rule
        self.onSave = onSave
        self.onSaveTemplate = onSaveTemplate
        _name = State(initialValue: rule.name)
        _isEnabled = State(initialValue: rule.isEnabled)
        _chargeType = State(initialValue: rule.chargeType)
        _addressKeyword = State(initialValue: rule.addressKeyword ?? "")
        _latitude = State(initialValue: Self.doubleText(rule.latitude))
        _longitude = State(initialValue: Self.doubleText(rule.longitude))
        _radiusMeters = State(initialValue: Self.doubleText(rule.radiusMeters))
        _startTime = State(initialValue: Self.timeText(rule.startMinuteOfDay))
        _endTime = State(initialValue: Self.timeText(rule.endMinuteOfDay))
        _hasEffectiveFromDate = State(initialValue: rule.effectiveFromDate != nil)
        _effectiveFromDate = State(initialValue: Self.date(from: rule.effectiveFromDate) ?? Date())
        _hasEffectiveToDate = State(initialValue: rule.effectiveToDate != nil)
        _effectiveToDate = State(initialValue: Self.date(from: rule.effectiveToDate) ?? Date())
        _pricePerKWh = State(initialValue: Self.doubleText(rule.pricePerKWh))
        _timeSegments = State(initialValue: rule.timeSegments.map(ChargePricingTimeSegmentDraft.init(segment:)))
        _sessionFee = State(initialValue: Self.doubleText(rule.sessionFee))
        _priority = State(initialValue: "\(rule.priority)")
        _templateName = State(initialValue: rule.name)
    }

    var body: some View {
        Form {
            Section(t("Rule", "规则")) {
                TextField(t("Name", "名称"), text: $name)
                Toggle(t("Enabled", "已启用"), isOn: $isEnabled)
                Picker(t("Charger Type", "充电类型"), selection: $chargeType) {
                    Text(ChargePricingChargeType.any.displayText(language: appLanguage)).tag(ChargePricingChargeType.any)
                    Text(ChargePricingChargeType.ac.displayText(language: appLanguage)).tag(ChargePricingChargeType.ac)
                    Text(ChargePricingChargeType.dc.displayText(language: appLanguage)).tag(ChargePricingChargeType.dc)
                    Text(ChargePricingChargeType.teslaSupercharger.displayText(language: appLanguage)).tag(ChargePricingChargeType.teslaSupercharger)
                    Text(ChargePricingChargeType.otherDC.displayText(language: appLanguage)).tag(ChargePricingChargeType.otherDC)
                }
                .pickerStyle(.menu)
            }

            Section(t("Location", "位置")) {
                TextField(t("Address Keyword", "地址关键词"), text: $addressKeyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(t("Latitude", "纬度"), text: $latitude)
                    .keyboardType(.decimalPad)
                TextField(t("Longitude", "经度"), text: $longitude)
                    .keyboardType(.decimalPad)
                TextField(t("Radius Meters", "半径（米）"), text: $radiusMeters)
                    .keyboardType(.decimalPad)
            }

            Section(t("Time", "时间")) {
                TextField(t("Start Time", "开始时间"), text: $startTime)
                    .keyboardType(.numbersAndPunctuation)
                TextField(t("End Time", "结束时间"), text: $endTime)
                    .keyboardType(.numbersAndPunctuation)
            }

            Section(t("Effective Dates", "生效日期")) {
                Toggle(t("Has Start Date", "设置开始日期"), isOn: $hasEffectiveFromDate)
                if hasEffectiveFromDate {
                    DatePicker(t("Effective From", "生效自"), selection: $effectiveFromDate, displayedComponents: .date)
                }
                Toggle(t("Has End Date", "设置结束日期"), isOn: $hasEffectiveToDate)
                if hasEffectiveToDate {
                    DatePicker(t("Effective Through", "生效至"), selection: $effectiveToDate, displayedComponents: .date)
                }
                Text(t(
                    "Use separate rules when the price changes so historical charging costs remain stable.",
                    "电价调整时请新增规则并划分日期，避免历史充电费用随新价格变化。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section(t("Price", "价格")) {
                TextField(t("Default Price per kWh", "默认每度电价格"), text: $pricePerKWh)
                    .keyboardType(.decimalPad)
                TextField(t("Session Fee", "单次服务费"), text: $sessionFee)
                    .keyboardType(.decimalPad)
                TextField(t("Priority", "优先级"), text: $priority)
                    .keyboardType(.numberPad)
            }

            Section(t("Price Segments", "分时价格")) {
                ForEach($timeSegments) { $segment in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField(t("Start Time", "开始时间"), text: $segment.startTime)
                                .keyboardType(.numbersAndPunctuation)
                            TextField(t("End Time", "结束时间"), text: $segment.endTime)
                                .keyboardType(.numbersAndPunctuation)
                        }
                        TextField(t("Price per kWh", "每度电价格"), text: $segment.pricePerKWh)
                            .keyboardType(.decimalPad)
                    }
                    .swipeActions {
                        Button(t("Delete", "删除"), role: .destructive) {
                            timeSegments.removeAll { $0.id == segment.id }
                        }
                    }
                }

                Button {
                    timeSegments.append(ChargePricingTimeSegmentDraft())
                } label: {
                    Label(t("Add Segment", "添加时段"), systemImage: "plus")
                }
            }

            Section(t("Reusable Tariff Template", "可复用电价模板")) {
                TextField(t("Template Name", "模板名称"), text: $templateName)
                Button {
                    let template = ChargeTariffTemplate(
                        id: templateID,
                        name: templateName.trimmingCharacters(in: .whitespacesAndNewlines),
                        rule: makeRule()
                    )
                    onSaveTemplate(template)
                    didSaveTemplate = true
                } label: {
                    Label(t("Save Pricing as Template", "将价格保存为模板"), systemImage: "square.and.arrow.down")
                }
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validationIssue != nil)

                Text(t(
                    "Only charger type and pricing schedule are saved. Location, effective dates, and priority stay with each rule.",
                    "模板只保存充电类型和价格时段；位置、生效日期和优先级仍由每条规则单独设置。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                if didSaveTemplate {
                    Label(t("Template Saved", "模板已保存"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let validationIssue {
                Section {
                    Label(validationMessage(validationIssue), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(originalRule.name.isEmpty ? t("Pricing Rule", "价格规则") : originalRule.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t("Cancel", "取消")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Save", "保存")) {
                    onSave(makeRule())
                    dismiss()
                }
                .disabled(validationIssue != nil)
            }
        }
    }

    private var parsedPricePerKWh: Double? {
        Self.double(from: pricePerKWh)
    }

    private var validationIssue: ChargePricingValidationIssue? {
        guard parsedPricePerKWh != nil else { return .invalidPrice }
        if !sessionFee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Self.double(from: sessionFee) == nil {
            return .invalidSessionFee
        }
        let locationInputs = [latitude, longitude, radiusMeters].map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if locationInputs.contains(true), locationInputs.contains(false) {
            return .incompleteLocation
        }
        if locationInputs.allSatisfy({ $0 }),
           (Self.double(from: latitude) == nil || Self.double(from: longitude) == nil || Self.double(from: radiusMeters) == nil) {
            return .invalidLocation
        }
        let hasStartTime = !startTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasEndTime = !endTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasStartTime != hasEndTime { return .incompleteTimeWindow }
        if hasStartTime,
           (Self.minuteOfDay(from: startTime) == nil || Self.minuteOfDay(from: endTime) == nil) {
            return .invalidTimeWindow
        }
        guard timeSegments.count == parsedTimeSegments.count else { return .invalidTimeSegment }
        return ChargePricingRuleValidator.issues(for: makeRule()).first
    }

    private func makeRule() -> ChargePricingRule {
        let draft = ChargePricingRule(
            id: originalRule.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? t("Pricing Rule", "价格规则") : name.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            chargeType: chargeType,
            addressKeyword: Self.optionalText(addressKeyword),
            latitude: Self.double(from: latitude),
            longitude: Self.double(from: longitude),
            radiusMeters: Self.double(from: radiusMeters),
            startMinuteOfDay: Self.minuteOfDay(from: startTime),
            endMinuteOfDay: Self.minuteOfDay(from: endTime),
            effectiveFromDate: hasEffectiveFromDate ? Self.dateText(effectiveFromDate) : nil,
            effectiveToDate: hasEffectiveToDate ? Self.dateText(effectiveToDate) : nil,
            pricePerKWh: parsedPricePerKWh ?? 0,
            timeSegments: parsedTimeSegments,
            sessionFee: Self.double(from: sessionFee) ?? 0,
            priority: Int(priority.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        )
        return draft.preservingEditorMetadata(from: originalRule)
    }

    private var parsedTimeSegments: [ChargePricingTimeSegment] {
        timeSegments.compactMap { draft in
            guard let start = Self.minuteOfDay(from: draft.startTime),
                  let end = Self.minuteOfDay(from: draft.endTime),
                  let price = Self.double(from: draft.pricePerKWh),
                  price >= 0
            else {
                return nil
            }
            return ChargePricingTimeSegment(
                id: draft.id,
                startMinuteOfDay: start,
                endMinuteOfDay: end,
                pricePerKWh: price
            )
        }
    }

    private static func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func double(from value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func doubleText(_ value: Double?) -> String {
        guard let value else {
            return ""
        }
        return String(format: "%.2f", value)
    }

    private static func minuteOfDay(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let parts = trimmed.split(separator: ":")
        if parts.count == 2,
           let hour = Int(parts[0]), (0...23).contains(hour),
           let minute = Int(parts[1]), (0...59).contains(minute) {
            return hour * 60 + minute
        }
        if let minute = Int(trimmed), (0...1_439).contains(minute) {
            return minute
        }
        return nil
    }

    private func validationMessage(_ issue: ChargePricingValidationIssue) -> String {
        switch issue {
        case .invalidPrice:
            return t("Enter a valid non-negative default price.", "请输入有效且不小于零的默认电价。")
        case .invalidSessionFee:
            return t("Session fee must be a non-negative number.", "单次服务费必须是有效且不小于零的数字。")
        case .invalidServiceFee:
            return t("Service fee must be a non-negative number.", "服务费必须是有效且不小于零的数字。")
        case .invalidApplicableWeekdays:
            return t("Applicable weekdays must use valid, unique calendar days.", "适用星期必须使用有效且不重复的日历值。")
        case .invalidApplicableMonths:
            return t("Applicable months must use valid, unique calendar months.", "适用月份必须使用有效且不重复的日历月份。")
        case .invalidCurrency:
            return t("Currency must use a three-letter code.", "币种必须使用三个字母的代码。")
        case .incompleteLocation:
            return t("Latitude, longitude, and radius must be entered together.", "纬度、经度和半径必须同时填写。")
        case .invalidLocation:
            return t("Enter valid coordinates and a radius greater than zero.", "请输入有效坐标和大于零的半径。")
        case .incompleteTimeWindow:
            return t("Start and end time must be entered together.", "开始时间和结束时间必须同时填写。")
        case .invalidTimeWindow:
            return t("Enter a valid rule time in HH:mm format.", "请输入有效的规则时间，例如 08:30。")
        case .invalidEffectiveDateRange:
            return t("The effective start date must not be after the end date.", "生效开始日期不能晚于结束日期。")
        case .invalidTimeSegment:
            return t("Complete every price segment with valid times and a non-negative price.", "请完整填写每个分时时段、有效时间和非负电价。")
        case .overlappingTimeSegments:
            return t("Price segments cannot overlap.", "分时时段不能重叠。")
        }
    }

    private static func timeText(_ minute: Int?) -> String {
        guard let minute else {
            return ""
        }
        let clamped = min(max(minute, 0), 1_439)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return dateFormatter.date(from: value)
    }

    private static func dateText(_ value: Date) -> String {
        dateFormatter.string(from: value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

extension ChargePricingRule {
    func preservingEditorMetadata(from original: ChargePricingRule) -> ChargePricingRule {
        var updated = self
        updated.origin = original.origin
        updated.regionCode = original.regionCode
        updated.sourceURL = original.sourceURL
        updated.verifiedAt = original.verifiedAt
        updated.serviceFeePerKWh = original.serviceFeePerKWh
        updated.parkingFeeRuleID = original.parkingFeeRuleID
        updated.applicableWeekdays = original.applicableWeekdays
        updated.applicableMonths = original.applicableMonths
        updated.currencyCode = original.currencyCode
        updated.stationKey = original.stationKey
        return updated
    }
}

private struct ChargePricingTimeSegmentDraft: Identifiable {
    var id: String
    var startTime: String
    var endTime: String
    var pricePerKWh: String

    init(id: String = UUID().uuidString, startTime: String = "", endTime: String = "", pricePerKWh: String = "") {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.pricePerKWh = pricePerKWh
    }

    init(segment: ChargePricingTimeSegment) {
        self.id = segment.id
        self.startTime = Self.timeText(segment.startMinuteOfDay)
        self.endTime = Self.timeText(segment.endMinuteOfDay)
        self.pricePerKWh = String(format: "%.2f", segment.pricePerKWh)
    }

    private static func timeText(_ minute: Int) -> String {
        let clamped = min(max(minute, 0), 1_439)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
