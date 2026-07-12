import XCTest
import UIKit
@testable import MateDroidIOS

final class AppStoreReadinessTests: XCTestCase {
    func testAppInfoPlistDeclaresBackgroundRefreshForScheduledSync() throws {
        let plist = try loadPlist("MateDroidIOS/Info.plist")

        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "MateDrive")
        XCTAssertEqual(plist["CFBundleName"] as? String, "$(PRODUCT_NAME)")
        XCTAssertEqual(plist["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertTrue((plist["UIBackgroundModes"] as? [String])?.contains("fetch") == true)
    }

    func testLaunchScreenUsesPackagedBrandAssets() throws {
        let plist = try loadPlist("MateDroidIOS/Info.plist")
        let launch = try XCTUnwrap(plist["UILaunchScreen"] as? [String: Any])
        let assetRoot = repositoryRoot().appendingPathComponent("MateDroidIOS/Resources/Assets.xcassets")

        XCTAssertEqual(launch["UIColorName"] as? String, "LaunchBackground")
        XCTAssertEqual(launch["UIImageName"] as? String, "LaunchWordmark")
        XCTAssertEqual(launch["UIImageRespectsSafeAreaInsets"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetRoot.appendingPathComponent("LaunchBackground.colorset/Contents.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetRoot.appendingPathComponent("LaunchWordmark.imageset/LaunchMark@3x.png").path))
    }

    func testAppVersionAndBuildAreAppStoreCompatible() throws {
        let plist = try loadPlist("MateDroidIOS/Info.plist")
        let shortVersion = try XCTUnwrap(plist["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(plist["CFBundleVersion"] as? String)

        XCTAssertTrue(Self.isDottedNumericVersion(shortVersion), "CFBundleShortVersionString must be dotted numeric")
        XCTAssertTrue(Self.isDottedNumericVersion(build), "CFBundleVersion must be dotted numeric")
    }

    func testBackgroundRefreshIdentifierIsAlignedAcrossAppConfigAndScheduler() throws {
        let plist = try loadPlist("MateDroidIOS/Info.plist")
        let identifiers = try XCTUnwrap(plist["BGTaskSchedulerPermittedIdentifiers"] as? [String])
        let projectYAML = try loadText("project.yml")

        XCTAssertEqual(BackgroundSyncScheduler.syncTaskIdentifier, "com.matedrive.ios.sync")
        XCTAssertEqual(identifiers, [BackgroundSyncScheduler.syncTaskIdentifier])
        XCTAssertTrue(projectYAML.contains("- \(BackgroundSyncScheduler.syncTaskIdentifier)"))
    }

    func testLiveEnvironmentIsNotLabeledAsDevelopment() {
        XCTAssertEqual(AppEnvironment.live.buildLabel, "production")
    }

    func testDebugLocalTeslaMateSeederIsCompileTimeDebugOnly() throws {
        let seederSource = try loadText("MateDroidIOS/App/DebugLocalTeslamateSeeder.swift")
        let rootViewSource = try loadText("MateDroidIOS/App/RootView.swift")

        XCTAssertTrue(seederSource.contains("#if DEBUG"))
        XCTAssertTrue(seederSource.contains("#endif"))
        XCTAssertTrue(rootViewSource.contains("#if DEBUG"))
        XCTAssertTrue(rootViewSource.contains("DebugLocalTeslamateSeeder.seedIfNeeded"))
    }

    func testProductionSourcesDoNotEmbedLocalTeslaMateDefaults() throws {
        let productionPaths = [
            "MateDroidIOS/App/AppEnvironment.swift",
            "MateDroidIOS/App/RootView.swift",
            "MateDroidIOS/Core/API/TeslamateAPI.swift",
            "MateDroidIOS/Info.plist",
            "MateDroidWidget/Info.plist",
            "project.yml"
        ]
        let forbiddenLocalEndpoints = ["127.0.0.1", "localhost"]

        for path in productionPaths {
            let text = try loadText(path)
            for endpoint in forbiddenLocalEndpoints {
                XCTAssertFalse(text.contains(endpoint), "\(path) must not embed \(endpoint) for production builds")
            }
        }
    }

    func testProductionSwiftSourcesDoNotUseForcedCrashPatterns() throws {
        let forbiddenPatterns = [
            "try!": "avoid forced throwing calls in production source",
            "as!": "avoid forced casts in production source",
            "fatalError(": "avoid unconditional crashes in production source",
            "preconditionFailure(": "avoid unconditional crashes in production source"
        ]
        let sourcePaths = try swiftSourcePaths(in: ["MateDroidIOS", "MateDroidWidget"])

        XCTAssertFalse(sourcePaths.isEmpty, "Expected production Swift sources to be discoverable")

        for path in sourcePaths {
            let text = try loadText(path)
            for (pattern, message) in forbiddenPatterns {
                XCTAssertFalse(text.contains(pattern), "\(path) must \(message): \(pattern)")
            }
        }
    }

    func testProductionConfigurationDoesNotUseLegacyMateDroidIdentifiers() throws {
        let productionConfigurationPaths = [
            "project.yml",
            "MateDroidIOS/Info.plist",
            "MateDroidWidget/Info.plist",
            "MateDroidIOS/MateDroidIOS.entitlements",
            "MateDroidWidget/MateDroidWidget.entitlements",
            "MateDroidIOS/Core/Sync/BackgroundSyncScheduler.swift",
            "MateDroidIOS/Core/Security/KeychainStore.swift",
            "MateDroidWidget/WidgetDisplayData.swift"
        ]

        for path in productionConfigurationPaths {
            let text = try loadText(path)
            XCTAssertFalse(text.contains("com.matedroid"), "\(path) must use com.matedrive identifiers for production")
            XCTAssertFalse(text.contains("MateDroid Widget"), "\(path) must use MateDrive widget branding")
            XCTAssertFalse(text.contains("<string>MateDroid</string>"), "\(path) must use MateDrive display branding")
        }
    }

    func testWidgetInfoPlistUsesMateDriveBranding() throws {
        let plist = try loadPlist("MateDroidWidget/Info.plist")
        let extensionInfo = try XCTUnwrap(plist["NSExtension"] as? [String: Any])

        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "MateDrive Widget")
        XCTAssertEqual(plist["CFBundleName"] as? String, "$(PRODUCT_NAME)")
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
    }

    func testXcodeProjectKeepsAppStoreVisibleBrandingAndPrivacyManifest() throws {
        let projectYAML = try loadText("project.yml")
        let projectFile = try loadText("MateDroidIOS.xcodeproj/project.pbxproj")

        XCTAssertTrue(projectYAML.contains("PRODUCT_NAME: MateDrive"))
        XCTAssertTrue(projectYAML.contains("schemes:\n  MateDrive:"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_MODULE_NAME: MateDroidIOS"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_BUNDLE_IDENTIFIER: com.matedrive.ios"))
        XCTAssertTrue(projectYAML.contains("INFOPLIST_KEY_CFBundleDisplayName: MateDrive"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_NAME: MateDriveWidget"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_MODULE_NAME: MateDroidWidget"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_BUNDLE_IDENTIFIER: com.matedrive.ios.widget"))
        XCTAssertTrue(projectYAML.contains("INFOPLIST_KEY_CFBundleDisplayName: MateDrive Widget"))
        XCTAssertTrue(projectYAML.contains("- path: MateDroidIOS/PrivacyInfo.xcprivacy"))
        XCTAssertTrue(projectYAML.contains(#"TEST_HOST: "$(BUILT_PRODUCTS_DIR)/MateDrive.app/MateDrive""#))
        XCTAssertTrue(projectFile.contains("PRODUCT_NAME = MateDrive"))
        XCTAssertTrue(projectFile.contains("PRODUCT_NAME = MateDriveWidget"))
        XCTAssertTrue(projectFile.contains("PRODUCT_MODULE_NAME = MateDroidIOS"))
        XCTAssertTrue(projectFile.contains("PRODUCT_MODULE_NAME = MateDroidWidget"))
        XCTAssertTrue(projectFile.contains("TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/MateDrive.app/MateDrive\""))
        XCTAssertTrue(projectFile.contains("PrivacyInfo.xcprivacy in Resources"))
        XCTAssertGreaterThanOrEqual(projectFile.components(separatedBy: "PrivacyInfo.xcprivacy in Resources").count - 1, 2)
        XCTAssertEqual(projectYAML.components(separatedBy: #"TARGETED_DEVICE_FAMILY: "1""#).count - 1, 2)
    }

    func testMakefileProvidesRepeatableReleaseArchiveAndTechnicalAudit() throws {
        let makefile = try loadText("Makefile")

        XCTAssertTrue(makefile.contains("archive-release:"))
        XCTAssertTrue(makefile.contains("SCHEME := MateDrive"))
        XCTAssertTrue(makefile.contains("xcodebuild archive"))
        XCTAssertTrue(makefile.contains("build/MateDrive.xcarchive"))
        XCTAssertTrue(makefile.contains("archive-audit:"))
        XCTAssertTrue(makefile.contains("audit_release_archive.py"))
        XCTAssertTrue(makefile.contains("app-store-technical-audit:"))
        XCTAssertTrue(makefile.contains("--technical-only"))
    }

    func testAppAndWidgetDeclareSameAppGroupForSharedWidgetSnapshot() throws {
        let appEntitlements = try loadPlist("MateDroidIOS/MateDroidIOS.entitlements")
        let widgetEntitlements = try loadPlist("MateDroidWidget/MateDroidWidget.entitlements")
        let appGroups = try XCTUnwrap(appEntitlements["com.apple.security.application-groups"] as? [String])
        let widgetGroups = try XCTUnwrap(widgetEntitlements["com.apple.security.application-groups"] as? [String])
        let projectYAML = try loadText("project.yml")
        let projectFile = try loadText("MateDroidIOS.xcodeproj/project.pbxproj")

        XCTAssertEqual(appGroups, [WidgetConstants.appGroupIdentifier])
        XCTAssertEqual(widgetGroups, [WidgetConstants.appGroupIdentifier])
        XCTAssertTrue(projectYAML.contains("CODE_SIGN_ENTITLEMENTS: MateDroidIOS/MateDroidIOS.entitlements"))
        XCTAssertTrue(projectYAML.contains("CODE_SIGN_ENTITLEMENTS: MateDroidWidget/MateDroidWidget.entitlements"))
        XCTAssertTrue(projectFile.contains("CODE_SIGN_ENTITLEMENTS = MateDroidIOS/MateDroidIOS.entitlements"))
        XCTAssertTrue(projectFile.contains("CODE_SIGN_ENTITLEMENTS = MateDroidWidget/MateDroidWidget.entitlements"))
    }

    func testInfoPlistDoesNotDeclareUnusedSensitivePermissions() throws {
        let plist = try loadPlist("MateDroidIOS/Info.plist")
        let unusedSensitivePermissionKeys = [
            "NSLocationWhenInUseUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription",
            "NSCameraUsageDescription",
            "NSPhotoLibraryUsageDescription",
            "NSContactsUsageDescription",
            "NSHealthShareUsageDescription",
            "NSUserTrackingUsageDescription"
        ]

        for key in unusedSensitivePermissionKeys {
            XCTAssertNil(plist[key], "Remove unused permission declaration: \(key)")
        }
    }

    func testPrivacyManifestDeclaresUserDefaultsRequiredReasonAndNoTracking() throws {
        let manifest = try loadPlist("MateDroidIOS/PrivacyInfo.xcprivacy")

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)

        let accessedAPIs = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = try XCTUnwrap(accessedAPIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }

    func testAppIconSetContainsRequiredDeviceAndMarketingIcons() throws {
        let root = repositoryRoot()
        let appIconDirectory = root.appendingPathComponent("MateDroidIOS/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        let contents = try loadJSON("MateDroidIOS/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
        let images = try XCTUnwrap(contents["images"] as? [[String: String]])
        let slots = Set(images.map { "\($0["idiom"] ?? "")|\($0["size"] ?? "")|\($0["scale"] ?? "")" })

        XCTAssertTrue(slots.contains("iphone|60x60|3x"))
        XCTAssertTrue(slots.contains("iphone|60x60|2x"))
        XCTAssertTrue(slots.contains("ipad|76x76|1x"))
        XCTAssertTrue(slots.contains("ipad|76x76|2x"))
        XCTAssertTrue(slots.contains("ipad|83.5x83.5|2x"))
        XCTAssertTrue(slots.contains("ios-marketing|1024x1024|1x"))

        for image in images {
            let filename = try XCTUnwrap(image["filename"])
            let url = appIconDirectory.appendingPathComponent(filename)
            let data = try Data(contentsOf: url)
            XCTAssertNotNil(UIImage(data: data), "Icon image is not readable: \(filename)")
        }
    }

    func testAppStoreSubmissionDraftCoversReviewPrivacyAndBranding() throws {
        let draft = try loadText("docs/release/app-store-submission.md")

        let requiredSections = [
            "## App Name",
            "## Submission Status",
            "## Subtitle",
            "## Description",
            "## Keywords",
            "## Promotional Text",
            "## Support URL",
            "## Marketing URL",
            "## Review Notes",
            "## Pre-Submission Verification",
            "## Demo Account And Server",
            "## Privacy Summary",
            "## App Privacy Questionnaire Draft",
            "## Export Compliance",
            "## Screenshot Checklist"
        ]

        for section in requiredSections {
            XCTAssertTrue(draft.contains(section), "Missing App Store submission section: \(section)")
        }

        XCTAssertTrue(draft.contains("MateDrive"))
        XCTAssertTrue(draft.contains("TeslaMate"))
        XCTAssertTrue(draft.contains("Technical archive ready."))
        XCTAssertFalse(draft.contains("TBD"))
        XCTAssertTrue(draft.contains("TeslaMate dashboard for iPhone"))
        XCTAssertTrue(draft.contains("Track your TeslaMate vehicle data"))
        XCTAssertTrue(draft.contains("docs/support/index.html"))
        XCTAssertTrue(draft.contains("Omit this optional field"))
        XCTAssertTrue(draft.contains("MateDrive requires the reviewer to configure a reachable TeslaMate API server"))
        XCTAssertTrue(draft.contains("The app is read-only"))
        XCTAssertTrue(draft.contains("does not send your vehicle data to a MateDrive-operated service"))
        XCTAssertTrue(draft.contains("MateDrive does not control your vehicle"))
        XCTAssertTrue(draft.contains("stores API tokens and Basic Auth secrets in Keychain"))
        XCTAssertTrue(draft.contains("Data collection by MateDrive developer: No."))
        XCTAssertTrue(draft.contains("Third-party tracking: No."))
        XCTAssertTrue(draft.contains("User account creation: No."))
        XCTAssertTrue(draft.contains("Diagnostics sent to developer: No."))
        XCTAssertTrue(draft.contains("Do not commit real server URLs, tokens, usernames, or passwords"))
        XCTAssertTrue(draft.contains("make verify"))
        XCTAssertTrue(draft.contains("make release-technical-gate"))
        XCTAssertTrue(draft.contains("make app-store-audit"))
        XCTAssertTrue(draft.contains("make integration-test"))
        XCTAssertTrue(draft.contains("MATEDRIVE_INTEGRATION_BASE_URL"))
        XCTAssertTrue(draft.contains("MATEDRIVE_INTEGRATION_API_TOKEN"))
        XCTAssertTrue(draft.contains("MATEDRIVE_INTEGRATION_BASIC_USERNAME"))
        XCTAssertTrue(draft.contains("MATEDRIVE_INTEGRATION_BASIC_PASSWORD"))
        XCTAssertTrue(draft.contains("vehicles, status, charge and drive lists/details, battery health, software updates, current charge, and global settings"))
        XCTAssertTrue(draft.contains("Never commit reviewer server URLs or credentials."))
        XCTAssertTrue(draft.contains("ITSAppUsesNonExemptEncryption"))
        XCTAssertTrue(draft.contains("Dashboard with vehicle image and status."))
        XCTAssertTrue(draft.contains("Settings with language selector and connection test."))
        XCTAssertTrue(draft.contains("Charge detail with cost section and chart."))
        XCTAssertTrue(draft.contains("Drive detail with route and metric cards."))
        XCTAssertTrue(draft.contains("Battery health screen."))
        XCTAssertTrue(draft.contains("no local/private server URLs"))
        XCTAssertTrue(draft.contains("no real secrets"))
        XCTAssertFalse(draft.contains("MateDroid"))
        XCTAssertFalse(draft.contains("sk-"))
        XCTAssertFalse(draft.contains("http://"))
        XCTAssertFalse(draft.contains("localhost"))
        XCTAssertFalse(draft.contains("127.0.0.1"))
        XCTAssertFalse(draft.range(
            of: #"\b(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\.\d{1,3}\.\d{1,3}\b"#,
            options: .regularExpression
        ) != nil, "Submission draft must not contain private network server addresses")
    }

    func testAppStoreSubmissionDraftDoesNotPretendPlaceholderValuesAreReady() throws {
        let draft = try loadText("docs/release/app-store-submission.md")
        XCTAssertFalse(draft.contains("TBD"))
        XCTAssertTrue(draft.contains("must be published before submission"))
        XCTAssertTrue(draft.contains("provided privately in App Store Connect review notes"))
    }

    func testPublishableSupportAndPrivacyPagesDescribeDataFlow() throws {
        let support = try loadText("docs/support/index.html")
        let privacy = try loadText("docs/support/privacy.html")

        XCTAssertTrue(support.contains("MateDrive Support"))
        XCTAssertTrue(support.contains("privacy.html"))
        XCTAssertTrue(support.contains("does not send commands to your vehicle"))
        XCTAssertTrue(privacy.contains("MateDrive Privacy Policy"))
        XCTAssertTrue(privacy.contains("Apple Keychain"))
        XCTAssertTrue(privacy.contains("Open-Meteo"))
        XCTAssertTrue(privacy.contains("does not use advertising trackers"))
    }

    func testReleaseTechnicalGateBuildsAndAuditsTheArchive() throws {
        let makefile = try loadText("Makefile")

        XCTAssertTrue(makefile.contains("release-technical-gate: app-store-technical-audit archive-release archive-audit"))
        XCTAssertTrue(makefile.contains("archive-release:"))
        XCTAssertTrue(makefile.contains("archive-audit:"))
    }

    private func loadPlist(_ relativePath: String) throws -> [String: Any] {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    private func loadJSON(_ relativePath: String) throws -> [String: Any] {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }

    private func loadText(_ relativePath: String) throws -> String {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func swiftSourcePaths(in directories: [String]) throws -> [String] {
        let root = repositoryRoot()
        let fileManager = FileManager.default

        return try directories.flatMap { directory -> [String] in
            let directoryURL = root.appendingPathComponent(directory, isDirectory: true)
            let files = try XCTUnwrap(fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ))
            return files.compactMap { item -> String? in
                guard let fileURL = item as? URL,
                      fileURL.pathExtension == "swift",
                      (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else {
                    return nil
                }
                return fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            }
        }.sorted()
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func isDottedNumericVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy(\.isNumber)
        }
    }
}
