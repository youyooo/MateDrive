import Combine
import Foundation

public enum ActivityTimelineFilter: String, CaseIterable, Sendable {
    case all
    case drive
    case charge
    case park
}

public struct ActivityTimelineState: Equatable, Sendable {
    public var sessions: [SmartActivitySession] = []
    public var filter: ActivityTimelineFilter = .all
    public var errorMessage: String?
    public var isLoading = false

    public init() {}
}

public struct ActivityTimelineDaySection: Identifiable, Equatable, Sendable {
    public let day: Date
    public let sessions: [SmartActivitySession]

    public var id: Date { day }

    public init(day: Date, sessions: [SmartActivitySession]) {
        self.day = day
        self.sessions = sessions
    }
}

@MainActor
public final class ActivityTimelineViewModel: ObservableObject {
    @Published public private(set) var state = ActivityTimelineState()

    private let sessionStore: any SmartActivitySessionStoring
    private let calendar: Calendar
    private var currentCarId: Int?
    private var pendingReloadCarId: Int?
    private var reloadTask: Task<Void, Never>?
    private var indexObservation: ActivityTimelineNotificationObservation?

    public init(
        sessionStore: any SmartActivitySessionStoring,
        calendar: Calendar = .current,
        notificationCenter: NotificationCenter = .default
    ) {
        self.sessionStore = sessionStore
        self.calendar = calendar
        indexObservation = ActivityTimelineNotificationObservation(
            center: notificationCenter,
            name: .smartActivityIndexDidChange
        ) { [weak self] changedCarId in
            MainActor.assumeIsolated {
                self?.activityIndexDidChange(carId: changedCarId)
            }
        }
    }

    public var filteredSessions: [SmartActivitySession] {
        guard state.filter != .all else { return state.sessions }
        return state.sessions.filter { session in
            switch state.filter {
            case .all:
                return true
            case .drive:
                return session.eventReferences.contains { $0.kind == .drive }
            case .charge:
                return session.eventReferences.contains { $0.kind == .charge }
            case .park:
                return session.eventReferences.contains { $0.kind == .park }
                    || session.provisionalKind == .parking
                    || session.classification?.purpose == .parking
            }
        }
    }

    public var daySections: [ActivityTimelineDaySection] {
        let grouped = Dictionary(grouping: filteredSessions) {
            calendar.startOfDay(for: $0.startDate)
        }
        return grouped.keys.sorted(by: >).map { day in
            ActivityTimelineDaySection(
                day: day,
                sessions: Self.newestFirst(grouped[day] ?? [])
            )
        }
    }

    public func load(carId: Int) async {
        if let currentCarId, currentCarId != carId {
            state.sessions = []
            state.errorMessage = nil
        }
        currentCarId = carId
        let task = enqueueReload(carId: carId)
        await task.value
    }

    public func setFilter(_ filter: ActivityTimelineFilter) {
        state.filter = filter
    }

    func waitUntilIdle() async {
        while let reloadTask {
            await reloadTask.value
        }
    }

    private func activityIndexDidChange(carId changedCarId: Int?) {
        guard let currentCarId else { return }
        if let changedCarId, changedCarId != currentCarId { return }
        _ = enqueueReload(carId: currentCarId)
    }

    private func enqueueReload(carId: Int) -> Task<Void, Never> {
        pendingReloadCarId = carId
        if let reloadTask { return reloadTask }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainReloads()
        }
        reloadTask = task
        return task
    }

    private func drainReloads() async {
        while let carId = pendingReloadCarId {
            pendingReloadCarId = nil
            do {
                let sessions = try await sessionStore.sessions(carId: carId)
                guard currentCarId == carId else { continue }
                state.sessions = Self.newestFirst(sessions)
                state.errorMessage = nil
            } catch {
                guard currentCarId == carId else { continue }
                state.errorMessage = "activity_timeline_local_error"
            }
        }
        reloadTask = nil
    }

    private static func newestFirst(_ sessions: [SmartActivitySession]) -> [SmartActivitySession] {
        sessions.sorted {
            if $0.startDate == $1.startDate {
                return $0.id < $1.id
            }
            return $0.startDate > $1.startDate
        }
    }
}

@MainActor
public final class ActivitySessionDetailViewModel: ObservableObject {
    @Published public private(set) var session: SmartActivitySession?
    @Published public private(set) var labelOverride: ActivityLabelOverride?
    @Published public private(set) var errorMessage: String?

    private let sessionStore: any SmartActivitySessionStoring
    private let labelStore: (any ActivityLabelOverrideStoring)?
    private var loadGeneration = 0

    public init(
        sessionStore: any SmartActivitySessionStoring,
        labelStore: (any ActivityLabelOverrideStoring)? = nil
    ) {
        self.sessionStore = sessionStore
        self.labelStore = labelStore
    }

    public func load(carId: Int, sessionId: String) async {
        loadGeneration += 1
        let generation = loadGeneration

        do {
            guard let loadedSession = try await sessionStore.session(
                carId: carId,
                sessionId: sessionId
            ) else {
                guard generation == loadGeneration else { return }
                session = nil
                labelOverride = nil
                errorMessage = "activity_session_missing"
                return
            }

            let loadedLabelOverride = try await loadLabelOverride(
                carId: carId,
                sessionId: sessionId
            )
            guard generation == loadGeneration else { return }
            session = loadedSession
            labelOverride = loadedLabelOverride
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            session = nil
            labelOverride = nil
            errorMessage = "activity_session_local_error"
        }
    }

    private func loadLabelOverride(
        carId: Int,
        sessionId: String
    ) async throws -> ActivityLabelOverride? {
        guard let labelStore else { return nil }
        let overrides = try await labelStore.overrides(carId: carId)

        return overrides
            .filter { $0.sessionId == sessionId }
            .sorted {
                if $0.updatedAt == $1.updatedAt { return $0.id < $1.id }
                return $0.updatedAt > $1.updatedAt
            }
            .first
    }
}

private final class ActivityTimelineNotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    init(
        center: NotificationCenter,
        name: Notification.Name,
        handler: @escaping @Sendable (Int?) -> Void
    ) {
        self.center = center
        token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            handler(notification.userInfo?["carId"] as? Int)
        }
    }

    deinit {
        if let token {
            center.removeObserver(token)
        }
    }
}
