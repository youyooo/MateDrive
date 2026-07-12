import SwiftUI

public struct CarImageView: View {
    @Environment(\.appLanguage) private var appLanguage

    private let assetPath: String?
    private let scaleFactor: CGFloat
    private let displayScale: CGFloat
    private let fallbackSystemImage: String

    public init(
        assetPath: String?,
        scaleFactor: CGFloat = 1.0,
        displayScale: CGFloat = 1.0,
        fallbackSystemImage: String = "car.side.fill"
    ) {
        self.assetPath = assetPath
        self.scaleFactor = scaleFactor
        self.displayScale = displayScale
        self.fallbackSystemImage = fallbackSystemImage
    }

    public var body: some View {
        ZStack {
            if let image = UIImage.carImage(namedByPath: assetPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scaleFactor * displayScale)
                    .accessibilityLabel(Text(t("Vehicle image", "车辆图片")))
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: 72, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(t("Vehicle image unavailable", "车辆图片不可用")))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2.2, contentMode: .fit)
        .clipped()
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private extension UIImage {
    static func carImage(namedByPath assetPath: String?) -> UIImage? {
        guard let assetPath else {
            return nil
        }

        let fileName = URL(fileURLWithPath: assetPath).lastPathComponent
        let resourceName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension

        if let image = UIImage(named: resourceName) ?? UIImage(named: fileName) {
            return image
        }

        let ext = fileExtension.isEmpty ? "png" : fileExtension
        if let url = Bundle.main.url(forResource: resourceName, withExtension: ext, subdirectory: "CarImages") ??
            Bundle.main.url(forResource: resourceName, withExtension: ext) {
            return UIImage(contentsOfFile: url.path)
        }

        return nil
    }
}
