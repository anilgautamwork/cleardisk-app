import Foundation

/// Prices and URLs for the $10 one-time license sold at cleardisk.app.
enum Pricing {
    static let display = "$10"
    static let activateURL = URL(string: "https://cleardisk.app/api/activate")!
    static let buyURLFromApp = URL(string: "https://cleardisk.app/buy-now?ref=app")!
}
