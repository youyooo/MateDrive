import Foundation
import XCTest
@testable import MateDriveApp

final class ActivityLabelEditorTests: XCTestCase {
    private let context = ActivityLabelEditorContext(
        carId: 7,
        sessionId: "session-42",
        placeKey: "  home:长沙  "
    )

    func testCustomPurposeRejectsEmptyAndUnicodeWhitespaceNames() {
        for name in ["", "  \n\t ", "\u{3000}\u{3000}"] {
            var draft = ActivityLabelEditorDraft(purpose: .custom)
            draft.customName = name

            XCTAssertThrowsError(try ActivityLabelEditorValidator.validate(draft, context: context)) {
                XCTAssertEqual($0 as? ActivityLabelEditorValidationError, .customNameRequired)
            }
        }
    }

    func testCustomPurposePreservesUnicodeAndTrimsBoundaryWhitespace() throws {
        var draft = ActivityLabelEditorDraft(
            purpose: .custom,
            customName: "  接送小朋友 🚗  ",
            symbolName: "  figure.2.and.child.holdinghands  ",
            semanticColor: .pink
        )
        draft.startMinute = 420
        draft.endMinute = 600

        let value = try ActivityLabelEditorValidator.makeOverride(
            from: draft,
            context: context,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(value.customName, "接送小朋友 🚗")
        XCTAssertEqual(value.icon, "figure.2.and.child.holdinghands")
        XCTAssertEqual(value.colorHex, "#FF2D55")
        XCTAssertEqual(value.startMinute, 420)
        XCTAssertEqual(value.endMinute, 600)
    }

    func testTimeWindowRequiresBothBoundaries() {
        var startOnly = ActivityLabelEditorDraft()
        startOnly.startMinute = 60
        XCTAssertThrowsError(try ActivityLabelEditorValidator.validate(startOnly, context: context)) {
            XCTAssertEqual($0 as? ActivityLabelEditorValidationError, .incompleteTimeWindow)
        }

        var endOnly = ActivityLabelEditorDraft()
        endOnly.endMinute = 120
        XCTAssertThrowsError(try ActivityLabelEditorValidator.validate(endOnly, context: context)) {
            XCTAssertEqual($0 as? ActivityLabelEditorValidationError, .incompleteTimeWindow)
        }
    }

    func testTimeWindowRejectsMinutesOutsideDayAndAcceptsBoundaries() throws {
        for pair in [(-1, 60), (60, 1_440)] {
            var draft = ActivityLabelEditorDraft()
            draft.startMinute = pair.0
            draft.endMinute = pair.1
            XCTAssertThrowsError(try ActivityLabelEditorValidator.validate(draft, context: context)) {
                XCTAssertEqual($0 as? ActivityLabelEditorValidationError, .invalidTimeWindow)
            }
        }

        var valid = ActivityLabelEditorDraft()
        valid.startMinute = 1_439
        valid.endMinute = 0
        XCTAssertNoThrow(try ActivityLabelEditorValidator.validate(valid, context: context))
    }

    func testFutureAtPlaceRequiresNonWhitespacePlaceKey() {
        let draft = ActivityLabelEditorDraft(scope: .futureAtPlace)

        for placeKey in [nil, "", " \n ", "\u{3000}"] as [String?] {
            let invalidContext = ActivityLabelEditorContext(
                carId: context.carId,
                sessionId: context.sessionId,
                placeKey: placeKey
            )
            XCTAssertThrowsError(try ActivityLabelEditorValidator.validate(draft, context: invalidContext)) {
                XCTAssertEqual($0 as? ActivityLabelEditorValidationError, .placeRequired)
            }
        }
    }

    func testSessionScopeTargetsOnlyCurrentSession() throws {
        let draft = ActivityLabelEditorDraft(
            scope: .sessionOnly,
            purpose: .commute,
            symbolName: "",
            semanticColor: .green
        )

        let value = try ActivityLabelEditorValidator.makeOverride(from: draft, context: context)

        XCTAssertEqual(value.id, "activity-label:7:session:session-42")
        XCTAssertEqual(value.carId, 7)
        XCTAssertEqual(value.sessionId, "session-42")
        XCTAssertNil(value.placeKey)
        XCTAssertEqual(value.scope, .sessionOnly)
        XCTAssertEqual(value.icon, SmartActivityPurpose.commute.systemImage)
        XCTAssertNil(value.customName)
    }

    func testPlaceScopeTargetsNormalizedPlaceAndFutureSessions() throws {
        let draft = ActivityLabelEditorDraft(
            scope: .futureAtPlace,
            purpose: .homeCharging,
            symbolName: "house.fill",
            semanticColor: .teal,
            startMinute: 1_320,
            endMinute: 360
        )

        let value = try ActivityLabelEditorValidator.makeOverride(from: draft, context: context)

        XCTAssertEqual(value.id, "activity-label:7:place:home:长沙")
        XCTAssertNil(value.sessionId)
        XCTAssertEqual(value.placeKey, "home:长沙")
        XCTAssertEqual(value.scope, .futureAtPlace)
        XCTAssertEqual(value.startMinute, 1_320)
        XCTAssertEqual(value.endMinute, 360)
    }

    func testReplacingOverrideKeepsIdentifierAndUpdatesNormalizedFields() throws {
        let existing = ActivityLabelOverride(
            id: "existing-label",
            carId: 7,
            sessionId: "session-42",
            placeKey: nil,
            scope: .sessionOnly,
            purpose: .parking,
            customName: nil,
            icon: "parkingsign.circle.fill",
            colorHex: "#007AFF",
            startMinute: nil,
            endMinute: nil,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let draft = ActivityLabelEditorDraft(
            scope: .futureAtPlace,
            purpose: .shopping,
            symbolName: "cart.fill",
            semanticColor: .orange
        )

        let value = try ActivityLabelEditorValidator.makeOverride(
            from: draft,
            context: context,
            replacing: existing,
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(value.id, "existing-label")
        XCTAssertNil(value.sessionId)
        XCTAssertEqual(value.placeKey, "home:长沙")
        XCTAssertEqual(value.updatedAt, Date(timeIntervalSince1970: 2))
    }
}
