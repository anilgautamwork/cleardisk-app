import Core
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(UI.canvas)
        }
        .transaction { if reduceMotion { $0.animation = nil } }
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
                        : hovering && isAvailable ? UI.elevated : .clear,
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(nsImage: AppIcon.image)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text("ClearDisk")
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.top, 30)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "internaldrive").foregroundStyle(UI.accentLight)
                    Text("Macintosh HD").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fmtBytes(state.volumeFree)).font(.system(size: 25, weight: .semibold)).tracking(-0.7)
                    Text("free").font(.system(size: 11)).foregroundStyle(UI.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(UI.elevated)
                        Capsule().fill(UI.accent).frame(width: geo.size.width * min(1, max(0, usedFraction)))
                    }
                }.frame(height: 5)
                Text("\(Int(usedFraction * 100))% used · \(fmtBytes(state.volumeTotal)) total")
                    .font(.system(size: 10.5)).foregroundStyle(UI.textSecondary)
            }.padding(15).card()

            Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(UI.textSecondary).padding(.leading, 10).padding(.top, 6)

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
                .background(UI.surface, in: RoundedRectangle(cornerRadius: 10))
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
            .background(UI.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.cardBorder))
        }
        .padding(14)
        .frame(width: 220)
        .background(UI.sidebar)
    }
}
