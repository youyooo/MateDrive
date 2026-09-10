import Foundation

public enum AppLinks {
    public static let supportURLString = "https://youyooo.github.io/MateDrive/"
    public static let privacyPolicyURLString = "https://youyooo.github.io/MateDrive/privacy.html"

    public static var supportURL: URL? {
        URL(string: supportURLString)
    }

    public static var privacyPolicyURL: URL? {
        URL(string: privacyPolicyURLString)
    }
}
