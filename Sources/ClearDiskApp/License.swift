import Core
import Foundation
import IOKit

/// Ed25519 public key matching the Worker's signing key. Verifies receipts
/// offline — activation still requires a network round trip once.
enum LicensePublicKey {
    static let raw = Data(base64Encoded: "o1CS/4g9/6b6cJxdvgsZZOUJvC38KEfMGHY8oqGwvpo=")!
}

/// Stable per-Mac identifier used both to activate and to verify receipts.
enum MachineIdentity {
    static var id: String { cachedId }
    static var name: String { Host.current().localizedName ?? "Mac" }

    private static let cachedId: String = computeId()

    private static func computeId() -> String {
        if let uuid = platformUUID() { return uuid }
        let key = "cleardisk.machineId"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    /// `IOPlatformUUID` from `IOPlatformExpertDevice` — stable across
    /// reinstalls, unlike anything we could generate ourselves.
    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let cfProp = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return cfProp.takeRetainedValue() as? String
    }
}

enum LicenseError: LocalizedError, Sendable {
    case invalidKey
    case revoked
    case limitReached([String])
    case offline
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "That key isn’t recognised. Check for typos or use Recover on cleardisk.app."
        case .revoked:
            return "This license was refunded and is no longer active."
        case .limitReached(let names):
            let list = names.joined(separator: ", ")
            return "Already in use on 3 Macs (\(list)). Email hello@cleardisk.app to free a slot."
        case .offline:
            return "Couldn’t reach the license server. Check your connection and try again."
        case .server(let message):
            return message
        }
    }
}

/// Talks to the Worker's `/api/activate`. Runs entirely off the main actor;
/// callers `await` it from `LicenseStore`.
struct LicenseClient {
    static func activate(key: String, appVersion: String) async throws -> LicenseReceipt {
        var request = URLRequest(url: Pricing.activateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode([
            "key": key,
            "machineId": MachineIdentity.id,
            "machineName": MachineIdentity.name,
            "appVersion": appVersion,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw LicenseError.offline }

        switch http.statusCode {
        case 200:
            struct Payload: Decodable {
                let key: String, email: String, machineId: String, activatedAt: String, signature: String
            }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                throw LicenseError.server("The server returned an unexpected response.")
            }
            return LicenseReceipt(key: payload.key, email: payload.email, machineId: payload.machineId,
                                   activatedAt: payload.activatedAt, signature: payload.signature, lastCheckedAt: Date())
        case 404:
            throw LicenseError.invalidKey
        case 403:
            throw LicenseError.revoked
        case 409:
            struct Payload: Decodable { let error: String, machines: [String] }
            let machines = (try? JSONDecoder().decode(Payload.self, from: data))?.machines ?? []
            throw LicenseError.limitReached(machines)
        default:
            struct Payload: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Payload.self, from: data))?.error
                ?? "Something went wrong (\(http.statusCode))."
            throw LicenseError.server(message)
        }
    }
}

/// App-wide license state. `load()` is offline/instant; `activate` and
/// `recheckIfStale` are the only calls that touch the network.
@MainActor
@Observable
final class LicenseStore {
    enum State: Equatable {
        case free
        case licensed(key: String, email: String)
    }

    var state: State = .free
    var showUnlock = false
    var pendingKey: String?

    var isLicensed: Bool {
        if case .licensed = state { true } else { false }
    }

    private var receipt: LicenseReceipt?

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let receipt = try? JSONDecoder().decode(LicenseReceipt.self, from: data),
              ReceiptVerifier.isValid(receipt, machineId: MachineIdentity.id, publicKeyRaw: LicensePublicKey.raw)
        else {
            state = .free
            return
        }
        self.receipt = receipt
        state = .licensed(key: receipt.key, email: receipt.email)
    }

    func activate(rawKey: String) async throws {
        guard let key = LicenseKey.normalize(rawKey) else { throw LicenseError.invalidKey }
        try await refresh(key: key)
    }

    /// Re-validates a licensed receipt roughly weekly, so a revoked or
    /// refunded key eventually stops working even without a relaunch.
    func recheckIfStale() async {
        guard case .licensed = state, let receipt else { return }
        let staleSince = receipt.lastCheckedAt ?? .distantPast
        guard Date().timeIntervalSince(staleSince) > 7 * 24 * 60 * 60 else { return }
        do {
            try await refresh(key: receipt.key)
        } catch LicenseError.invalidKey, LicenseError.revoked {
            clear()
        } catch {
            // Offline, server hiccup, etc. — keep the existing receipt and retry later.
        }
    }

    /// `cleardisk://activate?key=...` from the delivery email.
    func handle(url: URL) {
        guard url.scheme == "cleardisk", url.host == "activate",
              let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "key" })?.value
        else { return }
        pendingKey = key
        showUnlock = true
    }

    @discardableResult
    private func refresh(key: String) async throws -> LicenseReceipt {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let receipt = try await LicenseClient.activate(key: key, appVersion: appVersion)
        guard ReceiptVerifier.isValid(receipt, machineId: MachineIdentity.id, publicKeyRaw: LicensePublicKey.raw) else {
            throw LicenseError.server("The server returned an invalid license receipt.")
        }
        save(receipt)
        self.receipt = receipt
        state = .licensed(key: receipt.key, email: receipt.email)
        return receipt
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClearDisk", isDirectory: true)
            .appendingPathComponent("license.json")
    }

    private func save(_ receipt: LicenseReceipt) {
        writeFile(try? JSONEncoder().encode(receipt))
    }

    /// Clears the license by overwriting with an empty object — never
    /// `removeItem`, which is reserved for `TrashService.deleteForever`.
    private func clear() {
        receipt = nil
        state = .free
        writeFile(Data("{}".utf8))
    }

    private func writeFile(_ data: Data?) {
        guard let data else { return }
        let dir = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }
}
