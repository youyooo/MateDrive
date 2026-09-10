import SwiftUI

enum ListMapViewMode: String {
    case list
    case map

    var toggleDestination: Self {
        self == .list ? .map : .list
    }

    var toolbarSystemImage: String {
        self == .list ? "map" : "list.bullet"
    }
}

struct ListMapToolbarButton: View {
    @Binding var mode: ListMapViewMode
    let showListLabel: String
    let showMapLabel: String

    private var actionLabel: String {
        mode == .list ? showMapLabel : showListLabel
    }

    var body: some View {
        Button {
            mode = mode.toggleDestination
        } label: {
            Image(systemName: mode.toolbarSystemImage)
        }
        .accessibilityLabel(Text(actionLabel))
        .help(actionLabel)
    }
}

/// Keeps a map from taking over a parent scroll view until the user explicitly activates it.
struct MapGestureGate<Content: View>: View {
    @Environment(\.appLanguage) private var appLanguage
    @State private var isMapInteractionEnabled = false
    @State private var autoLockTask: Task<Void, Never>?
    @State private var resetGeneration = 0

    private let onAutoLock: () -> Void
    private let content: (Bool) -> Content

    init(
        onAutoLock: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Bool) -> Content
    ) {
        self.onAutoLock = onAutoLock
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content(isMapInteractionEnabled)
                .id(resetGeneration)
                .allowsHitTesting(isMapInteractionEnabled)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            guard isMapInteractionEnabled else { return }
                            scheduleAutoLock()
                        },
                    isEnabled: isMapInteractionEnabled
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { _ in
                            guard isMapInteractionEnabled else { return }
                            scheduleAutoLock()
                        },
                    isEnabled: isMapInteractionEnabled
                )

            if isMapInteractionEnabled {
                Button {
                    lockMap(shouldReset: true)
                } label: {
                    Image(systemName: "lock.open")
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                .padding(10)
                .accessibilityLabel(t("Lock map and resume page scrolling", "锁定地图并恢复页面滚动"))
                .help(t("Lock map", "锁定地图"))
            } else {
                Button {
                    activateMap()
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("Activate map interaction", "启用地图交互"))
                .accessibilityHint(t(
                    "After activation, drag or zoom the map. Page scrolling resumes three seconds after the last map gesture.",
                    "启用后可拖动或缩放地图，最后一次地图操作三秒后恢复页面滚动。"
                ))

                Image(systemName: "hand.draw.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .allowsHitTesting(false)
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .onDisappear {
            autoLockTask?.cancel()
            autoLockTask = nil
            isMapInteractionEnabled = false
        }
    }

    private func activateMap() {
        autoLockTask?.cancel()
        autoLockTask = nil
        isMapInteractionEnabled = true
    }

    private func scheduleAutoLock() {
        autoLockTask?.cancel()
        autoLockTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            lockMap(shouldReset: true)
        }
    }

    private func lockMap(shouldReset: Bool) {
        autoLockTask?.cancel()
        autoLockTask = nil
        isMapInteractionEnabled = false
        if shouldReset {
            resetGeneration &+= 1
            onAutoLock()
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
