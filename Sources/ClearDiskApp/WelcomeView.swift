import Core
import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: UI.accent.opacity(0.3), radius: 18, y: 6)

            VStack(spacing: 8) {
                Text("Welcome to ClearDisk")
                    .font(.system(size: 30, weight: .bold))
                Text("See exactly what's using your Mac's storage — including the mysterious \"System Data\" — and safely reclaim the space.")
                    .font(.system(size: 15))
                    .foregroundStyle(UI.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: 10) {
                Button {
                    state.startScan(path: NSHomeDirectory())
                } label: {
                    Text("Scan My Home Folder")
                        .frame(width: 240)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    if FullDiskAccess.isGranted {
                        state.startScan(path: "/")
                    } else {
                        state.fdaSheetPresented = true
                    }
                } label: {
                    Text("Scan Full Mac")
                        .font(.system(size: 13))
                        .frame(width: 260)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Scan"
                    if panel.runModal() == .OK, let url = panel.url {
                        state.startScan(path: url.path)
                    }
                } label: {
                    Text("Choose a Folder…")
                        .font(.system(size: 13))
                        .frame(width: 260)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }

            Text("Preview \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") · Help shape ClearDisk")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(UI.textSecondary)

            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .font(.system(size: 11))
                Text("ClearDisk runs entirely on your Mac. Your files are never uploaded, ever.")
                    .font(.system(size: 12))
            }
            .foregroundStyle(UI.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ScanningView: View {
    @Environment(AppState.self) private var state
    @State private var spin = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(UI.cardBorder, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(UI.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                VStack(spacing: 2) {
                    Text(fmtBytes(state.progressBytes))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("measured")
                        .font(.system(size: 10.5))
                        .foregroundStyle(UI.textSecondary)
                }
            }
            .frame(width: 150, height: 150)
            .onAppear { spin = true }

            Text("Scanning \(abbreviateHome(state.scanPath))…")
                .font(.system(size: 19, weight: .semibold))
            Text("\(state.progressFiles.formatted()) files so far")
                .font(.system(size: 13.5))
                .foregroundStyle(UI.textSecondary)
                .monospacedDigit()
            Text("Nothing is changed or deleted during a scan.")
                .font(.system(size: 12))
                .foregroundStyle(UI.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

func abbreviateHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home { return "your home folder" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}
