import XCTest
import UIKit
@testable import MateDriveApp

final class AppStoreReadinessTests: XCTestCase {
    func testAppInfoPlistDeclaresBackgroundRefreshForScheduledSync() throws {
        let plist = try loadPlist("MateDriveApp/Info.plist")

        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "MateDrive")
        XCTAssertEqual(plist["CFBundleName"] as? String, "$(PRODUCT_NAME)")
        XCTAssertEqual(plist["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertTrue((plist["UIBackgroundModes"] as? [String])?.contains("fetch") == true)
        XCTAssertTrue((plist["UIBackgroundModes"] as? [String])?.contains("processing") == true)
        XCTAssertEqual(plist["NSSupportsLiveActivities"] as? Bool, true)
    }

    func testWidgetBundleIncludesReadOnlyChargeLiveActivity() throws {
        let bundle = try loadText("MateDriveWidget/MateDriveWidgetBundle.swift")
        let activity = try loadText("MateDriveWidget/ChargeLiveActivityWidget.swift")

        XCTAssertTrue(bundle.contains("ChargeLiveActivityWidget()"))
        XCTAssertTrue(activity.contains("ActivityConfiguration(for: ChargeLiveActivityAttributes.self)"))
        XCTAssertFalse(activity.contains("Button("))
        XCTAssertFalse(activity.contains("AppIntent"))
    }

    func testLaunchScreenUsesPackagedBrandAssets() throws {
        let plist = try loadPlist("MateDriveApp/Info.plist")
        let launch = try XCTUnwrap(plist["UILaunchScreen"] as? [String: Any])
        let assetRoot = repositoryRoot().appendingPathComponent("MateDriveApp/Resources/Assets.xcassets")

        XCTAssertEqual(launch["UIColorName"] as? String, "LaunchBackground")
        XCTAssertEqual(launch["UIImageName"] as? String, "LaunchWordmark")
        XCTAssertEqual(launch["UIImageRespectsSafeAreaInsets"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetRoot.appendingPathComponent("LaunchBackground.colorset/Contents.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetRoot.appendingPathComponent("LaunchWordmark.imageset/LaunchMark@3x.png").path))
    }

    func testAppVersionAndBuildAreAppStoreCompatible() throws {
        let plist = try loadPlist("MateDriveApp/Info.plist")
        let shortVersion = try XCTUnwrap(plist["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(plist["CFBundleVersion"] as? String)
        let projectYAML = try loadText("project.yml")

        XCTAssertTrue(
            Self.isDottedNumericVersion(shortVersion)
                || (
                    shortVersion == "$(MARKETING_VERSION)"
                        && projectYAML.range(
                            of: #"MARKETING_VERSION:\s*"\d+(?:\.\d+){0,2}""#,
                            options: .regularExpression
                        ) != nil
                ),
            "CFBundleShortVersionString must resolve to a dotted numeric version"
        )
        XCTAssertTrue(
            Self.isDottedNumericVersion(build)
                || (
                    build == "$(CURRENT_PROJECT_VERSION)"
                        && projectYAML.range(
                            of: #"CURRENT_PROJECT_VERSION:\s*"\d+(?:\.\d+){0,2}""#,
                            options: .regularExpression
                        ) != nil
                ),
            "CFBundleVersion must resolve to a dotted numeric build"
        )
    }

    func testBackgroundRefreshIdentifierIsAlignedAcrossAppConfigAndScheduler() throws {
        let plist = try loadPlist("MateDriveApp/Info.plist")
        let identifiers = try XCTUnwrap(plist["BGTaskSchedulerPermittedIdentifiers"] as? [String])
        let projectYAML = try loadText("project.yml")

        XCTAssertEqual(BackgroundSyncScheduler.syncTaskIdentifier, "com.matedrive.ios.sync")
        XCTAssertEqual(Set(identifiers), [
            BackgroundSyncScheduler.syncTaskIdentifier,
            BackgroundSyncScheduler.fullSyncTaskIdentifier
        ])
        XCTAssertTrue(projectYAML.contains("- \(BackgroundSyncScheduler.syncTaskIdentifier)"))
        XCTAssertTrue(projectYAML.contains("- \(BackgroundSyncScheduler.fullSyncTaskIdentifier)"))
    }

    func testLiveEnvironmentIsNotLabeledAsDevelopment() {
        XCTAssertEqual(AppEnvironment.live.buildLabel, "production")
    }

    func testDebugLocalTeslaMateSeederIsCompileTimeDebugOnly() throws {
        let seederSource = try loadText("MateDriveApp/App/DebugLocalTeslamateSeeder.swift")
        let rootViewSource = try loadText("MateDriveApp/App/RootView.swift")

        XCTAssertTrue(seederSource.contains("#if DEBUG"))
        XCTAssertTrue(seederSource.contains("#endif"))
        XCTAssertTrue(seederSource.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("#endif"))
        XCTAssertTrue(rootViewSource.contains("#if DEBUG"))
        XCTAssertTrue(rootViewSource.contains("DebugLocalTeslamateSeeder.seedLaunchConfigurationIfNeeded"))
        XCTAssertTrue(rootViewSource.contains("DebugLocalTeslamateSeeder.seedDatabaseFixtureIfNeeded"))
        XCTAssertTrue(rootViewSource.contains("Self.isAutomatedTestMode"))
        XCTAssertTrue(rootViewSource.contains("Self.isReservedTestServer"))
    }

    func testProductionSourcesDoNotEmbedLocalTeslaMateDefaults() throws {
        let productionPaths = [
            "MateDriveApp/App/AppEnvironment.swift",
            "MateDriveApp/App/RootView.swift",
            "MateDriveApp/Core/API/TeslamateAPI.swift",
            "MateDriveApp/Info.plist",
            "MateDriveWidget/Info.plist",
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

    func testHistoryHeavyFeatureRoutesUseSynchronizedLocalDataProvider() throws {
        let rootViewSource = try loadText("MateDriveApp/App/RootView.swift")
        let constructors = [
            "CompareChargesViewModel",
            "ActivitiesViewModel",
            "CompareDrivesViewModel",
            "BatteryViewModel",
            "DriveInsightsViewModel",
            "WhereWasIViewModel",
            "CountriesVisitedViewModel",
            "RegionsVisitedViewModel"
        ]

        for constructor in constructors {
            let escaped = NSRegularExpression.escapedPattern(for: constructor)
            let expression = try NSRegularExpression(
                pattern: "\(escaped)\\([\\s\\S]{0,700}?historyProvider:\\s*mileageDataProvider\\(\\)"
            )
            let range = NSRange(rootViewSource.startIndex..<rootViewSource.endIndex, in: rootViewSource)
            XCTAssertNotNil(
                expression.firstMatch(in: rootViewSource, range: range),
                "\(constructor) must use synchronized local history in the production route"
            )
        }
    }

    func testSoftwareUpdateRouteUsesDedicatedPersistentHistoryStore() throws {
        let rootViewSource = try loadText("MateDriveApp/App/RootView.swift")
        XCTAssertTrue(rootViewSource.contains("snapshotStore: SoftwareUpdateSnapshotStore.shared"))
        let privacySource = try loadText("MateDriveApp/Features/Settings/PrivacyDataView.swift")
        XCTAssertTrue(privacySource.contains("SoftwareUpdateSnapshotStore.shared.removeAll()"))
    }

    func testMemoryWarningsReleaseRebuildableCachesWithoutDeletingOfflineSnapshots() throws {
        let rootViewSource = try loadText("MateDriveApp/App/RootView.swift")
        let pageCacheSource = try loadText("MateDriveApp/Core/Persistence/VehiclePageStateCache.swift")
        let updateStoreSource = try loadText("MateDriveApp/Features/Updates/SoftwareUpdateSnapshotStore.swift")

        XCTAssertTrue(rootViewSource.contains("UIApplication.didReceiveMemoryWarningNotification"))
        XCTAssertTrue(rootViewSource.contains("VehiclePageStateCacheRegistry.releaseMemory()"))
        XCTAssertTrue(rootViewSource.contains("SoftwareUpdateSnapshotStore.shared.releaseMemory()"))
        XCTAssertTrue(pageCacheSource.contains("VehiclePageStateCacheRegistry.register(self)"))
        XCTAssertTrue(updateStoreSource.contains("restoredFromDisk = false"))
    }

    func testProductionSwiftSourcesDoNotUseForcedCrashPatterns() throws {
        let forbiddenPatterns = [
            "try!": "avoid forced throwing calls in production source",
            "as!": "avoid forced casts in production source",
            "fatalError(": "avoid unconditional crashes in production source",
            "preconditionFailure(": "avoid unconditional crashes in production source"
        ]
        let sourcePaths = try swiftSourcePaths(in: ["MateDriveApp", "MateDriveWidget"])
        let forcedUnwrapPattern = try NSRegularExpression(
            pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]\n]+\]|\.[A-Za-z_][A-Za-z0-9_]*)*!(?=[\s\.,\)\]\?:]|$)"#
        )

        XCTAssertFalse(sourcePaths.isEmpty, "Expected production Swift sources to be discoverable")

        for path in sourcePaths {
            let text = try loadText(path)
            for (pattern, message) in forbiddenPatterns {
                XCTAssertFalse(text.contains(pattern), "\(path) must \(message): \(pattern)")
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            XCTAssertNil(
                forcedUnwrapPattern.firstMatch(in: text, range: range),
                "\(path) must avoid forced optional unwraps"
            )
        }
    }

    func testProductionConfigurationUsesMateDriveIdentifiers() throws {
        let productionConfigurationPaths = [
            "project.yml",
            "MateDriveApp/Info.plist",
            "MateDriveWidget/Info.plist",
            "MateDriveApp/MateDriveApp.entitlements",
            "MateDriveWidget/MateDriveWidget.entitlements",
            "MateDriveApp/Core/Sync/BackgroundSyncScheduler.swift",
            "MateDriveApp/Core/Security/KeychainStore.swift",
            "MateDriveWidget/WidgetDisplayData.swift"
        ]

        for path in productionConfigurationPaths {
            let text = try loadText(path)
            XCTAssertFalse(text.contains("PRODUCT_BUNDLE_IDENTIFIER: com.example"), "\(path) must use production identifiers")
        }
    }

    func testWidgetInfoPlistUsesMateDriveBranding() throws {
        let plist = try loadPlist("MateDriveWidget/Info.plist")
        let extensionInfo = try XCTUnwrap(plist["NSExtension"] as? [String: Any])

        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "MateDrive Widget")
        XCTAssertEqual(plist["CFBundleName"] as? String, "$(PRODUCT_NAME)")
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
    }

    func testXcodeProjectKeepsAppStoreVisibleBrandingAndPrivacyManifest() throws {
        let projectYAML = try loadText("project.yml")
        let projectFile = try loadText("MateDrive.xcodeproj/project.pbxproj")

        XCTAssertTrue(projectYAML.contains("PRODUCT_NAME: MateDrive"))
        XCTAssertTrue(projectYAML.contains("schemes:\n  MateDrive:"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_MODULE_NAME: MateDriveApp"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_BUNDLE_IDENTIFIER: com.matedrive.ios"))
        XCTAssertTrue(projectYAML.contains("INFOPLIST_KEY_CFBundleDisplayName: MateDrive"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_NAME: MateDriveWidget"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_MODULE_NAME: MateDriveWidget"))
        XCTAssertTrue(projectYAML.contains("PRODUCT_BUNDLE_IDENTIFIER: com.matedrive.ios.widget"))
        XCTAssertTrue(projectYAML.contains("INFOPLIST_KEY_CFBundleDisplayName: MateDrive Widget"))
        XCTAssertTrue(projectYAML.contains("- path: MateDriveApp/PrivacyInfo.xcprivacy"))
        XCTAssertTrue(projectYAML.contains("- path: MateDriveWidget/PrivacyInfo.xcprivacy"))
        XCTAssertTrue(projectYAML.contains(#"TEST_HOST: "$(BUILT_PRODUCTS_DIR)/MateDrive.app/MateDrive""#))
        XCTAssertTrue(projectFile.contains("PRODUCT_NAME = MateDrive"))
        XCTAssertTrue(projectFile.contains("PRODUCT_NAME = MateDriveWidget"))
        XCTAssertTrue(projectFile.contains("PRODUCT_MODULE_NAME = MateDriveApp"))
        XCTAssertTrue(projectFile.contains("PRODUCT_MODULE_NAME = MateDriveWidget"))
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
        let appEntitlements = try loadPlist("MateDriveApp/MateDriveApp.entitlements")
        let widgetEntitlements = try loadPlist("MateDriveWidget/MateDriveWidget.entitlements")
        let appGroups = try XCTUnwrap(appEntitlements["com.apple.security.application-groups"] as? [String])
        let widgetGroups = try XCTUnwrap(widgetEntitlements["com.apple.security.application-groups"] as? [String])
        let projectYAML = try loadText("project.yml")
        let projectFile = try loadText("MateDrive.xcodeproj/project.pbxproj")

        XCTAssertEqual(appGroups, [WidgetConstants.appGroupIdentifier])
        XCTAssertEqual(widgetGroups, [WidgetConstants.appGroupIdentifier])
        XCTAssertTrue(projectYAML.contains("CODE_SIGN_ENTITLEMENTS: MateDriveApp/MateDriveApp.entitlements"))
        XCTAssertTrue(projectYAML.contains("CODE_SIGN_ENTITLEMENTS: MateDriveWidget/MateDriveWidget.entitlements"))
        XCTAssertTrue(projectFile.contains("CODE_SIGN_ENTITLEMENTS = MateDriveApp/MateDriveApp.entitlements"))
        XCTAssertTrue(projectFile.contains("CODE_SIGN_ENTITLEMENTS = MateDriveWidget/MateDriveWidget.entitlements"))
    }

    func testInfoPlistDoesNotDeclareUnusedSensitivePermissions() throws {
        let plist = try loadPlist("MateDriveApp/Info.plist")
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

    func testPrivacyManifestDeclaresRequiredReasonsAndNoTracking() throws {
        let manifest = try loadPlist("MateDriveApp/PrivacyInfo.xcprivacy")

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        let collectedDataTypes = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertEqual(collectedDataTypes.count, 1)
        let preciseLocation = try XCTUnwrap(collectedDataTypes.first)
        XCTAssertEqual(
            preciseLocation["NSPrivacyCollectedDataType"] as? String,
            "NSPrivacyCollectedDataTypePreciseLocation"
        )
        XCTAssertEqual(preciseLocation["NSPrivacyCollectedDataTypeLinked"] as? Bool, false)
        XCTAssertEqual(preciseLocation["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(
            preciseLocation["NSPrivacyCollectedDataTypePurposes"] as? [String],
            ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
        )

        let accessedAPIs = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = try XCTUnwrap(accessedAPIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
        let fileTimestamp = try XCTUnwrap(accessedAPIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryFileTimestamp"
        })
        XCTAssertEqual(fileTimestamp["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])
        let systemBootTime = try XCTUnwrap(accessedAPIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategorySystemBootTime"
        })
        XCTAssertEqual(systemBootTime["NSPrivacyAccessedAPITypeReasons"] as? [String], ["35F9.1"])
    }

    func testWidgetPrivacyManifestDeclaresOnlyItsActualDataUse() throws {
        let manifest = try loadPlist("MateDriveWidget/PrivacyInfo.xcprivacy")

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])
        XCTAssertTrue((manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.isEmpty == true)

        let accessedAPIs = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(accessedAPIs.count, 1)
        XCTAssertEqual(
            accessedAPIs.first?["NSPrivacyAccessedAPIType"] as? String,
            "NSPrivacyAccessedAPICategoryUserDefaults"
        )
        XCTAssertEqual(
            accessedAPIs.first?["NSPrivacyAccessedAPITypeReasons"] as? [String],
            ["CA92.1"]
        )
    }

    func testAppIconSetContainsRequiredDeviceAndMarketingIcons() throws {
        let root = repositoryRoot()
        let appIconDirectory = root.appendingPathComponent("MateDriveApp/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        let contents = try loadJSON("MateDriveApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
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
        let projectYAML = try loadText("project.yml")
        let buildPattern = try NSRegularExpression(
            pattern: #"CURRENT_PROJECT_VERSION:\s*"([^"]+)""#
        )
        let projectRange = NSRange(projectYAML.startIndex..<projectYAML.endIndex, in: projectYAML)
        let buildMatch = try XCTUnwrap(buildPattern.firstMatch(in: projectYAML, range: projectRange))
        let buildRange = try XCTUnwrap(Range(buildMatch.range(at: 1), in: projectYAML))
        let currentBuild = String(projectYAML[buildRange])

        let requiredSections = [
            "## App Name",
            "## Submission Status",
            "## Subtitle",
            "## Description",
            "## Keywords",
            "## Promotional Text",
            "## Support URL",
            "## Marketing URL",
            "## Privacy Policy URL",
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
        XCTAssertTrue(draft.contains("Build \(currentBuild)"))
        XCTAssertTrue(draft.contains("App Store Connect"))
        XCTAssertTrue(draft.contains("TestFlight"))
        XCTAssertTrue(draft.contains("App Store review submission still also requires"))
        XCTAssertFalse(draft.contains("TBD"))
        XCTAssertTrue(draft.contains("TeslaMate dashboard for iPhone"))
        XCTAssertTrue(draft.contains("Track your TeslaMate vehicle data"))
        XCTAssertTrue(draft.contains("https://youyooo.github.io/MateDrive/"))
        XCTAssertTrue(draft.contains("Omit this optional field"))
        XCTAssertTrue(draft.contains("MateDrive requires the reviewer to configure a reachable TeslaMate API server"))
        XCTAssertTrue(draft.contains("The app is read-only"))
        XCTAssertTrue(draft.contains("does not send your vehicle data to a MateDrive-operated service"))
        XCTAssertTrue(draft.contains("MateDrive does not control your vehicle"))
        XCTAssertTrue(draft.contains("stores API tokens and Basic Auth secrets in Keychain"))
        XCTAssertTrue(draft.contains("No developer-operated backend or analytics collection"))
        XCTAssertTrue(draft.contains("one representative precise route coordinate and the drive time"))
        XCTAssertTrue(draft.contains("only after the user enables route weather"))
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
        XCTAssertTrue(draft.contains("Dashboard with a circular battery gauge and vehicle status."))
        XCTAssertTrue(draft.contains("Settings with language selector and connection test."))
        XCTAssertTrue(draft.contains("Charge detail with cost section and chart."))
        XCTAssertTrue(draft.contains("Drive detail with route and metric cards."))
        XCTAssertTrue(draft.contains("Battery health screen."))
        XCTAssertTrue(draft.contains("no local/private server URLs"))
        XCTAssertTrue(draft.contains("no real secrets"))
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
        XCTAssertTrue(draft.contains("https://youyooo.github.io/MateDrive/privacy.html"))
        XCTAssertTrue(draft.contains("provided privately in App Store Connect review notes"))
    }

    func testPublishableSupportAndPrivacyPagesDescribeDataFlow() throws {
        let support = try loadText("docs/support/index.html")
        let privacy = try loadText("docs/support/privacy.html")
        let links = try loadText("MateDriveApp/Core/Domain/AppLinks.swift")
        let settingsView = try loadText("MateDriveApp/Features/Settings/SettingsView.swift")
        let privacyView = try loadText("MateDriveApp/Features/Settings/PrivacyDataView.swift")

        XCTAssertTrue(support.contains("MateDrive Support"))
        XCTAssertTrue(support.contains("privacy.html"))
        XCTAssertTrue(support.contains("does not send commands to your vehicle"))
        XCTAssertTrue(privacy.contains("MateDrive Privacy Policy"))
        XCTAssertTrue(privacy.contains("Apple Keychain"))
        XCTAssertTrue(privacy.contains("Open-Meteo"))
        XCTAssertTrue(privacy.contains("does not use advertising trackers"))
        XCTAssertTrue(links.contains("https://youyooo.github.io/MateDrive/"))
        XCTAssertTrue(links.contains("https://youyooo.github.io/MateDrive/privacy.html"))
        XCTAssertTrue(settingsView.contains("AppLinks.supportURL"))
        XCTAssertTrue(settingsView.contains("AppLinks.privacyPolicyURL"))
        XCTAssertTrue(settingsView.contains("Support & Feedback"))
        XCTAssertTrue(privacyView.contains("AppLinks.privacyPolicyURL"))
        XCTAssertTrue(privacyView.contains("Link(destination: privacyPolicyURL)"))
    }

    func testSharedMapGestureGateResetsEveryEmbeddedMapAfterAutoLock() throws {
        let source = try loadText("MateDriveApp/Features/Shared/ListMapToolbarButton.swift")

        XCTAssertTrue(source.contains("Task.sleep(for: .seconds(3))"))
        XCTAssertTrue(source.contains("@State private var resetGeneration = 0"))
        XCTAssertTrue(source.contains(".id(resetGeneration)"))
        XCTAssertTrue(source.contains("resetGeneration &+= 1"))
    }

    func testHeavyDetailContentIsDeferredUntilAfterTheFirstNavigationFrame() throws {
        let activity = try loadText("MateDriveApp/Features/Activities/ActivitySessionDetailView.swift")
        let drive = try loadText("MateDriveApp/Features/Drives/DriveDetailView.swift")

        XCTAssertTrue(activity.contains("@State private var presentsMap = false"))
        XCTAssertTrue(activity.contains("try await Task.sleep(for: .seconds(1))"))
        XCTAssertTrue(activity.contains("if presentsMap"))
        XCTAssertTrue(drive.contains("@State private var presentsExpandedDetail = false"))
        XCTAssertTrue(drive.contains("try await Task.sleep(for: .seconds(1))"))
        XCTAssertTrue(drive.contains("viewModel.state.isShowingSummary || !presentsExpandedDetail"))
    }

    func testReleaseTechnicalGateBuildsAndAuditsTheArchive() throws {
        let makefile = try loadText("Makefile")

        XCTAssertTrue(makefile.contains("release-technical-gate: independent-release-audit app-store-technical-audit archive-release archive-audit"))
        XCTAssertTrue(makefile.contains("archive-release:"))
        XCTAssertTrue(makefile.contains("archive-audit:"))
    }

    func testRepositoryAndReleaseDoNotShipVehicleImageResources() throws {
        let root = repositoryRoot()
        let imageDirectory = root.appendingPathComponent("MateDriveApp/Resources/CarImages", isDirectory: true)
        let imageFiles = (try? FileManager.default.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let projectYAML = try loadText("project.yml")
        let archiveAudit = try loadText("scripts/audit_release_archive.py")

        XCTAssertFalse(imageFiles.contains { $0.pathExtension.lowercased() == "png" })
        let removedCatalogName = "Vehicle" + "Image" + "Catalog.json"
        XCTAssertFalse(projectYAML.contains(removedCatalogName))
        XCTAssertTrue(archiveAudit.contains("FORBIDDEN_VEHICLE_IMAGE_PATTERNS"))
        XCTAssertTrue(archiveAudit.contains("catalog_name"))
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
