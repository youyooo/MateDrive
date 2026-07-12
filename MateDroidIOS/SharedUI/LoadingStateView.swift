import SwiftUI

public struct LoadingStateView: View {
    @Environment(\.appLanguage) private var appLanguage

    private let title: String
    private let message: String?
    private let systemImage: String
    private let showsProgress: Bool
    private let retryTitle: String?
    private let retry: (() -> Void)?

    public init(
        title: String,
        message: String? = nil,
        systemImage: String = "gauge.with.dots.needle.bottom.50percent",
        showsProgress: Bool = false,
        retryTitle: String? = nil,
        retry: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.showsProgress = showsProgress
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 14) {
            if showsProgress {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let message, !message.isEmpty {
                    Text(LocalizedStringKey(UserFacingErrorLocalizer.localized(message, language: appLanguage)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let retryTitle, let retry {
                Button(LocalizedStringKey(retryTitle), action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(24)
    }
}

public struct FeatureUnavailableView: View {
    @Environment(\.appLanguage) private var appLanguage

    private let routeTitle: String?
    private let route: AppRoute?

    public init(routeTitle: String) {
        self.routeTitle = routeTitle
        self.route = nil
    }

    public init(route: AppRoute) {
        self.routeTitle = nil
        self.route = route
    }

    public var body: some View {
        LoadingStateView(
            title: resolvedRouteTitle,
            message: t("This feature is temporarily unavailable.", "此功能暂时不可用。"),
            systemImage: "hammer"
        )
        .navigationTitle(resolvedRouteTitle)
    }

    private var resolvedRouteTitle: String {
        if let route {
            return route.title(language: appLanguage)
        }
        return routeTitle ?? ""
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
