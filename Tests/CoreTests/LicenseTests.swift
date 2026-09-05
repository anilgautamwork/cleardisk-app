import XCTest
import CryptoKit
@testable import Core
final class LicenseTests: XCTestCase {
    func testNormalizationMatchesTheServerRules() {
        XCTAssertEqual(LicenseKey.normalize("cldk-abcd efgh jkmn pqrs"), "CLDK-ABCD-EFGH-JKMN-PQRS")
        XCTAssertEqual(LicenseKey.normalize("ABCD-EFGH-JKMN-PQRS"), "CLDK-ABCD-EFGH-JKMN-PQRS")
        XCTAssertEqual(LicenseKey.normalize("CLDK-OIL0-1234-5678-9ABC"), "CLDK-0110-1234-5678-9ABC")
        XCTAssertNil(LicenseKey.normalize("CLDK-ABCD-EFGH-JKMN"))
        XCTAssertNil(LicenseKey.normalize("CLDK-ABCD-EFGH-JKMN-PQRU"))  // U is not in the alphabet
        XCTAssertNil(LicenseKey.normalize(""))
    }
    func testReceiptVerifiesOnlyForTheSignedKeyAndMachine() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let pub = priv.publicKey.rawRepresentation
        let key = "CLDK-ABCD-EFGH-JKMN-PQRS"
        let sig = try priv.signature(for: Data("cleardisk:v1:\(key):mac-1".utf8)).base64EncodedString()
        let receipt = LicenseReceipt(key: key, email: "a@b.c", machineId: "mac-1", activatedAt: "2026-09-05T00:00:00Z", signature: sig, lastCheckedAt: nil)
        XCTAssertTrue(ReceiptVerifier.isValid(receipt, machineId: "mac-1", publicKeyRaw: pub))
        XCTAssertFalse(ReceiptVerifier.isValid(receipt, machineId: "mac-2", publicKeyRaw: pub))
        var tampered = receipt; tampered.key = "CLDK-ABCD-EFGH-JKMN-PQRT"
        XCTAssertFalse(ReceiptVerifier.isValid(tampered, machineId: "mac-1", publicKeyRaw: pub))
        XCTAssertFalse(ReceiptVerifier.isValid(receipt, machineId: "mac-1", publicKeyRaw: Data(repeating: 1, count: 32)))
    }
}
