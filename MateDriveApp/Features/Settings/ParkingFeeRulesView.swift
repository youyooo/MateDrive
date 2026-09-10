import MapKit
import SwiftUI

@MainActor
public struct ParkingFeeRulesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @ObservedObject private var viewModel: SettingsViewModel
    @State private var editingRule: ParkingFeeRule?

    public init(viewModel: SettingsViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView(
                    t("No parking fee rules", "暂无停车费用规则"),
                    systemImage: "parkingsign.circle",
                    description: Text(t("Add location rules for free time, hourly billing, caps, fixed fees, or monthly parking.", "添加地点规则，可设置免费时长、按时计费、封顶、固定费或包月停车。"))
                )
            } else {
                ForEach(rules) { rule in
                    Button { editingRule = rule } label: { row(rule) }.buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(t("Parking Fees", "停车费用"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editingRule = ParkingFeeRule(name: "", hourlyRate: 0) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(t("Add Parking Rule", "添加停车规则"))
            }
        }
        .sheet(item: $editingRule) { rule in
            NavigationStack { ParkingFeeRuleEditor(rule: rule, onSave: save) }
                .environment(\.appLanguage, appLanguage)
        }
    }

    private var rules: [ParkingFeeRule] {
        viewModel.settings.parkingFeeRules.sorted {
            $0.priority == $1.priority ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.priority > $1.priority
        }
    }

    private func row(_ rule: ParkingFeeRule) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(rule.name.isEmpty ? t("Parking Rule", "停车规则") : rule.name).font(.body.weight(.medium))
                Spacer()
                Text(rule.isEnabled ? t("Enabled", "已启用") : t("Disabled", "已停用"))
                    .font(.caption.weight(.semibold)).foregroundStyle(rule.isEnabled ? .green : .secondary)
            }
            Text(summary(rule)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.vertical, 4)
    }

    private func summary(_ rule: ParkingFeeRule) -> String {
        let place = rule.addressKeyword?.nilIfBlank ?? t("Any location", "任意地点")
        if let monthly = rule.monthlyFee, monthly > 0 {
            return t("\(place) · \(money(monthly))/month", "\(place) · \(money(monthly))/月")
        }
        return t(
            "\(place) · \(rule.freeMinutes) min free · \(money(rule.hourlyRate))/h",
            "\(place) · 免费 \(rule.freeMinutes) 分钟 · \(money(rule.hourlyRate))/小时"
        )
    }

    private func save(_ rule: ParkingFeeRule) {
        var updated = viewModel.settings.parkingFeeRules
        if let index = updated.firstIndex(where: { $0.id == rule.id }) { updated[index] = rule } else { updated.append(rule) }
        Task { await viewModel.saveParkingFeeRules(updated); editingRule = nil }
    }

    private func delete(_ offsets: IndexSet) {
        let ids = Set(offsets.map { rules[$0].id })
        Task { await viewModel.saveParkingFeeRules(viewModel.settings.parkingFeeRules.filter { !ids.contains($0.id) }) }
    }

    private func money(_ value: Double) -> String { String(format: "%.2f", value) }
    private func t(_ en: String, _ zh: String) -> String { AppText.localized(en, zh, language: appLanguage) }
}

private struct ParkingFeeRuleEditor: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    let original: ParkingFeeRule
    let onSave: (ParkingFeeRule) -> Void

    @State private var name: String
    @State private var enabled: Bool
    @State private var address: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var radius: String
    @State private var freeMinutes: String
    @State private var increment: String
    @State private var hourlyRate: String
    @State private var fixedFee: String
    @State private var cap: String
    @State private var monthlyFee: String
    @State private var priority: String

    init(rule: ParkingFeeRule, onSave: @escaping (ParkingFeeRule) -> Void) {
        original = rule; self.onSave = onSave
        _name = State(initialValue: rule.name); _enabled = State(initialValue: rule.isEnabled)
        _address = State(initialValue: rule.addressKeyword ?? "")
        _latitude = State(initialValue: rule.latitude.map { String($0) } ?? "")
        _longitude = State(initialValue: rule.longitude.map { String($0) } ?? "")
        _radius = State(initialValue: rule.radiusMeters.map { String($0) } ?? "")
        _freeMinutes = State(initialValue: String(rule.freeMinutes)); _increment = State(initialValue: String(rule.billingIncrementMinutes))
        _hourlyRate = State(initialValue: String(rule.hourlyRate)); _fixedFee = State(initialValue: String(rule.fixedFee))
        _cap = State(initialValue: rule.sessionCap.map { String($0) } ?? "")
        _monthlyFee = State(initialValue: rule.monthlyFee.map { String($0) } ?? "")
        _priority = State(initialValue: String(rule.priority))
    }

    var body: some View {
        Form {
            Section(t("Rule", "规则")) {
                TextField(t("Name", "名称"), text: $name)
                Toggle(t("Enabled", "启用"), isOn: $enabled)
                TextField(t("Address Keyword", "地址关键词"), text: $address)
                TextField(t("Priority", "优先级"), text: $priority).keyboardType(.numberPad)
            }
            Section(t("Coordinate Match", "坐标匹配")) {
                TextField(t("Latitude", "纬度"), text: $latitude).keyboardType(.decimalPad)
                TextField(t("Longitude", "经度"), text: $longitude).keyboardType(.decimalPad)
                TextField(t("Radius (m)", "半径（米）"), text: $radius).keyboardType(.decimalPad)
                Text(t("Leave all coordinate fields blank to match by address only.", "坐标字段全部留空时仅按地址匹配。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(t("Billing", "计费")) {
                TextField(t("Free Minutes", "免费分钟"), text: $freeMinutes).keyboardType(.numberPad)
                TextField(t("Billing Increment (min)", "计费步长（分钟）"), text: $increment).keyboardType(.numberPad)
                TextField(t("Hourly Rate", "小时费率"), text: $hourlyRate).keyboardType(.decimalPad)
                TextField(t("Fixed Fee", "固定费用"), text: $fixedFee).keyboardType(.decimalPad)
                TextField(t("Session Cap (optional)", "单次封顶（可选）"), text: $cap).keyboardType(.decimalPad)
                TextField(t("Monthly Fee (optional)", "包月费用（可选）"), text: $monthlyFee).keyboardType(.decimalPad)
                Text(t("When a monthly fee is set, it is counted once per rule and calendar month instead of per parking event.", "设置包月费用后，同一规则每个自然月只计一次，不再逐次计算停车费。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !issues.isEmpty {
                Section { Label(validationText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .navigationTitle(t("Parking Rule", "停车规则"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("Cancel", "取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(t("Save", "保存")) { onSave(rule) }.disabled(!issues.isEmpty) }
        }
    }

    private var rule: ParkingFeeRule {
        ParkingFeeRule(
            id: original.id, name: name, isEnabled: enabled, addressKeyword: address.nilIfBlank,
            latitude: Double(latitude), longitude: Double(longitude), radiusMeters: Double(radius),
            freeMinutes: Int(freeMinutes) ?? -1, billingIncrementMinutes: Int(increment) ?? 0,
            hourlyRate: Double(hourlyRate) ?? -.infinity, fixedFee: Double(fixedFee) ?? -.infinity,
            sessionCap: cap.nilIfBlank.flatMap(Double.init), monthlyFee: monthlyFee.nilIfBlank.flatMap(Double.init),
            priority: Int(priority) ?? 0
        )
    }
    private var issues: [ParkingFeeValidationIssue] { ParkingFeeRuleValidator.issues(for: rule) }
    private var validationText: String { t("Complete the rule with valid non-negative values and a billing method.", "请填写有效的非负数值，并至少配置一种计费方式。") }
    private func t(_ en: String, _ zh: String) -> String { AppText.localized(en, zh, language: appLanguage) }
}

@MainActor
struct GeofenceRulesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @ObservedObject private var viewModel: SettingsViewModel
    @State private var editingRule: GeofenceRule?

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        List {
            Section {
                Toggle(
                    t("Use fences for commute suggestions", "围栏参与通勤建议"),
                    isOn: Binding(
                        get: { viewModel.settings.usesGeofencesForCommuteClassification },
                        set: { enabled in
                            Task {
                                await viewModel.saveGeofenceRules(
                                    viewModel.settings.geofenceRules,
                                    usesForCommuteClassification: enabled
                                )
                            }
                        }
                    )
                )
            } footer: {
                Text(t("Fences are evaluated from TeslaMate coordinates after sync. MateDrive does not request your phone location.", "围栏仅根据同步后的 TeslaMate 车辆坐标判断，MateDrive 不会请求手机定位。"))
            }

            if rules.isEmpty {
                ContentUnavailableView(
                    t("No geofences", "暂无地理围栏"),
                    systemImage: "mappin.and.ellipse",
                    description: Text(t("Create Home, Work, charging, or parking fences to organize vehicle activity.", "创建家、公司、充电点或停车点围栏，用于整理车辆活动。"))
                )
            } else {
                Section {
                    ForEach(rules) { rule in
                        Button { editingRule = rule } label: { row(rule) }
                            .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle(t("Geofences", "地理围栏"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingRule = GeofenceRule(name: "", latitude: .zero, longitude: .zero)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(t("Add geofence", "添加地理围栏"))
            }
        }
        .sheet(item: $editingRule) { rule in
            NavigationStack {
                GeofenceRuleEditor(rule: rule, onSave: save)
            }
            .environment(\.appLanguage, appLanguage)
        }
    }

    private var rules: [GeofenceRule] {
        viewModel.settings.geofenceRules.sorted {
            if $0.isEnabled != $1.isEnabled { return $0.isEnabled }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func row(_ rule: GeofenceRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rule.kind.systemImage)
                .foregroundStyle(rule.isEnabled ? .green : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name).font(.body.weight(.semibold))
                Text(verbatim: "\(rule.kind.title(language: appLanguage)) · \(Int(rule.radiusMeters)) \(t("m", "米"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !rule.isEnabled {
                Text(t("Off", "关闭"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func save(_ rule: GeofenceRule) {
        var updated = viewModel.settings.geofenceRules
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            updated[index] = rule
        } else {
            updated.append(rule)
        }
        Task {
            await viewModel.saveGeofenceRules(updated)
            editingRule = nil
        }
    }

    private func delete(_ offsets: IndexSet) {
        let ids = Set(offsets.map { rules[$0].id })
        Task {
            await viewModel.saveGeofenceRules(viewModel.settings.geofenceRules.filter { !ids.contains($0.id) })
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

struct GeofenceRuleEditor: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    let original: GeofenceRule
    let onSave: (GeofenceRule) -> Void

    @State private var name: String
    @State private var kind: GeofenceKind
    @State private var isEnabled: Bool
    @State private var usesForCommute: Bool
    @State private var latitude: String
    @State private var longitude: String
    @State private var radiusMeters: Double

    init(rule: GeofenceRule, onSave: @escaping (GeofenceRule) -> Void) {
        original = rule
        self.onSave = onSave
        _name = State(initialValue: rule.name)
        _kind = State(initialValue: rule.kind)
        _isEnabled = State(initialValue: rule.isEnabled)
        _usesForCommute = State(initialValue: rule.participatesInCommuteClassification)
        _latitude = State(initialValue: rule.latitude == 0 ? "" : String(rule.latitude))
        _longitude = State(initialValue: rule.longitude == 0 ? "" : String(rule.longitude))
        _radiusMeters = State(initialValue: min(max(rule.radiusMeters, 50), 1_000))
    }

    var body: some View {
        Form {
            Section(t("Fence", "围栏")) {
                TextField(t("Name", "名称"), text: $name)
                Picker(t("Type", "类型"), selection: $kind) {
                    ForEach(GeofenceKind.allCases) { value in
                        Label(value.title(language: appLanguage), systemImage: value.systemImage).tag(value)
                    }
                }
                Toggle(t("Enabled", "启用"), isOn: $isEnabled)
                Toggle(t("Use for commute suggestions", "用于通勤建议"), isOn: $usesForCommute)
            }

            Section(t("Location", "位置")) {
                TextField(t("Latitude", "纬度"), text: $latitude)
                    .keyboardType(.numbersAndPunctuation)
                TextField(t("Longitude", "经度"), text: $longitude)
                    .keyboardType(.numbersAndPunctuation)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(t("Radius", "半径"), systemImage: "ruler")
                        Spacer()
                        Text(verbatim: "\(Int(radiusMeters)) \(t("m", "米"))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $radiusMeters, in: 50 ... 1_000, step: 10)
                        .tint(.green)
                }
            }

            Section(t("Choose on map", "在地图上选点")) {
                MapReader { proxy in
                    Map(
                        initialPosition: .region(mapRegion),
                        interactionModes: [.pan, .zoom]
                    ) {
                        if let coordinate {
                            Marker(name.isEmpty ? t("Geofence", "地理围栏") : name, coordinate: coordinate)
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { point in
                        guard let selected = proxy.convert(point, from: .local) else { return }
                        latitude = String(format: "%.6f", selected.latitude)
                        longitude = String(format: "%.6f", selected.longitude)
                    }
                }
                Text(t("Tap the map to set the center. The smallest matching enabled fence wins when places overlap.", "点击地图设置围栏中心。多个围栏重叠时，优先识别半径更小的已启用地点。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isValid {
                Section {
                    Label(t("Enter a name, valid coordinates, and a radius between 50 and 1,000 meters.", "请填写名称、有效坐标，以及 50 至 1,000 米之间的半径。"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(t("Geofence", "地理围栏"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t("Cancel", "取消")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Save", "保存")) {
                    onSave(rule)
                }
                .disabled(!isValid)
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = Double(latitude), let longitude = Double(longitude),
              GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var span: MKCoordinateSpan {
        let delta = max(radiusMeters / 55_000, 0.004)
        return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
    }

    private var mapRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate ?? CLLocationCoordinate2D(),
            span: coordinate == nil
                ? MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 35)
                : span
        )
    }

    private var rule: GeofenceRule {
        GeofenceRule(
            id: original.id,
            carId: original.carId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            latitude: Double(latitude) ?? 0,
            longitude: Double(longitude) ?? 0,
            radiusMeters: radiusMeters,
            isEnabled: isEnabled,
            participatesInCommuteClassification: usesForCommute
        )
    }

    private var isValid: Bool {
        GeofenceRuleValidator.isValid(rule)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
