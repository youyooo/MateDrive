import XCTest
@testable import MateDriveApp

@MainActor
final class EnergyCyclesViewModelTests: XCTestCase {
    func testRepeatedEntryRestoresAnalysisAndFailedRefreshPreservesIt() async throws {
        let cache = VehiclePageStateCache<EnergyCyclesState>()
        let key = VehiclePageCacheKey(serverURL: "https://example.test", carId: 7)
        let initialViewModel = EnergyCyclesViewModel(
            provider: EnergyCycleTestProvider(result: .success(.empty)),
            cacheKey: key,
            stateCache: cache
        )

        await initialViewModel.load(carId: 7)
        let cachedAnalysis = try XCTUnwrap(initialViewModel.state.analysis)

        let repeatedViewModel = EnergyCyclesViewModel(
            provider: EnergyCycleTestProvider(result: .failure(EnergyCycleTestError.unavailable)),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertEqual(repeatedViewModel.state.analysis, cachedAnalysis)
        XCTAssertFalse(repeatedViewModel.state.isLoading)

        await repeatedViewModel.load(carId: 7)

        XCTAssertEqual(repeatedViewModel.state.analysis, cachedAnalysis)
        XCTAssertEqual(repeatedViewModel.state.errorMessage, EnergyCycleTestError.unavailable.localizedDescription)
        XCTAssertFalse(repeatedViewModel.state.isLoading)
    }

    func testConcurrentLoadsOnlyReadStoredHistoryOnce() async {
        let provider = DelayedEnergyCycleTestProvider()
        let viewModel = EnergyCyclesViewModel(provider: provider)

        async let first: Void = viewModel.load(carId: 3)
        async let second: Void = viewModel.load(carId: 3)
        _ = await (first, second)

        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertNotNil(viewModel.state.analysis)
    }
}

private enum EnergyCycleTestError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Stored energy history is unavailable"
    }
}

private struct EnergyCycleTestProvider: EnergyCycleDataProviding {
    let result: Result<EnergyCycleDataSet, Error>

    func dataSet(carId _: Int) async throws -> EnergyCycleDataSet {
        try result.get()
    }
}

private actor DelayedEnergyCycleTestProvider: EnergyCycleDataProviding {
    private(set) var requestCount = 0

    func dataSet(carId _: Int) async throws -> EnergyCycleDataSet {
        requestCount += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        return .empty
    }
}
