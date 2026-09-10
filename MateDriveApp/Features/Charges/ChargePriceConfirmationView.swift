import Foundation
import SwiftUI

public enum ChargePricingConfirmationValidationIssue: Equatable, Sendable {
    case invalidFinalAmount
    case invalidBilledEnergy
    case invalidUnitPrice
    case invalidServiceFee
    case invalidFixedFee
    case invalidCurrency
    case missingFutureUnitPrice
    case incompleteTimeWindow
    case invalidTimeWindow
}

public enum ChargePricingConfirmationValidator {
    public static func validate(
        _ value: ChargePricingConfirmation
    ) -> [ChargePricingConfirmationValidationIssue] {
        var issues: [ChargePricingConfirmationValidationIssue] = []

        if !value.finalAmount.isFinite || value.finalAmount < 0 {
            issues.append(.invalidFinalAmount)
        }
        if let energy = value.billedEnergyKWh,
           !energy.isFinite || energy <= 0 {
            issues.append(.invalidBilledEnergy)
        }
        if let price = value.pricePerKWh,
           !price.isFinite || price < 0 {
            issues.append(.invalidUnitPrice)
        }
        if let fee = value.serviceFeePerKWh,
           !fee.isFinite || fee < 0 {
            issues.append(.invalidServiceFee)
        }
        if let fee = value.fixedFee,
           !fee.isFinite || fee < 0 {
            issues.append(.invalidFixedFee)
        }

        if (value.startMinute == nil) != (value.endMinute == nil) {
            issues.append(.incompleteTimeWindow)
        } else if let startMinute = value.startMinute,
                  let endMinute = value.endMinute,
                  !(0...1_439).contains(startMinute) || !(0...1_439).contains(endMinute) {
            issues.append(.invalidTimeWindow)
        }

        guard let currencyCode = ChargePricingCurrencyCode.normalized(value.currencyCode),
              ChargePricingCurrencyCode.isValid(currencyCode) else {
            issues.append(.invalidCurrency)
            return issues
        }

        if value.scope == .futureAtStation,
           resolvedUnitPrice(for: value) == nil,
           !issues.contains(.invalidUnitPrice) {
            issues.append(.missingFutureUnitPrice)
        }

        return issues
    }

    public static func resolvedUnitPrice(
        for value: ChargePricingConfirmation
    ) -> Double? {
        if let price = value.pricePerKWh {
            return price.isFinite && price >= 0 ? price : nil
        }
        guard value.finalAmount.isFinite,
              value.finalAmount >= 0,
              let energy = value.billedEnergyKWh,
              energy.isFinite,
              energy > 0,
              value.serviceFeePerKWh.map({ $0.isFinite && $0 >= 0 }) ?? true,
              value.fixedFee.map({ $0.isFinite && $0 >= 0 }) ?? true
        else {
            return nil
        }

        let serviceFee = (value.serviceFeePerKWh ?? 0) * energy
        let derived = (value.finalAmount - serviceFee - (value.fixedFee ?? 0)) / energy
        return derived.isFinite && derived >= 0 ? derived : nil
    }
}

public struct ChargePriceConfirmationView: View {
    @Environment(\.appLanguage) private var appLanguage

    private let seed: ChargePricingConfirmation
    private let stationName: String
    private let currencySymbol: String
    private let service: any ChargePricingObservationServicing
    private let onSaved: @MainActor (ChargePricingConfirmation) -> Void
    private let onCancel: @MainActor () -> Void

    @State private var scope: ChargePricingObservationScope
    @State private var finalAmountText: String
    @State private var billedEnergyText: String
    @State private var unitPriceText: String
    @State private var serviceFeeText: String
    @State private var fixedFeeText: String
    @State private var chargerChoice: Int
    @State private var hasTimeWindow: Bool
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isSaving = false
    @State private var saveError: String?

    public init(
        confirmation: ChargePricingConfirmation,
        stationName: String,
        currencySymbol: String? = nil,
        service: any ChargePricingObservationServicing,
        onSaved: @escaping @MainActor (ChargePricingConfirmation) -> Void = { _ in },
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.seed = confirmation
        self.stationName = stationName
        self.currencySymbol = currencySymbol
            ?? MateDriveCurrencyFormatter.symbol(for: confirmation.currencyCode)
        self.service = service
        self.onSaved = onSaved
        self.onCancel = onCancel

        _scope = State(initialValue: confirmation.scope)
        _finalAmountText = State(initialValue: Self.decimalText(confirmation.finalAmount))
        _billedEnergyText = State(initialValue: Self.decimalText(confirmation.billedEnergyKWh))
        _unitPriceText = State(initialValue: Self.decimalText(confirmation.pricePerKWh))
        _serviceFeeText = State(initialValue: Self.decimalText(confirmation.serviceFeePerKWh))
        _fixedFeeText = State(initialValue: Self.decimalText(confirmation.fixedFee))
        _chargerChoice = State(initialValue: Self.choice(for: confirmation.chargerIdentity))

        let hasWindow = confirmation.startMinute != nil && confirmation.endMinute != nil
        _hasTimeWindow = State(initialValue: hasWindow)
        _startTime = State(initialValue: Self.date(for: confirmation.startMinute ?? 0))
        _endTime = State(initialValue: Self.date(for: confirmation.endMinute ?? 1_439))
    }

    public var body: some View {
        NavigationStack {
            Form {
                stationSection
                scopeSection
                amountSection
                pricingSection
                chargerSection
                timeWindowSection
                validationSection
            }
            .navigationTitle(t("Confirm charging price", "确认充电价格"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消"), action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(t("Save", "保存"))
                        }
                    }
                    .disabled(isSaving || !validationIssues.isEmpty)
                }
            }
        }
    }

    private var stationSection: some View {
        Section(t("Station", "地点")) {
            LabeledContent(t("Charging location", "充电地点"), value: stationName)
            LabeledContent(t("Currency", "货币")) {
                Text("\(currencySymbol) \(seed.currencyCode.uppercased())")
                    .monospacedDigit()
            }
        }
    }

    private var scopeSection: some View {
        Section {
            Picker(t("Price scope", "价格范围"), selection: $scope) {
                Text(t("This charge only", "仅本次"))
                    .tag(ChargePricingObservationScope.sessionOnly)
                Text(t("Future charges here", "此地点以后"))
                    .tag(ChargePricingObservationScope.futureAtStation)
            }
            .pickerStyle(.segmented)
        } header: {
            Text(t("Applies to", "应用范围"))
        } footer: {
            Text(scope == .sessionOnly
                 ? t("Saves the confirmed result for this charge.", "只保存本次充电的确认结果。")
                 : t("Also learns a reusable rule for future charging at this location.", "同时学习此地点以后充电可复用的价格规则。"))
        }
    }

    private var amountSection: some View {
        Section {
            decimalField(
                title: t("Final amount", "最终金额"),
                text: $finalAmountText,
                prefix: currencySymbol,
                suffix: nil,
                accessibilityHint: t("The final amount on the user's bill.", "用户账单上的最终金额。")
            )
            decimalField(
                title: t("Billed energy", "计费电量"),
                text: $billedEnergyText,
                prefix: nil,
                suffix: "kWh",
                accessibilityHint: t(
                    "Enter energy from the user's bill or charger meter, not TeslaMate vehicle energy.",
                    "填写用户账单或充电桩表计电量，不是 TeslaMate 车辆侧电量。"
                )
            )
        } header: {
            Text(t("Bill", "账单"))
        } footer: {
            Text(t(
                "Billed energy is optional. When entered, it must come from your bill or charger meter and be greater than zero.",
                "计费电量可留空；填写时应来自账单或充电桩表计，并且必须大于 0。"
            ))
        }
    }

    private var pricingSection: some View {
        Section(t("Price components", "价格组成")) {
            decimalField(
                title: t("Energy unit price", "电费单价"),
                text: $unitPriceText,
                prefix: currencySymbol,
                suffix: "/kWh",
                accessibilityHint: t("Energy price per kilowatt-hour.", "每千瓦时的电费单价。")
            )
            decimalField(
                title: t("Service fee", "服务费"),
                text: $serviceFeeText,
                prefix: currencySymbol,
                suffix: "/kWh",
                accessibilityHint: t("Service fee per kilowatt-hour.", "每千瓦时的服务费。")
            )
            decimalField(
                title: t("Fixed fee", "固定费"),
                text: $fixedFeeText,
                prefix: currencySymbol,
                suffix: nil,
                accessibilityHint: t("One-time fixed fee for this charging session.", "本次充电的一次性固定费用。")
            )

            if scope == .futureAtStation {
                LabeledContent(t("Rule unit price", "规则采用单价")) {
                    Text(resolvedUnitPriceText)
                        .foregroundStyle(resolvedUnitPrice == nil ? Color.orange : Color.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var chargerSection: some View {
        Section(t("Charger", "充电桩")) {
            Picker(t("Charger type", "充电桩类型"), selection: $chargerChoice) {
                ForEach(Array(Self.chargerIdentities.indices), id: \.self) { index in
                    Text(chargerName(Self.chargerIdentities[index])).tag(index)
                }
            }
        }
    }

    private var timeWindowSection: some View {
        Section {
            Toggle(t("Use this time window", "使用此时间段"), isOn: $hasTimeWindow)
            if hasTimeWindow {
                DatePicker(
                    t("Starts", "开始"),
                    selection: $startTime,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    t("Ends", "结束"),
                    selection: $endTime,
                    displayedComponents: .hourAndMinute
                )
            }
            LabeledContent(t("Summary", "摘要"), value: timeWindowSummary)
        } header: {
            Text(t("Time window", "时间段"))
        } footer: {
            Text(t(
                "The time window is saved with future rules and may cross midnight.",
                "时间段会随地点规则保存，并且可以跨越午夜。"
            ))
        }
    }

    @ViewBuilder
    private var validationSection: some View {
        if let saveError {
            Section {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } else if let issue = validationIssues.first {
            Section {
                Label(validationMessage(issue), systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func decimalField(
        title: String,
        text: Binding<String>,
        prefix: String?,
        suffix: String?,
        accessibilityHint: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                if let prefix {
                    Text(prefix).foregroundStyle(.secondary)
                }
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(minWidth: 76)
                if let suffix {
                    Text(suffix).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHint(accessibilityHint)
    }

    private var confirmation: ChargePricingConfirmation {
        ChargePricingConfirmation(
            carId: seed.carId,
            chargeId: seed.chargeId,
            stationKey: seed.stationKey,
            scope: scope,
            finalAmount: Self.requiredNumber(finalAmountText),
            billedEnergyKWh: Self.optionalNumber(billedEnergyText),
            pricePerKWh: Self.optionalNumber(unitPriceText),
            serviceFeePerKWh: Self.optionalNumber(serviceFeeText),
            fixedFee: Self.optionalNumber(fixedFeeText),
            currencyCode: seed.currencyCode,
            coordinates: seed.coordinates,
            chargerIdentity: Self.chargerIdentities[chargerChoice],
            startMinute: hasTimeWindow ? Self.minuteOfDay(startTime) : nil,
            endMinute: hasTimeWindow ? Self.minuteOfDay(endTime) : nil
        )
    }

    private var validationIssues: [ChargePricingConfirmationValidationIssue] {
        ChargePricingConfirmationValidator.validate(confirmation)
    }

    private var resolvedUnitPrice: Double? {
        ChargePricingConfirmationValidator.resolvedUnitPrice(for: confirmation)
    }

    private var resolvedUnitPriceText: String {
        guard let resolvedUnitPrice else {
            return t("Required", "需要补充")
        }
        return String(format: "%@%.4f/kWh", currencySymbol, resolvedUnitPrice)
    }

    private var timeWindowSummary: String {
        guard hasTimeWindow else {
            return t("All day", "全天")
        }
        return "\(Self.timeText(startTime))-\(Self.timeText(endTime))"
    }

    private func save() {
        let value = confirmation
        guard ChargePricingConfirmationValidator.validate(value).isEmpty else { return }

        isSaving = true
        saveError = nil
        Task {
            do {
                try await service.confirm(value)
                await MainActor.run {
                    isSaving = false
                    onSaved(value)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = t(
                        "Could not save the charging price. \(error.localizedDescription)",
                        "无法保存充电价格。\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func chargerName(_ value: ChargePricingChargerIdentity) -> String {
        switch value {
        case .ac: return t("AC charger", "交流充电桩")
        case .teslaSupercharger: return t("Tesla Supercharger", "特斯拉超充")
        case .otherDC: return t("Other DC charger", "其他直流充电桩")
        case .unknownDC: return t("Unknown DC charger", "未知直流充电桩")
        }
    }

    private func validationMessage(_ issue: ChargePricingConfirmationValidationIssue) -> String {
        switch issue {
        case .invalidFinalAmount:
            return t("Enter a finite final amount of zero or more.", "最终金额必须是大于或等于 0 的有效数字。")
        case .invalidBilledEnergy:
            return t("Billed energy must be greater than zero.", "计费电量必须大于 0。")
        case .invalidUnitPrice:
            return t("The energy unit price cannot be negative.", "电费单价不能为负数。")
        case .invalidServiceFee:
            return t("The service fee cannot be negative.", "服务费不能为负数。")
        case .invalidFixedFee:
            return t("The fixed fee cannot be negative.", "固定费不能为负数。")
        case .invalidCurrency:
            return t("The currency code is invalid.", "币种代码无效。")
        case .missingFutureUnitPrice:
            return t(
                "Enter a unit price, or enough bill data to derive one for future charges.",
                "请填写单价，或填写足够的账单数据以计算此地点以后的单价。"
            )
        case .incompleteTimeWindow:
            return t("Enter both the start and end of the time window.", "时间段必须同时包含开始和结束时间。")
        case .invalidTimeWindow:
            return t("Time values must be between 00:00 and 23:59.", "时间必须在 00:00 到 23:59 之间。")
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private static let chargerIdentities: [ChargePricingChargerIdentity] = [
        .ac,
        .teslaSupercharger,
        .otherDC,
        .unknownDC
    ]

    private static func choice(for value: ChargePricingChargerIdentity) -> Int {
        chargerIdentities.firstIndex(of: value) ?? 0
    }

    private static func decimalText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.4f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static func requiredNumber(_ value: String) -> Double {
        optionalNumber(value) ?? .nan
    }

    private static func optionalNumber(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: ".")) ?? .nan
    }

    private static func date(for minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: max(0, min(23, minute / 60)),
            minute: max(0, min(59, minute % 60)),
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
