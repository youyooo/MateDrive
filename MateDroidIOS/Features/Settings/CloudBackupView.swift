import SwiftUI

@MainActor
public struct CloudBackupView: View {
    @Environment(\.appLanguage) private var appLanguage
    @StateObject private var viewModel: CloudBackupViewModel
    @State private var restoreCandidate: CloudBackupDescriptor?
    @State private var deleteCandidate: CloudBackupDescriptor?
    @State private var showsDeleteAllConfirmation = false

    public init(coordinator: any CloudBackupCoordinating) {
        _viewModel = StateObject(wrappedValue: CloudBackupViewModel(coordinator: coordinator))
    }

    public var body: some View {
        Form {
            statusSection
            backupSection
            if !viewModel.state.backups.isEmpty {
                deleteSection
            }
        }
        .navigationTitle(t("iCloud Backup", "iCloud 备份"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refreshRemote() }
                } label: {
                    if viewModel.state.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.state.operation != nil || viewModel.state.isRefreshing)
                .accessibilityLabel(t("Refresh Backups", "刷新备份"))
            }
        }
        .task {
            await viewModel.loadCached()
            await viewModel.refreshRemote()
        }
        .refreshable { await viewModel.refreshRemote() }
        .alert(
            t("Enable iCloud Backup?", "开启 iCloud 备份？"),
            isPresented: disclosureBinding
        ) {
            Button(t("Enable", "开启")) {
                Task { await viewModel.confirmDisclosureAndEnableAutomaticBackup() }
            }
            Button(t("Cancel", "取消"), role: .cancel) { viewModel.cancelDisclosure() }
        } message: {
            Text(t(
                "MateDrive stores the local database and non-secret settings in your private iCloud database. Server passwords, tokens, and API keys are never included.",
                "MateDrive 会把本地数据库和非敏感设置保存到你的私人 iCloud 数据库。服务器密码、令牌和接口密钥不会包含在备份中。"
            ))
        }
        .confirmationDialog(
            t("Restore this backup?", "恢复这份备份？"),
            isPresented: restoreConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let restoreCandidate {
                Button(t("Restore Backup", "恢复备份"), role: .destructive) {
                    Task { await viewModel.restore(restoreCandidate) }
                }
            }
            Button(t("Cancel", "取消"), role: .cancel) { restoreCandidate = nil }
        } message: {
            Text(t(
                "Current local data is protected by a safety snapshot and restored automatically if this operation fails.",
                "恢复前会先创建当前数据的安全快照；如果恢复失败，会自动还原。"
            ))
        }
        .confirmationDialog(
            t("Delete this backup?", "删除这份备份？"),
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let deleteCandidate {
                Button(t("Delete Backup", "删除备份"), role: .destructive) {
                    Task { await viewModel.delete(deleteCandidate) }
                }
            }
            Button(t("Cancel", "取消"), role: .cancel) { deleteCandidate = nil }
        }
        .confirmationDialog(
            t("Delete all iCloud backups?", "删除全部 iCloud 备份？"),
            isPresented: $showsDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("Delete All Backups", "删除全部备份"), role: .destructive) {
                Task { await viewModel.deleteAll() }
            }
            Button(t("Cancel", "取消"), role: .cancel) {}
        }
        .alert(
            t("Restore Complete", "恢复完成"),
            isPresented: credentialReminderBinding
        ) {
            Button(t("OK", "确定"), role: .cancel) { viewModel.dismissCredentialReminder() }
        } message: {
            Text(t(
                "Local data and settings were restored. Authentication secrets are not backed up; check the server credentials before the next refresh.",
                "本地数据和设置已恢复。认证密钥不会进入备份，请在下次刷新前检查服务器凭据。"
            ))
        }
        .alert(t("iCloud Backup Error", "iCloud 备份错误"), isPresented: errorBinding) {
            Button(t("OK", "确定"), role: .cancel) { viewModel.dismissError() }
        } message: {
            Text(localizedError(viewModel.state.error))
        }
    }

    private var statusSection: some View {
        Section(t("Status", "状态")) {
            LabeledContent(t("iCloud Account", "iCloud 账户")) {
                Label(accountStatusText, systemImage: accountStatusIcon)
                    .foregroundStyle(accountStatusColor)
            }
            Toggle(
                t("Automatic Backup", "自动备份"),
                isOn: Binding(
                    get: { viewModel.state.preferences.isAutomaticBackupEnabled },
                    set: { value in Task { await viewModel.requestAutomaticBackup(value) } }
                )
            )
            .disabled(viewModel.state.operation != nil)
            if let lastBackup = viewModel.state.preferences.lastSuccessfulBackupAt {
                LabeledContent(t("Last Successful Backup", "上次成功备份")) {
                    Text(lastBackup, format: .dateTime.year().month().day().hour().minute())
                }
            }
            if let warning = viewModel.state.cleanupWarning {
                Label(localizedError(warning), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var backupSection: some View {
        Section(t("Backups", "备份")) {
            Button {
                Task { await viewModel.createManualBackup() }
            } label: {
                Label(
                    viewModel.state.operation == .creatingBackup
                        ? t("Creating Backup", "正在创建备份")
                        : t("Back Up Now", "立即备份"),
                    systemImage: "icloud.and.arrow.up"
                )
            }
            .disabled(viewModel.state.operation != nil || viewModel.state.isRefreshing)

            if viewModel.state.backups.isEmpty {
                ContentUnavailableView(
                    t("No Backups", "暂无备份"),
                    systemImage: "icloud",
                    description: Text(t("Your successful backups will appear here.", "成功创建的备份会显示在这里。"))
                )
            } else {
                ForEach(viewModel.state.backups) { backup in
                    Button { restoreCandidate = backup } label: {
                        backupRow(backup)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.state.operation != nil)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deleteCandidate = backup } label: {
                            Label(t("Delete", "删除"), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(t("Delete All Backups", "删除全部备份"), role: .destructive) {
                showsDeleteAllConfirmation = true
            }
            .disabled(viewModel.state.operation != nil)
        }
    }

    private func backupRow(_ backup: CloudBackupDescriptor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: backup.kind == .automatic ? "clock.arrow.circlepath" : "icloud.fill")
                .foregroundStyle(.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.body.weight(.medium))
                Text("\(backupKindText(backup.kind)) · MateDrive \(backup.appVersion) · \(formattedBytes(backup.databaseByteCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if viewModel.state.operation == .restoring(backup.id) {
                ProgressView()
            } else {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var disclosureBinding: Binding<Bool> {
        Binding(
            get: { viewModel.state.showsDisclosure },
            set: { if !$0 { viewModel.cancelDisclosure() } }
        )
    }

    private var restoreConfirmationBinding: Binding<Bool> {
        Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    private var credentialReminderBinding: Binding<Bool> {
        Binding(
            get: { viewModel.state.showsCredentialReminder },
            set: { if !$0 { viewModel.dismissCredentialReminder() } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.state.error != nil }, set: { if !$0 { viewModel.dismissError() } })
    }

    private var accountStatusText: String {
        switch viewModel.state.accountStatus {
        case .available: t("Available", "可用")
        case .noAccount: t("Not Signed In", "未登录")
        case .restricted: t("Restricted", "受限")
        case .unavailable: t("Unavailable", "暂不可用")
        case nil: t("Checking", "正在检查")
        }
    }

    private var accountStatusIcon: String {
        viewModel.state.accountStatus == .available ? "checkmark.circle.fill" : "icloud.slash"
    }

    private var accountStatusColor: Color {
        viewModel.state.accountStatus == .available ? .green : .secondary
    }

    private func backupKindText(_ kind: CloudBackupKind) -> String {
        kind == .automatic ? t("Automatic", "自动") : t("Manual", "手动")
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func localizedError(_ error: CloudBackupError?) -> String {
        guard let error else { return "" }
        return switch error {
        case .disclosureRequired: t("Please accept the iCloud backup notice first.", "请先同意 iCloud 备份说明。")
        case .automaticBackupDisabled: t("Automatic backup is disabled.", "自动备份已关闭。")
        case .operationInProgress: t("Another backup operation is in progress.", "另一项备份操作正在进行。")
        case .noICloudAccount: t("Sign in to iCloud in iOS Settings and try again.", "请先在 iOS 系统设置中登录 iCloud，然后重试。")
        case .iCloudUnavailable: t("iCloud is temporarily unavailable.", "iCloud 暂时不可用。")
        case .quotaExceeded: t("Your iCloud storage is full.", "你的 iCloud 储存空间已满。")
        case .rateLimited: t("iCloud is busy. Try again later.", "iCloud 当前繁忙，请稍后重试。")
        case .incompatibleFormat: t("This backup format is not supported.", "不支持这份备份的格式。")
        case .newerDatabaseSchema: t("This backup requires a newer MateDrive version.", "这份备份需要更新版本的 MateDrive。")
        case .invalidDatabaseSize, .invalidChecksum, .invalidDatabase, .invalidSettings:
            t("The backup is incomplete or damaged.", "备份不完整或已损坏。")
        case .recordNotFound: t("This backup no longer exists in iCloud.", "这份备份已不在 iCloud 中。")
        case .cancelled: t("The backup operation was cancelled.", "备份操作已取消。")
        case let .serviceFailure(message), let .restoreFailed(message), let .rollbackFailed(message): message
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
