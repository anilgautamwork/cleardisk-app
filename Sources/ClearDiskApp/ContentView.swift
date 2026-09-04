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
                    Group {
                        switch state.section {
                        case .systemData: SystemDataView()
                        case .reclaimable: ReclaimableView()
                        case .categories: CategoriesView()
                        case .browse: BrowserView()
                        case .treemap: TreemapView()
                        case .largeFiles: LargeFilesView()
                        case .search: SearchView()
                        }
                    }
                    .id(state.section)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: state.section)
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

/// Full-width clickable nav row: the ENTIRE row is the hit area (contentShape),
/// with a hover tint so it responds before the click even lands.
struct SidebarNavRow: View {
    let section: AppState.Section
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .frame(width: 18)
                Text(section.rawValue)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? UI.selectedRowBorder
                        : hovering && isAvailable ? Color(hex: 0xE9E9EE) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
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
                    SidebarNavRow(section: section,
                                  isSelected: state.section == section && state.phase == .done,
                                  isAvailable: available) {
                        state.section = section
                    }
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
                Text("1.0 cleanup license: \(Pricing.display) once at launch. This preview has no license activation.")
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
