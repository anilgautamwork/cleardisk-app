import Core
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Divider().overlay(UI.cardBorder)
            Group {
                switch state.phase {
                case .welcome:
                    WelcomeView()
                case .scanning:
                    ScanningView()
                case .done:
                    switch state.section {
                    case .systemData: SystemDataView()
                    case .reclaimable: ReclaimableView()
                    case .categories: CategoriesView()
                    case .treemap: TreemapView()
                    case .largeFiles: LargeFilesView()
                    case .search: SearchView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0xFBFBFD))
        }
        .foregroundStyle(UI.textPrimary)
        .overlay(alignment: .bottom) {
            ToastView()
                .animation(.spring(duration: 0.3), value: state.toast?.id)
        }
        .sheet(isPresented: Bindable(state).fdaSheetPresented) {
            FDASheetView()
        }
        .task {
            if !FullDiskAccess.isBundledApp {
                NSApp.applicationIconImage = AppIcon.image
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var state

    private var usedFraction: Double {
        guard state.volumeTotal > 0 else { return 0 }
        return Double(state.volumeTotal - state.volumeFree) / Double(state.volumeTotal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcon.image)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text("ClearDisk")
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.top, 30)

            // Storage summary card
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(UI.cardBorder, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: usedFraction)
                        .stroke(UI.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(usedFraction * 100))%")
                            .font(.system(size: 17, weight: .bold))
                        Text("full")
                            .font(.system(size: 9))
                            .foregroundStyle(UI.textSecondary)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(spacing: 2) {
                    Text("\(fmtBytes(state.volumeTotal - state.volumeFree)) used of \(fmtBytes(state.volumeTotal))")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("\(fmtBytes(state.volumeFree)) free")
                        .font(.system(size: 12))
                        .foregroundStyle(UI.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .card()

            // Navigation
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppState.Section.allCases) { section in
                    let needsHome = section == .systemData || section == .categories
                    let available = state.phase == .done && (!needsHome || state.homeNode != nil)
                    Button {
                        state.section = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .frame(width: 18)
                            Text(section.rawValue)
                            Spacer()
                        }
                        .font(.system(size: 13, weight: state.section == section ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(state.section == section && state.phase == .done
                                    ? Color(hex: 0xDCDCE1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .opacity(available ? 1 : 0.45)
                    .help(available ? "" :
                          (state.phase == .done
                           ? "Scan your home folder or full Mac to see this"
                           : "Run a scan first"))
                }
            }

            if state.showFDAHint {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\((state.stats?.skippedCount ?? 0).formatted()) items couldn't be read")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Grant Full Disk Access to see everything.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(UI.textSecondary)
                    Button("Grant access") { state.fdaSheetPresented = true }
                        .buttonStyle(.link)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.cardBorder))
            }

            if state.phase == .done && state.trashBytes > 100_000_000 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(fmtBytes(state.trashBytes)) waiting in your Trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(UI.reviewText)
                    Text("The space isn't free until the Trash is emptied.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(UI.textSecondary)
                    Button("Open Trash in Finder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12, weight: .semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(UI.reviewBG, in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            if state.phase == .done {
                Button {
                    state.startScan(path: state.scanPath)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Rescan")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Scanning is free, forever")
                    .font(.system(size: 12, weight: .semibold))
                Text("Cleaning unlocks with a one-time $9.99 purchase. No subscription.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(UI.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.cardBorder))
        }
        .padding(14)
        .frame(width: 248)
        .background(UI.sidebar)
    }
}
