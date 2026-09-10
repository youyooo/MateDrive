import Foundation
import XCTest
@testable import MateDriveApp

@MainActor
final class CostReviewViewModelTests: XCTestCase {
    func testPresentationKeepsMissingAndExplicitZeroCostsDistinct() {
        XCTAssertEqual(CostReviewPresentation.money(nil, currencySymbol: "¥"), "--")
        XCTAssertEqual(CostReviewPresentation.money(0, currencySymbol: "¥"), "¥0.00")
        XCTAssertEqual(CostReviewPresentation.moneyDelta(-12.5, currencySymbol: "¥"), "-¥12.50")
        XCTAssertEqual(CostReviewPresentation.moneyDelta(0, currencySymbol: "¥"), "¥0.00")
        XCTAssertEqual(CostReviewPresentation.coverage(recorded: 1, total: 15, language: .chinese), "已记录 1/15 条")
        XCTAssertEqual(CostReviewPresentation.rangeTitle(.ninetyDays, language: .chinese), "90 天")
    }

    func testLoadUsesSelectedPresetAndPreservesServerDataQuality() async throws {
        let now = Date(timeIntervalSince1970: 1_752_278_400) // 2025-07-12 00:00:00 UTC
        let response = try sampleResponse()
        let api = RecordingCostReviewAPI(result: .success(response))
        let viewModel = CostReviewViewModel(api: api, now: { now })

        await viewModel.load(carId: 1)

        let recordedRequests = await api.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.carId, 1)
        XCTAssertEqual(request.endDate, now.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(request.startDate, now.addingTimeInterval(-29 * 24 * 60 * 60))
        XCTAssertEqual(viewModel.state.response?.data.summary.recordedSpend, 27.83)
        XCTAssertFalse(viewModel.hasCompleteRecordedSpend)
        XCTAssertEqual(viewModel.missingCostCount, 44)
    }

    func testSelectingPresetReloadsAnEqualLengthRange() async throws {
        let now = Date(timeIntervalSince1970: 1_752_278_400)
        let api = RecordingCostReviewAPI(result: .success(try sampleResponse()))
        let viewModel = CostReviewViewModel(api: api, now: { now })

        await viewModel.select(.sevenDays, carId: 9)

        let recordedRequests = await api.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.last)
        XCTAssertEqual(request.endDate, now.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(request.startDate, now.addingTimeInterval(-6 * 24 * 60 * 60))
        XCTAssertEqual(viewModel.state.range, .sevenDays)
    }

    func testDateWindowIsStableThroughoutTheSameUTCDay() {
        let morning = Date(timeIntervalSince1970: 1_752_280_200)
        let evening = morning.addingTimeInterval(12 * 60 * 60)

        let morningWindow = CostReviewRange.thirtyDays.dateWindow(containing: morning)
        let eveningWindow = CostReviewRange.thirtyDays.dateWindow(containing: evening)

        XCTAssertEqual(morningWindow.startDate, eveningWindow.startDate)
        XCTAssertEqual(morningWindow.endDate, eveningWindow.endDate)
    }

    func testFailedReloadKeepsExistingReviewAndShowsNonDestructiveError() async throws {
        let response = try sampleResponse()
        let api = SequencedCostReviewAPI(results: [.success(response), .failure(.httpStatus(503))])
        let viewModel = CostReviewViewModel(api: api, now: Date.init)

        await viewModel.load(carId: 1)
        await viewModel.select(.ninetyDays, carId: 1)

        XCTAssertEqual(viewModel.state.response, response)
        XCTAssertEqual(viewModel.state.range, .thirtyDays)
        XCTAssertNotNil(viewModel.state.errorMessage)
    }

    func testRepeatedEntryRestoresSelectedRangeAndCachedRangesSurviveFailure() async throws {
        let response = try sampleResponse()
        let cache = VehiclePageStateCache<CostReviewPageSnapshot>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let initial = CostReviewViewModel(
            api: RecordingCostReviewAPI(result: .success(response)),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1)
        await initial.select(.sevenDays, carId: 1)

        let reopened = CostReviewViewModel(
            api: RecordingCostReviewAPI(result: .failure(.network("offline"))),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.range, .sevenDays)
        XCTAssertEqual(reopened.state.response, response)

        await reopened.select(.thirtyDays, carId: 1)

        XCTAssertEqual(reopened.state.range, .thirtyDays)
        XCTAssertEqual(reopened.state.response, response)
        XCTAssertNotNil(reopened.state.errorMessage)
    }

    func testOverlappingCostReviewLoadsStartOneRequest() async {
        let api = SlowCostReviewAPI()
        let viewModel = CostReviewViewModel(api: api)

        async let first: Void = viewModel.load(carId: 1)
        async let second: Void = viewModel.load(carId: 1)
        _ = await (first, second)

        let requestCount = await api.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testRangeSelectionIsIgnoredWhileRefreshIsInFlight() async throws {
        let response = try sampleResponse()
        let api = SlowSuccessfulCostReviewAPI(response: response)
        let viewModel = CostReviewViewModel(api: api)

        let refresh = Task { await viewModel.load(carId: 1) }
        await Task.yield()
        await viewModel.select(.sevenDays, carId: 1)
        await refresh.value

        XCTAssertEqual(viewModel.state.range, .thirtyDays)
        let requestCount = await api.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    private func sampleResponse() throws -> CostReviewResponse {
        try JSONDecoder.teslamate.decode(
            CostReviewResponse.self,
            from: #"{"contractVersion":1,"data":{"range":{"startDate":"2026-06-12T00:00:00Z","endDate":"2026-07-12T00:00:00Z","period":"day"},"summary":{"recordedSpend":27.83,"estimatedUseCost":510.61,"missingChargeCostCount":14,"missingParkingCostCount":30},"dataQuality":{"hasAnyActivity":true,"chargingCost":{"eventCount":15,"costRecordedCount":1,"missingCostCount":14,"zeroCostCount":0,"costCoverage":0.0667},"parkingCost":{"eventCount":30,"costRecordedCount":0,"missingCostCount":30,"zeroCostCount":0,"costCoverage":0},"energyEstimate":{"isAvailable":true}},"buckets":[],"chargingModes":[],"placeRankings":{"charging":[],"parking":[],"standby":[]},"records":{"topCharges":[],"missingChargeCosts":[],"missingParkingCosts":[]}}}"#.data(using: .utf8)!
        )
    }
}

private actor RecordingCostReviewAPI: CostReviewAPIProviding {
    struct Request: Equatable {
        let carId: Int
        let startDate: Date
        let endDate: Date
    }

    let result: APIResult<CostReviewResponse>
    private(set) var requests: [Request] = []

    init(result: APIResult<CostReviewResponse>) { self.result = result }

    func recordedRequests() -> [Request] { requests }

    func costReview(carId: Int, startDate: Date, endDate: Date) async -> APIResult<CostReviewResponse> {
        requests.append(Request(carId: carId, startDate: startDate, endDate: endDate))
        return result
    }
}

private actor SequencedCostReviewAPI: CostReviewAPIProviding {
    private var results: [APIResult<CostReviewResponse>]
    init(results: [APIResult<CostReviewResponse>]) { self.results = results }

    func costReview(carId _: Int, startDate _: Date, endDate _: Date) async -> APIResult<CostReviewResponse> {
        results.isEmpty ? .failure(.emptyBody) : results.removeFirst()
    }
}

private actor SlowCostReviewAPI: CostReviewAPIProviding {
    private var requests = 0

    var requestCount: Int {
        requests
    }

    func costReview(carId _: Int, startDate _: Date, endDate _: Date) async -> APIResult<CostReviewResponse> {
        requests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .failure(.emptyBody)
    }
}

private actor SlowSuccessfulCostReviewAPI: CostReviewAPIProviding {
    private let response: CostReviewResponse
    private var requests = 0

    init(response: CostReviewResponse) {
        self.response = response
    }

    var requestCount: Int {
        requests
    }

    func costReview(carId _: Int, startDate _: Date, endDate _: Date) async -> APIResult<CostReviewResponse> {
        requests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .success(response)
    }
}
