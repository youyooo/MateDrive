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
    private let settingsStore: (any SettingsStoring)?
    private let calendar: Calendar
    private var currentCarId: Int?
    private var pendingReloadCarId: Int?
    private var pendingReloadIncludesIndexChange = false
    private var indexReloadInFlightOrPending = false
    private var indexReloadSucceededSinceCacheRevision = false
    private var lastConsumedCacheRevision: Int?
    private var loadGeneration = 0
    private var reloadTask: Task<Void, Never>?
    private var indexObservation: ActivityTimelineNotificationObservation?

    public init(
        sessionStore: any SmartActivitySessionStoring,
        settingsStore: (any SettingsStoring)? = nil,
        calendar: Calendar = .current,
        notificationCenter: NotificationCenter = .default
    ) {
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
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

    public func placeName(for session: SmartActivitySession) -> String? {
        guard let geofenceID = session.geofenceID else { return nil }
        return geofenceNames[geofenceID]
    }

    public func session(id: String) -> SmartActivitySession? {
        state.sessions.first { $0.id == id }
    }

    private var geofenceNames: [String: String] = [:]

    public func load(carId: Int, cacheRevision: Int? = nil) async {
        if let settingsStore {
            let settings = await settingsStore.load()
            geofenceNames = Dictionary(uniqueKeysWithValues: settings.geofenceRules.compactMap { rule in
                let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return rule.isEnabled && !name.isEmpty ? (rule.id, name) : nil
            })
        }
        loadGeneration += 1
        let generation = loadGeneration
        let carChanged = currentCarId != nil && currentCarId != carId
        if carChanged {
            state.sessions = []
            state.errorMessage = nil
            lastConsumedCacheRevision = nil
            indexReloadSucceededSinceCacheRevision = false
        }
        currentCarId = carId

        if let cacheRevision, !carChanged {
            if indexReloadInFlightOrPending, let reloadTask {
                await reloadTask.value
                if currentCarId == carId, state.errorMessage == nil {
                    lastConsumedCacheRevision = cacheRevision
                    indexReloadSucceededSinceCacheRevision = false
                    return
                }
            }
            if indexReloadSucceededSinceCacheRevision {
                lastConsumedCacheRevision = cacheRevision
                indexReloadSucceededSinceCacheRevision = false
                return
            }
            if lastConsumedCacheRevision == cacheRevision {
                return
            }
        }

        if reloadTask == nil, pendingReloadCarId == nil {
            do {
                let sessions = try await sessionStore.sessions(carId: carId)
                guard currentCarId == carId, generation == loadGeneration else { return }
                publishSessions(sessions)
            } catch {
                guard currentCarId == carId, generation == loadGeneration else { return }
                state.errorMessage = "activity_timeline_local_error"
            }
        } else {
            let task = enqueueReload(carId: carId)
            await task.value
        }
        if currentCarId == carId, state.errorMessage == nil, let cacheRevision {
            lastConsumedCacheRevision = cacheRevision
            indexReloadSucceededSinceCacheRevision = false
        }
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
        loadGeneration += 1
        _ = enqueueReload(carId: currentCarId, includesIndexChange: true)
    }

    private func enqueueReload(
        carId: Int,
        includesIndexChange: Bool = false
    ) -> Task<Void, Never> {
        pendingReloadCarId = carId
        pendingReloadIncludesIndexChange = pendingReloadIncludesIndexChange || includesIndexChange
        indexReloadInFlightOrPending = indexReloadInFlightOrPending || includesIndexChange
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
            let includesIndexChange = pendingReloadIncludesIndexChange
            pendingReloadIncludesIndexChange = false
            do {
                let sessions = try await sessionStore.sessions(carId: carId)
                guard currentCarId == carId else { continue }
                publishSessions(sessions)
                if includesIndexChange {
                    indexReloadSucceededSinceCacheRevision = true
                }
            } catch {
                guard currentCarId == carId else { continue }
                state.errorMessage = "activity_timeline_local_error"
            }
        }
        indexReloadInFlightOrPending = false
        reloadTask = nil
    }

    private func publishSessions(_ sessions: [SmartActivitySession]) {
        var updatedState = state
        updatedState.sessions = Self.newestFirst(sessions)
        updatedState.errorMessage = nil
        guard updatedState != state else { return }
        state = updatedState
    }

    private static func newestFirst(_ sessions: [SmartActivitySession]) -> [SmartActivitySession] {
        guard sessions.count > 1 else { return sessions }
        let isAlreadyOrdered = sessions.indices.dropFirst().allSatisfy { index in
            let previous = sessions[sessions.index(before: index)]
            let current = sessions[index]
            if previous.startDate == current.startDate {
                return previous.id <= current.id
            }
            return previous.startDate > current.startDate
        }
        if isAlreadyOrdered { return sessions }

        return sessions.sorted {
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
        labelStore: (any ActivityLabelOverrideStoring)? = nil,
        initialSession: SmartActivitySession? = nil
    ) {
        self.sessionStore = sessionStore
        self.labelStore = labelStore
        session = initialSession
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
                if session?.carId != carId || session?.id != sessionId {
                    session = nil
                }
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
            if session?.carId != carId || session?.id != sessionId {
                session = nil
            }
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
