import SwiftUI

public struct TripTimelineView: View {
    public let segments: [TripTimelineSegment]
    public let compact: Bool
    public let language: AppLanguage

    public init(segments: [TripTimelineSegment], compact: Bool = false, language: AppLanguage = .system) {
        self.segments = segments
        self.compact = compact
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        let label = segment.displayLabel(language: language)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(for: segment.kind))
                            .frame(width: width(for: segment, totalWidth: proxy.size.width), height: compact ? 10 : 18)
                            .accessibilityLabel("\(label), \(segment.kind.title(language: language)), \(durationText(segment.durationMin))")
                    }
                }
            }
            .frame(height: compact ? 10 : 18)

            if !compact {
                ForEach(segments) { segment in
                    let label = segment.displayLabel(language: language)
                    HStack {
                        Circle()
                            .fill(color(for: segment.kind))
                            .frame(width: 8, height: 8)
                        Text(label)
                            .font(.caption.weight(.semibold))
                        Text(segment.kind.title(language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(durationText(segment.durationMin))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var totalDuration: Int {
        max(segments.reduce(0) { $0 + max($1.durationMin, 1) }, 1)
    }

    private func width(for segment: TripTimelineSegment, totalWidth: CGFloat) -> CGFloat {
        let ratio = CGFloat(max(segment.durationMin, 1)) / CGFloat(totalDuration)
        return max(4, totalWidth * ratio)
    }

    private func durationText(_ value: Int) -> String {
        MateDriveUnitFormatter.formatDuration(minutes: value, language: language)
    }

    private func color(for kind: TripTimelineSegmentKind) -> Color {
        switch kind {
        case .drive:
            return .accentColor
        case .dcCharge:
            return .orange
        case .acCharge:
            return .green
        case .parking:
            return .gray.opacity(0.55)
        }
    }
}

public extension TripTimelineSegmentKind {
    func title(language: AppLanguage) -> String {
        switch self {
        case .drive:
            return AppText.localized(rawValue, "行程", language: language)
        case .dcCharge:
            return AppText.localized(rawValue, "直流充电", language: language)
        case .acCharge:
            return AppText.localized(rawValue, "交流充电", language: language)
        case .parking:
            return AppText.localized(rawValue, "停放", language: language)
        }
    }
}
