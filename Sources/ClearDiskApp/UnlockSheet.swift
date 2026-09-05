import Core
import SwiftUI

/// Presented wherever a free user hits a licensed feature, and from the
/// License… menu item and sidebar card. Reads/writes `LicenseStore` from
/// the environment, wired in by the app scene.
struct UnlockSheet: View {
    var reclaimBytes: Int64? = nil
    var onActivated: () -> Void = {}

    @Environment(LicenseStore.self) private var license
    @Environment(\.dismiss) private var dismiss

    @State private var keyText = ""
    @State private var waitingForPurchase = false
    @State private var activating = false
    @State private var error: LicenseError?
    @State private var licensedEmail: String?

    private var headline: String {
        if let reclaimBytes {
            return "Reclaim \(fmtBytes(reclaimBytes)). Unlock ClearDisk for \(Pricing.display)."
        }
        return "Unlock ClearDisk for \(Pricing.display)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let licensedEmail {
                successRow(email: licensedEmail)
            } else {
                Text(headline)
                    .font(.system(size: 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                bullets
                if waitingForPurchase {
                    Text("Waiting for your key… paste it below or click Activate in the email")
                        .font(.system(size: 13)).foregroundStyle(UI.textSecondary)
                }
                TextField("Paste your license key", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                    .disabled(activating)
                    .onSubmit(activate)
                if let error {
                    errorRow(error)
                }
                actions
            }
        }
        .padding(28).frame(width: 590)
        .onAppear { keyText = license.pendingKey ?? "" }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 10) {
            bullet("One-time payment, no subscription")
            bullet("Use on 3 Macs")
            bullet("30-day money-back")
            bullet("Notarized by Apple, runs entirely offline")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(UI.safeText)
            Text(text).font(.system(size: 14)).foregroundStyle(UI.textSecondary)
        }
    }

    private func errorRow(_ error: LicenseError) -> some View {
        HStack(spacing: 12) {
            Text(error.errorDescription ?? "Something went wrong.")
                .font(.system(size: 13)).foregroundStyle(UI.reviewText)
                .fixedSize(horizontal: false, vertical: true)
            if case .offline = error {
                Button("Retry", action: activate)
                    .buttonStyle(.plain).foregroundStyle(UI.accentLight)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction).disabled(activating)
            Spacer(minLength: 0)
            Button("Buy for \(Pricing.display)") {
                waitingForPurchase = true
                NSWorkspace.shared.open(Pricing.buyURLFromApp)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button {
                activate()
            } label: {
                HStack(spacing: 8) {
                    if activating { ProgressView().controlSize(.small) }
                    Text("Activate")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(activating || keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func successRow(email: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(UI.safeText).font(.system(size: 20))
            Text("You’re all set, licensed to \(email)").font(.system(size: 15, weight: .semibold))
        }
    }

    private func activate() {
        guard !activating else { return }
        error = nil
        activating = true
        let raw = keyText
        Task {
            do {
                try await license.activate(rawKey: raw)
                activating = false
                if case .licensed(_, let email) = license.state {
                    licensedEmail = email
                    try? await Task.sleep(for: .seconds(1))
                    onActivated()
                }
            } catch let licenseError as LicenseError {
                activating = false
                error = licenseError
            } catch {
                activating = false
                self.error = .server(error.localizedDescription)
            }
        }
    }
}
