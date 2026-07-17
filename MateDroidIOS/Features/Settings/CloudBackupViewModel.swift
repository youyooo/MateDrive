import SwiftUI

public enum CloudBackupViewOperation: Equatable, Sendable {
    case creatingBackup
    case restoring(String)
    case deleting(String)
    case deletingAll
}

public struct CloudBackupViewState: Equatable, Sendable {
    public var accountStatus: CloudBackupAccountStatus?
    public var preferences = CloudBackupPreferences()
    public var backups: [CloudBackupDescriptor] = []
    public var operation: CloudBackupViewOperation?
    public var isRefreshing = false
    public var showsDisclosure = false
    public var showsCredentialReminder = false
    public var error: CloudBackupError?
    public var cleanupWarning: CloudBackupError?

    public init() {}
}

@MainActor
public final class CloudBackupViewModel: ObservableObject {
    @Published public private(set) var state = CloudBackupViewState()

    private let coordinator: any CloudBackupCoordinating

    public init(coordinator: any CloudBackupCoordinating) {
        self.coordinator = coordinator
    }

    public func loadCached() async {
        state.preferences = await coordinator.preferences()
        do {
            state.backups = try await coordinator.listBackups(forceRefresh: false)
        } catch {
            state.error = Self.map(error)
        }
    }

    public func refreshRemote() async {
        guard state.operation == nil, !state.isRefreshing else { return }
        state.isRefreshing = true
        defer { state.isRefreshing = false }

        do {
            let newStatus = try await coordinator.accountStatus()
            state.accountStatus = newStatus
            state.preferences = await coordinator.preferences()
            state.cleanupWarning = await coordinator.cleanupWarning()
            guard newStatus == .available else {
                state.error = nil
                return
            }

            state.backups = try await coordinator.listBackups(forceRefresh: true)
            state.error = nil
        } catch {
            let mapped = Self.map(error)
            switch mapped {
            case .noICloudAccount:
                state.accountStatus = .noAccount
                state.error = nil
            case .iCloudUnavailable:
                state.accountStatus = .unavailable
                state.error = nil
            default:
                state.error = mapped
            }
        }
    }

    public func requestAutomaticBackup(_ isEnabled: Bool) async {
        guard state.operation == nil else { return }
        if isEnabled, !state.preferences.hasAcceptedDisclosure {
            state.showsDisclosure = true
            return
        }
        await applyAutomaticBackup(isEnabled)
    }

    public func confirmDisclosureAndEnableAutomaticBackup() async {
        guard state.operation == nil else { return }
        await coordinator.acceptDisclosure()
        state.showsDisclosure = false
        await applyAutomaticBackup(true)
    }

    public func cancelDisclosure() {
        state.showsDisclosure = false
    }

    public func createManualBackup() async {
        guard state.operation == nil, !state.isRefreshing else { return }
        if !state.preferences.hasAcceptedDisclosure {
            state.showsDisclosure = true
            return
        }
        state.operation = .creatingBackup
        defer { state.operation = nil }
        do {
            _ = try await coordinator.createManualBackup()
            state.backups = try await coordinator.listBackups(forceRefresh: false)
            state.preferences = await coordinator.preferences()
            state.cleanupWarning = await coordinator.cleanupWarning()
            state.error = nil
        } catch {
            state.error = Self.map(error)
        }
    }

    public func restore(_ descriptor: CloudBackupDescriptor) async {
        guard state.operation == nil, !state.isRefreshing else { return }
        state.operation = .restoring(descriptor.id)
        defer { state.operation = nil }
        do {
            try await coordinator.restore(descriptor)
            state.showsCredentialReminder = true
            state.error = nil
        } catch {
            state.error = Self.map(error)
        }
    }

    public func delete(_ descriptor: CloudBackupDescriptor) async {
        guard state.operation == nil, !state.isRefreshing else { return }
        state.operation = .deleting(descriptor.id)
        defer { state.operation = nil }
        do {
            try await coordinator.delete(descriptor)
            state.backups = try await coordinator.listBackups(forceRefresh: false)
            state.preferences = await coordinator.preferences()
            state.error = nil
        } catch {
            state.error = Self.map(error)
        }
    }

    public func deleteAll() async {
        guard state.operation == nil, !state.isRefreshing else { return }
        state.operation = .deletingAll
        defer { state.operation = nil }
        do {
            try await coordinator.deleteAll()
            state.backups = []
            state.preferences = await coordinator.preferences()
            state.error = nil
        } catch {
            state.error = Self.map(error)
        }
    }

    public func dismissCredentialReminder() {
        state.showsCredentialReminder = false
    }

    public func dismissError() {
        state.error = nil
    }

    private func applyAutomaticBackup(_ isEnabled: Bool) async {
        do {
            try await coordinator.setAutomaticBackupEnabled(isEnabled)
            state.preferences = await coordinator.preferences()
            state.error = nil
        } catch {
            state.preferences = await coordinator.preferences()
            state.error = Self.map(error)
        }
    }

    private static func map(_ error: Error) -> CloudBackupError {
        if let error = error as? CloudBackupError { return error }
        if error is CancellationError { return .cancelled }
        return .serviceFailure(error.localizedDescription)
    }
}
