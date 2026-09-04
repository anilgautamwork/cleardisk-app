import AppKit
import Darwin
import SwiftUI

/// macOS has no public Full Disk Access status API. Treat an unsuccessful
/// probe as unconfirmed, not proof of denial: Unix permissions or OS changes
/// can also prevent opening these files. Never read/query the database, and
/// never probe Safari, Mail, iCloud, or another user's personal content.
enum FullDiskAccess {
    static var isConfirmed: Bool {
        let probes = [
            NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        return probes.contains { path in
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard descriptor >= 0 else { return false }
            close(descriptor)
            return true
        }
    }

    @MainActor
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static var isBundledApp: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    /// Launch a fresh instance before closing this one. A failed launch leaves
    /// the current app open and reports an error. Relaunch never starts a scan.
    @MainActor
    static func relaunch(onFailure: @escaping @MainActor (String) -> Void) {
        guard isBundledApp else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
            let launched = app != nil && error == nil
            Task { @MainActor in
                if launched { NSApplication.shared.terminate(nil) }
                else { onFailure("ClearDisk couldn’t reopen. Quit and open it again from Applications.") }
            }
        }
    }
}

/// Inline onboarding. Checking status is read-only and never starts a scan;
/// the user returns from Settings and explicitly chooses Scan my disk.
struct DiskAccessView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    private var confirmed: Bool { state.diskAccessConfirmed }
    @State private var hasChecked = false
    @State private var relaunching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Button { state.leaveDiskAccess() } label: {
                    Label("Back", systemImage: "chevron.left")
                }.buttonStyle(.borderless).tint(UI.accentLight)

                Image(systemName: "internaldrive.fill.badge.checkmark")
                    .font(.system(size: 40, weight: .regular)).foregroundStyle(UI.accentLight)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Allow disk access")
                        .font(.system(size: 34, weight: .semibold))
                    Text("Give ClearDisk Full Disk Access before scanning your disk. You control this in System Settings.")
                        .font(.system(size: 16)).foregroundStyle(UI.textSecondary)
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 20) {
                    step(1, "Open System Settings", detail: "Go to Privacy & Security → Full Disk Access.")
                    step(2, "Turn on ClearDisk", detail: "If ClearDisk isn’t listed, click + and select it from Applications.")
                    step(3, "Come back to ClearDisk", detail: "Once access is detected, choose Scan my disk. If needed, click Check access or relaunch ClearDisk.")
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).card()

                HStack(spacing: 12) {
                    if confirmed {
                        Button("Scan my disk") { state.startScan(path: "/") }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("Open System Settings") { FullDiskAccess.openSettings() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Open System Settings") { FullDiskAccess.openSettings() }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("Check access") { checkAccess() }
                            .buttonStyle(.bordered)
                    }
                    if FullDiskAccess.isBundledApp && !confirmed {
                        Button(relaunching ? "Relaunching…" : "Relaunch ClearDisk") {
                            relaunching = true
                            FullDiskAccess.relaunch {
                                relaunching = false
                                state.showToast($0)
                            }
                        }.buttonStyle(.bordered).disabled(relaunching)
                    }
                }.controlSize(.large).font(.system(size: 14))

                if hasChecked {
                    Label(confirmed ? "Disk access detected. Ready when you are." : "Disk access hasn’t been confirmed yet.",
                          systemImage: confirmed ? "checkmark.circle" : "info.circle")
                        .font(.system(size: 14)).foregroundStyle(confirmed ? UI.safeText : UI.textSecondary)
                        .accessibilityElement(children: .combine)
                }
                Text("A scan only measures files. Nothing is changed or deleted. macOS may still restrict some locations or ask for additional access.")
                    .font(.system(size: 14)).foregroundStyle(UI.textSecondary)
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                if !FullDiskAccess.isBundledApp {
                    Text("Open the installed ClearDisk app to manage its disk access in System Settings.")
                        .font(.system(size: 14)).foregroundStyle(UI.textSecondary)
                }
            }.padding(36).frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .task { checkAccess() }
        .onChange(of: scenePhase) { if scenePhase == .active { checkAccess() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkAccess() }
    }

    private func checkAccess() {
        state.diskAccessConfirmed = FullDiskAccess.isConfirmed
        hasChecked = true
    }

    private func step(_ number: Int, _ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(UI.accentLight).frame(width: 28, height: 28)
                .background(UI.selectedRowBG, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 14)).foregroundStyle(UI.textSecondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
