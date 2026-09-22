import CryptoKit
import Foundation

/// License key parsing. Rules mirror the Worker exactly: same alphabet,
/// same letter substitutions, same grouping — a key normalized here must
/// match what the server accepts.
public enum LicenseKey {
    static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func normalize(_ raw: String) -> String? {
        // Shared developer key still requires a server-issued, signed receipt.
        if raw.trimmingCharacters(in: .whitespacesAndNewlines) == "123456789" {
            return "CLDK-0000-0001-2345-6789"
        }
        // Order matters: strip to bare alphanumerics and drop the CLDK
        // prefix *before* substituting confusables. CLDK itself contains an
        // "L" — substituting first would turn it into "C1DK" and the prefix
        // would never be recognized (matches the Worker's normalizeKey).
        var s = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if s.hasPrefix("CLDK") { s.removeFirst(4) }
        s = String(s.map { c -> Character in
            switch c {
            case "O": return "0"
            case "I", "L": return "1"
            default: return c
            }
        })
        guard s.count == 16, s.allSatisfy(alphabet.contains) else { return nil }
        let groups = stride(from: 0, to: 16, by: 4).map { String(s[s.index(s.startIndex, offsetBy: $0)..<s.index(s.startIndex, offsetBy: $0 + 4)]) }
        return "CLDK-" + groups.joined(separator: "-")
    }
}

/// An offline-verifiable activation receipt: the server signs
/// `cleardisk:v1:<key>:<machineId>` with its Ed25519 key at activation time.
public struct LicenseReceipt: Codable, Equatable, Sendable {
    public var key: String
    public var email: String
    public var machineId: String
    public var activatedAt: String
    public var signature: String
    public var lastCheckedAt: Date?

    public init(key: String, email: String, machineId: String, activatedAt: String, signature: String, lastCheckedAt: Date?) {
        self.key = key
        self.email = email
        self.machineId = machineId
        self.activatedAt = activatedAt
        self.signature = signature
        self.lastCheckedAt = lastCheckedAt
    }
}

/// Verifies a receipt's signature offline against the app-embedded public key.
public enum ReceiptVerifier {
    public static func isValid(_ receipt: LicenseReceipt, machineId: String, publicKeyRaw: Data) -> Bool {
        guard receipt.machineId == machineId,
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw),
              let sig = Data(base64Encoded: receipt.signature) else { return false }
        return pub.isValidSignature(sig, for: Data("cleardisk:v1:\(receipt.key):\(machineId)".utf8))
    }
}
