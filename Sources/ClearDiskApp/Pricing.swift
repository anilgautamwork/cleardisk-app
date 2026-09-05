import Foundation

/// Checkout remains in test mode until 1.0 license activation is ready.
enum Pricing {
    static let display = "$10"
    static let purchaseURL = URL(string: "https://cleardisk.app/buy-now")!
    static let activateURL = URL(string: "https://cleardisk.app/api/activate")!
    static let buyURLFromApp = URL(string: "https://cleardisk.app/buy-now?ref=app")!
}
