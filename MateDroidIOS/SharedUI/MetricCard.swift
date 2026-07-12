import SwiftUI

public struct MetricCard: View {
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint ?? .accentColor)
                    .frame(width: 20, height: 20)
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(verbatim: value)
                .font(.title3.weight(.semibold))
                .lineLimit(valueLineLimit)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: valueLineLimit > 1)

            if let subtitle, !subtitle.isEmpty {
                Text(LocalizedStringKey(subtitle))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
    }
}
