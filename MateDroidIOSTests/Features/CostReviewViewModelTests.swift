import Foundation
import XCTest
@testable import MateDroidIOS

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
        XCTAssertEqual(request.endDate, now)
        XCTAssertEqual(request.startDate, now.addingTimeInterval(-30 * 24 * 60 * 60))
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
        XCTAssertEqual(request.endDate, now)
        XCTAssertEqual(request.startDate, now.addingTimeInterval(-7 * 24 * 60 * 60))
        XCTAssertEqual(viewModel.state.range, .sevenDays)
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
