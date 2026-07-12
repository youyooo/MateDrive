import SwiftUI
import UniformTypeIdentifiers

public struct ChargePricingBatchView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel: ChargesViewModel
    @State private var confirmation: Confirmation?
    @State private var exportDocument: ChargePricingAuditCSVDocument?
    @State private var exportsAudit = false
    @State private var exportError: String?

    public init(viewModel: ChargesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            overviewSection
            candidatesSection
            if let receipt = viewModel.state.pricingBatch.lastReceipt {
                resultsSection(receipt)
            }
            auditHistorySection
        }
        .navigationTitle(t("Pricing Preview", "费用预览"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t("Done", "完成")) { dismiss() }
            }
            if canRollback {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        confirmation = .rollback
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel(Text(t("Roll Back", "回滚")))
                }
            }
            if !viewModel.state.pricingBatch.auditHistory.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: prepareAuditExport) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text(t("Export Audit CSV", "导出审计记录")))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                confirmation = .apply
            } label: {
                if viewModel.state.pricingBatch.isApplying {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(applyButtonTitle, systemImage: "arrow.up.doc")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedCount == 0 || isBusy)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .alert(confirmationTitle, isPresented: confirmationBinding) {
            Button(t("Cancel", "取消"), role: .cancel) { confirmation = nil }
            Button(confirmationActionTitle, role: confirmation == .rollback ? .destructive : nil) {
                let action = confirmation
                confirmation = nil
                Task {
                    if action == .rollback {
                        await viewModel.rollbackLastPricingBatch()
                    } else {
                        await viewModel.applyPricingBatch()
                    }
                }
            }
        } message: {
            Text(confirmationMessage)
        }
        .fileExporter(
            isPresented: $exportsAudit,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "MateDrive-charge-cost-audit"
        ) { result in
            if case let .failure(error) = result {
                exportError = error.localizedDescription
            }
            exportDocument = nil
        }
        .alert(t("Export Failed", "导出失败"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(t("OK", "确定"), role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .task {
            viewModel.preparePricingBatchPreview()
        }
    }

    private var overviewSection: some View {
        Section(t("Pricing Rules", "费用规则")) {
            LabeledContent(t("Matched", "匹配记录"), value: "\(viewModel.state.pricingBatch.candidates.count)")
            LabeledContent(t("Selected", "已选择"), value: "\(selectedCount)")
            LabeledContent(t("Manual Costs Protected", "已保护手动费用"), value: "\(viewModel.state.pricingBatch.manualOverrideExcludedCount)")
            LabeledContent(t("Already Correct", "费用已正确"), value: "\(viewModel.state.pricingBatch.alreadyCorrectCount)")
            LabeledContent(t("No Matching Rule", "未匹配规则"), value: "\(viewModel.state.pricingBatch.unmatchedCount)")
            if let error = viewModel.state.pricingBatch.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let error = viewModel.state.pricingBatch.auditErrorMessage {
                Label(error, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var candidatesSection: some View {
        Section(t("Cost Changes", "费用变更")) {
            if viewModel.state.pricingBatch.candidates.isEmpty {
                ContentUnavailableView(
                    t("No pricing changes", "没有需要写入的费用"),
                    systemImage: "checkmark.circle"
                )
            } else {
                ForEach(viewModel.state.pricingBatch.candidates) { candidate in
                    Toggle(isOn: selectionBinding(candidate.chargeId)) {
                        candidateLabel(candidate)
                    }
                    .tint(candidate.changeKind == .replaceRecorded ? .orange : .accentColor)
                }
            }
        }
    }

    private func candidateLabel(_ candidate: ChargePricingBatchCandidate) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(candidate.address ?? dateText(candidate.startDate))
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Spacer()
                Text(costChange(candidate))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(candidate.changeKind == .replaceRecorded ? .orange : .primary)
            }
            Text("\(dateText(candidate.startDate)) · \(String(format: "%.1f kWh", candidate.energyKWh))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(
                candidate.changeKind == .fillMissing
                    ? t("Missing Cost", "补齐缺失费用")
                    : t("Replace Recorded Cost", "替换已有费用"),
                systemImage: candidate.changeKind == .fillMissing ? "plus.circle" : "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(candidate.changeKind == .replaceRecorded ? .orange : .secondary)
            Text("\(t("Rule", "规则")): \(candidate.ruleName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func resultsSection(_ receipt: ChargePricingBatchReceipt) -> some View {
        Section(t("Writeback Results", "写入结果")) {
            ForEach(receipt.results) { result in
                resultRow(
                    chargeId: result.chargeId,
                    succeeded: result.succeeded,
                    detail: "\(formatCost(result.previousCost)) → \(formatCost(result.newCost))",
                    message: result.message
                )
            }
            if let rollbackResults = receipt.rollbackResults {
                ForEach(rollbackResults) { result in
                    resultRow(
                        chargeId: result.chargeId,
                        succeeded: result.succeeded,
                        detail: "\(t("Restored", "已恢复")): \(formatCost(result.restoredCost))",
                        message: result.message
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var auditHistorySection: some View {
        if !viewModel.state.pricingBatch.auditHistory.isEmpty {
            Section(t("Audit History", "审计记录")) {
                ForEach(viewModel.state.pricingBatch.auditHistory) { record in
                    DisclosureGroup {
                        ForEach(record.receipt.results) { result in
                            resultRow(
                                chargeId: result.chargeId,
                                succeeded: result.succeeded,
                                detail: "\(auditCost(result.previousCost, currencyCode: record.currencyCode)) → \(auditCost(result.newCost, currencyCode: record.currencyCode))",
                                message: result.message
                            )
                        }
                        if let rollbackResults = record.receipt.rollbackResults {
                            ForEach(rollbackResults) { result in
                                resultRow(
                                    chargeId: result.chargeId,
                                    succeeded: result.succeeded,
                                    detail: "\(t("Restored", "已恢复")): \(auditCost(result.restoredCost, currencyCode: record.currencyCode))",
                                    message: result.message
                                )
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.receipt.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.body.weight(.medium))
                            Text(auditSummary(record))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func resultRow(chargeId: Int, succeeded: Bool, detail: String, message: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(succeeded ? .green : .red)
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(chargeId) · \(succeeded ? t("Succeeded", "成功") : t("Failed", "失败"))")
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let message {
                    Text(UserFacingErrorLocalizer.localized(message, language: appLanguage))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var selectedCount: Int {
        viewModel.state.pricingBatch.selectedChargeIDs.count
    }

    private var isBusy: Bool {
        viewModel.state.pricingBatch.isApplying || viewModel.state.pricingBatch.isRollingBack
    }

    private var canRollback: Bool {
        guard let receipt = viewModel.state.pricingBatch.lastReceipt,
              receipt.rollbackResults == nil
        else { return false }
        return receipt.results.contains(where: \.succeeded) && !isBusy
    }

    private var applyButtonTitle: String {
        "\(t("Write Selected Costs", "写入所选费用")) (\(selectedCount))"
    }

    private func selectionBinding(_ chargeId: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.state.pricingBatch.selectedChargeIDs.contains(chargeId) },
            set: { viewModel.setPricingBatchSelection(chargeId: chargeId, isSelected: $0) }
        )
    }

    private func costChange(_ candidate: ChargePricingBatchCandidate) -> String {
        "\(formatCost(candidate.previousCost)) → \(formatCost(candidate.estimatedCost))"
    }

    private func formatCost(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(viewModel.state.currencySymbol)\(String(format: "%.2f", value))"
    }

    private func auditCost(_ value: Double?, currencyCode: String) -> String {
        guard let value else { return "--" }
        let symbol = MateDroidCurrencyFormatter.symbol(for: currencyCode)
        return "\(symbol)\(String(format: "%.2f", value))"
    }

    private func auditSummary(_ record: ChargePricingAuditRecord) -> String {
        let succeeded = record.receipt.results.filter(\.succeeded).count
        let failed = record.receipt.results.count - succeeded
        let writeSummary = "\(succeeded) \(t("succeeded", "成功")) · \(failed) \(t("failed", "失败"))"
        guard let rollback = record.receipt.rollbackResults else { return writeSummary }
        return "\(writeSummary) · \(rollback.filter(\.succeeded).count)/\(rollback.count) \(t("rolled back", "已回滚"))"
    }

    private func prepareAuditExport() {
        exportDocument = ChargePricingAuditCSVDocument(
            csv: ChargePricingAuditCSVExporter.csv(records: viewModel.state.pricingBatch.auditHistory)
        )
        exportsAudit = true
    }

    private func dateText(_ value: String) -> String {
        guard let date = DomainDateParser.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var confirmationTitle: String {
        confirmation == .rollback ? t("Roll Back Costs?", "回滚费用？") : t("Write Costs?", "写入费用？")
    }

    private var confirmationActionTitle: String {
        confirmation == .rollback ? t("Roll Back", "回滚") : t("Write", "写入")
    }

    private var confirmationMessage: String {
        if confirmation == .rollback {
            return t("Restore the original TeslaMate API costs for every successful write?", "恢复本次成功写入记录原有的 TeslaMate API 费用？")
        }
        return t("Write the selected rule estimates to TeslaMate API? Existing API costs are changed only when explicitly selected.", "将所选规则估算写入 TeslaMate API？已有接口费用仅在明确勾选后才会更改。")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private enum Confirmation {
        case apply
        case rollback
    }
}

private struct ChargePricingAuditCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let csv: String

    init(csv: String) {
        self.csv = csv
    }

    init(configuration: ReadConfiguration) throws {
        csv = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }
}
