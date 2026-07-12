import Foundation

public enum APIResult<Value> {
    case success(Value)
    case failure(APIError)
}

extension APIResult: Sendable where Value: Sendable {}

public extension JSONDecoder {
    static var teslamate: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
