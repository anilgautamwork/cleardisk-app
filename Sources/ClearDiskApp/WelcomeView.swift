import Core
import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Label("YOUR MAC. YOUR SPACE.", systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(UI.textSecondary)
                    Spacer()
                    Text("PREVIEW").font(.system(size: 10, weight: .bold)).tracking(1)
                        .foregroundStyle(UI.accentLight).padding(.horizontal, 9).padding(.vertical, 5)
                        .background(UI.selectedRowBG, in: Capsule())
                }
                HStack(alignment: .center, spacing: 30) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Make room for\nwhat’s next.")
                            .font(.system(size: 42, weight: .bold)).tracking(-1.5)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Find the files filling your Mac. Understand System Data. Decide what stays.")
                            .font(.system(size: 15)).foregroundStyle(UI.textSecondary)
                            .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        Button { state.startScan(path: NSHomeDirectory()) } label: {
                            Label("Scan My Home Folder", systemImage: "arrow.up.right")
                        }.buttonStyle(PrimaryButtonStyle())
                        Text("A clear view starts with a read-only scan.")
                            .font(.system(size: 11)).foregroundStyle(UI.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 12) {
                        StorageMapArtwork(active: false).frame(height: 240)
                        HStack(spacing: 6) {
                            Circle().fill(UI.accentLight).frame(width: 5, height: 5)
                            Text("Your storage map appears after scanning")
                                .font(.system(size: 10.5)).foregroundStyle(UI.textSecondary)
                        }
                    }.frame(maxWidth: .infinity).padding(16).card(radius: 16)
                }
                HStack(spacing: 14) {
                    scopeCard("Full Mac", subtitle: "See the bigger picture", icon: "desktopcomputer") {
                        if FullDiskAccess.isGranted { state.startScan(path: "/") }
                        else { state.fdaSheetPresented = true }
                    }
                    scopeCard("Choose a folder", subtitle: "Focus on one location", icon: "folder") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true; panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false; panel.prompt = "Scan"
                        if panel.runModal() == .OK, let url = panel.url { state.startScan(path: url.path) }
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    feature("See the whole picture", "Explore large files and a visual storage map.", "square.grid.2x2")
                    feature("Understand the mystery", "Open System Data into explained categories.", "sparkle.magnifyingglass")
                    feature("Stay in control", "Review every cleanup before anything changes.", "checkmark.shield")
                }.padding(.top, 4)
                Divider().overlay(UI.cardBorder)
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield")
                    Text("Local by design. Your filenames and scan results stay on this Mac.")
                    Spacer()
                }.font(.system(size: 11.5)).foregroundStyle(UI.textSecondary)
            }.padding(36).frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
        }
    }

    private func scopeCard(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(UI.accentLight)
                    .frame(width: 38, height: 38).background(UI.selectedRowBG, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(UI.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(UI.textSecondary)
            }.padding(16).card()
        }.buttonStyle(.plain)
    }

    private func feature(_ title: String, _ text: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(UI.accentLight)
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(UI.textSecondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScanningView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Label("SCAN IN PROGRESS", systemImage: "viewfinder")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(UI.accentLight)
                Spacer()
                Label("Read-only", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(UI.textSecondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(state.scanStage == "Reading files" ? "Finding your space." : "Putting it all together.")
                    .font(.system(size: 36, weight: .bold)).tracking(-1)
                Text("Scanning \(abbreviateHome(state.scanPath))")
                    .font(.system(size: 14)).foregroundStyle(UI.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("STORAGE EXPLORER").font(.system(size: 10, weight: .semibold)).tracking(1)
                        Spacer()
                        Text("Building your map").font(.system(size: 11)).foregroundStyle(UI.textSecondary)
                    }
                    StorageMapArtwork(active: true).frame(minHeight: 200, maxHeight: .infinity)
                    Text("Blocks are a scan illustration. Measured file sizes appear when the scan is complete.")
                        .font(.system(size: 11)).foregroundStyle(UI.textSecondary).lineSpacing(3)
                }.padding(20).card(radius: 16).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        if reduceMotion { Image(systemName: "hourglass").foregroundStyle(UI.accentLight) }
                        else { ProgressView().controlSize(.small) }
                        Text(state.scanStage).font(.system(size: 13, weight: .semibold))
                    }
                    Divider()
                    metric(fmtBytes(state.progressBytes), "allocated space measured", icon: "internaldrive")
                    metric(state.progressFiles.formatted(), "files discovered", icon: "doc.on.doc")
                    Spacer(minLength: 0)
                    Label("Nothing is changed or deleted.", systemImage: "checkmark.shield")
                        .font(.system(size: 11)).foregroundStyle(UI.safeText)
                }.padding(22).frame(width: 245, alignment: .leading).frame(maxHeight: .infinity).card(radius: 16)
            }.frame(maxHeight: 355)
            HStack(spacing: 0) {
                scanStep("01", "Read files", active: state.scanStage == "Reading files")
                Rectangle().fill(UI.cardBorder).frame(height: 1).padding(.horizontal, 18)
                scanStep("02", "Organize storage", active: state.scanStage != "Reading files")
                Rectangle().fill(UI.cardBorder).frame(height: 1).padding(.horizontal, 18)
                scanStep("03", "Ready to explore", active: false)
            }.padding(18).card()
            Spacer(minLength: 0)
        }.padding(36).frame(maxWidth: 1250).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func metric(_ value: String, _ label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 29, weight: .semibold)).tracking(-0.8).monospacedDigit()
            Label(label, systemImage: icon).font(.system(size: 11.5)).foregroundStyle(UI.textSecondary)
        }
    }
    private func scanStep(_ number: String, _ title: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Text(number).font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? UI.accentLight : UI.textSecondary)
                .frame(width: 25, height: 25).background(active ? UI.selectedRowBG : UI.elevated, in: Circle())
            Text(title).font(.system(size: 11.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? UI.textPrimary : UI.textSecondary).fixedSize()
        }
    }
}

/// Abstract storage blocks, never a progress percentage or a fabricated result.
/// The scanning sweep is decorative; Reduce Motion pauses the timeline entirely.
struct StorageMapArtwork: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let blocks: [(CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
        (0, 0, 0.46, 0.57, 0.85), (0.47, 0, 0.30, 0.34, 0.6), (0.78, 0, 0.22, 0.34, 0.3),
        (0.47, 0.36, 0.18, 0.21, 0.42), (0.66, 0.36, 0.34, 0.21, 0.75),
        (0, 0.59, 0.27, 0.41, 0.42), (0.28, 0.59, 0.18, 0.41, 0.25),
        (0.47, 0.59, 0.30, 0.41, 0.55), (0.78, 0.59, 0.22, 0.19, 0.22), (0.78, 0.80, 0.22, 0.20, 0.4)
    ]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active || reduceMotion)) { timeline in
            Canvas { context, size in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
                for (x, y, w, h, opacity) in blocks {
                    let rect = CGRect(x: x * size.width, y: y * size.height, width: w * size.width - 2, height: h * size.height - 2)
                    let path = Path(roundedRect: rect, cornerRadius: 7)
                    context.fill(path, with: .color(UI.accent.opacity(opacity * (active ? 0.52 : 0.72))))
                    context.stroke(path, with: .color(UI.accentLight.opacity(0.2)), lineWidth: 1)
                }
                if active && !reduceMotion {
                    let x = size.width * phase
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(UI.accentLight.opacity(0.7)))
                    context.fill(Path(CGRect(x: max(0, x - 30), y: 0, width: 30, height: size.height)), with: .linearGradient(Gradient(colors: [.clear, UI.accentLight.opacity(0.12)]), startPoint: CGPoint(x: x - 30, y: 0), endPoint: CGPoint(x: x, y: 0)))
                }
            }
        }.accessibilityHidden(true)
    }
}

func abbreviateHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home { return "your home folder" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}
