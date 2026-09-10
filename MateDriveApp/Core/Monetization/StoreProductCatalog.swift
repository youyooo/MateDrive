import Foundation

struct StoreProductCatalog: Equatable, Sendable {
    static let mateDrive = StoreProductCatalog(
        lifetimeID: "com.matedrive.ios.pro.lifetime",
        monthlyID: "com.matedrive.ios.pro.monthly",
        yearlyID: "com.matedrive.ios.pro.yearly"
    )

    let lifetimeID: String
    let monthlyID: String
    let yearlyID: String

    var productIDs: [String] {
        [lifetimeID, monthlyID, yearlyID]
    }

    var subscriptionIDs: Set<String> {
        [monthlyID, yearlyID]
    }
}
