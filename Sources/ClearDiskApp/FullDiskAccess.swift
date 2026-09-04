import AppKit
import SwiftUI

/// No API tells you whether Full Disk Access is granted — probing
/// TCC-protected paths is the standard technique.
enum FullDiskAccess {
    static var isGranted: Bool {
        let home = NSHomeDirectory()
        let probes = [
            home + "/Library/Safari",
            home + "/Library/Application Support/com.apple.TCC",
            "/Library/Application Support/com.apple.TCC",
        ]
        return probes.contains { (try? FileManager.default.contentsOfDirectory(atPath: $0)) != nil }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static var isBundledApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// FDA applies to freshly launched processes — relaunch after granting.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", path]
        try? open.run()
        NSApplication.shared.terminate(nil)
    }
}

/// The permission walkthrough from the design canvas: numbered steps, deep
/// link, live status while the user flips the switch.
struct FDASheetView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var granted = FullDiskAccess.isGranted

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: granted ? "checkmark.shield.fill" : "shield")
                    .font(.system(size: 22))
                    .foregroundStyle(granted ? Color(hex: 0x34C759) : UI.accent)
                Text(granted ? "Full Disk Access granted" : "One permission needed to see everything")
                    .font(.system(size: 16, weight: .bold))
            }

            if granted {
                Text("You're all set — scan the whole Mac whenever you like.")
                    .font(.system(size: 13))
                    .foregroundStyle(UI.textSecondary)
                Button {
                    dismiss()
                    state.startScan(path: "/")
                } label: {
                    Text("Scan Full Mac")
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(UI.accent)
            } else {
                Text("macOS hides system folders from apps by default. Granting Full Disk Access lets ClearDisk measure all of your storage — it takes about 20 seconds and nothing is ever uploaded.")
                    .font(.system(size: 13))
                    .foregroundStyle(UI.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Click **Open System Settings** below")
                    step(2, "Turn on the switch next to **ClearDisk** (use + to add it if it isn't listed)")
                    step(3, FullDiskAccess.isBundledApp
                         ? "Come back and hit **Relaunch** — macOS applies the permission to fresh launches"
                         : "Quit and reopen ClearDisk — macOS applies the permission to fresh launches")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        FullDiskAccess.openSettings()
                    } label: {
                        Text("Open System Settings")
                            .font(.system(size: 13.5, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(UI.accent)

                    if FullDiskAccess.isBundledApp {
                        Button("Relaunch ClearDisk") { FullDiskAccess.relaunch() }
                    }
                    Button("Not now") { dismiss() }
                }
            }
        }
        .padding(26)
        .frame(width: 470)
        .task {
            while !Task.isCancelled {
                granted = FullDiskAccess.isGranted
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(UI.accentLight)
                .frame(width: 22, height: 22)
                .background(UI.selectedRowBG, in: Circle())
            Text(.init(text))
                .font(.system(size: 13))
        }
    }
}
