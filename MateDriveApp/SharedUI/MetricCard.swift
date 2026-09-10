import SwiftUI

public struct MetricCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var decorativeIconSize: CGFloat = 20

    private let title: String
    private let value: String
    private let subtitle: String?
    private let systemImage: String
    private let tint: Color?
    private let valueLineLimit: Int

    public init(title: String, value: String, subtitle: String? = nil, systemImage: String, tint: Color? = nil, valueLineLimit: Int = 1) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.valueLineLimit = max(valueLineLimit, 1)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: decorativeIconSize, weight: .semibold))
                    .foregroundStyle(tint ?? .accentColor)
                    .frame(
                        minWidth: decorativeIconSize,
                        minHeight: decorativeIconSize
                    )
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                    .fixedSize(
                        horizontal: false,
                        vertical: dynamicTypeSize.isAccessibilitySize
                    )
            }

            Text(verbatim: value)
                .font(.title3.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : valueLineLimit)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                .fixedSize(
                    horizontal: false,
                    vertical: dynamicTypeSize.isAccessibilitySize || valueLineLimit > 1
                )

            if let subtitle, !subtitle.isEmpty {
                Text(LocalizedStringKey(subtitle))
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

struct HistoryHistogramBar: View {
    let color: Color
    let height: CGFloat
    let width: CGFloat

    init(color: Color, height: CGFloat, width: CGFloat = 44) {
        self.color = color
        self.height = height
        self.width = width
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
    }
}
