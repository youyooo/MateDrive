import WidgetKit

public protocol WidgetTimelineReloading: Sendable {
    func reloadTimelines(ofKind kind: String) async
}

public struct SystemWidgetTimelineReloader: WidgetTimelineReloading {
    public init() {}

    public func reloadTimelines(ofKind kind: String) async {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
