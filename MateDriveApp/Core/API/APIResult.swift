import Foundation

public enum APIResult<Value> {
    case success(Value)
    case failure(APIError)
}

extension APIResult: Sendable where Value: Sendable {}

public enum VehicleHistoryPaginator {
    public static let pageSize = 200
    public static let maximumPageCount = 250

    public static func drives(
        loadPage: @escaping @Sendable (_ page: Int, _ show: Int) async -> APIResult<[DriveData]>
    ) async -> APIResult<[DriveData]> {
        await loadAll(loadPage: loadPage, identifier: \.driveId)
    }

    public static func charges(
        loadPage: @escaping @Sendable (_ page: Int, _ show: Int) async -> APIResult<[ChargeData]>
    ) async -> APIResult<[ChargeData]> {
        await loadAll(loadPage: loadPage, identifier: \.chargeId)
    }

    private static func loadAll<Item: Sendable>(
        loadPage: @escaping @Sendable (_ page: Int, _ show: Int) async -> APIResult<[Item]>,
        identifier: @escaping @Sendable (Item) -> Int?
    ) async -> APIResult<[Item]> {
        var items: [Item] = []
        var seenIdentifiers: Set<Int> = []

        for page in 1 ... maximumPageCount {
            guard !Task.isCancelled else {
                return .failure(.cancelled)
            }

            let pageResult = await loadPage(page, pageSize)
            guard !Task.isCancelled else {
                return .failure(.cancelled)
            }

            let pageItems: [Item]
            switch pageResult {
            case let .success(value):
                pageItems = value
            case let .failure(error):
                return .failure(error)
            }

            var addedCount = 0
            for item in pageItems {
                if let id = identifier(item) {
                    guard seenIdentifiers.insert(id).inserted else { continue }
                }
                items.append(item)
                addedCount += 1
            }

            if pageItems.isEmpty {
                return .success(items)
            }
            if addedCount == 0 {
                return .failure(.invalidResponse("History pagination returned a repeated full page."))
            }
        }

        return .failure(.invalidResponse("History pagination exceeded the safety limit."))
    }
}

public extension JSONDecoder {
    static var teslamate: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
