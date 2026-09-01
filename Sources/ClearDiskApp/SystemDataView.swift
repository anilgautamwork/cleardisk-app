import Core
import SwiftUI

/// The hero screen: System Data opened into explained rows with Safe / Review
/// / Leave-it labels, and a trash-only Clean action for the safe ones.
struct SystemDataView: View {
    @Environment(AppState.self) private var state
    @State private var selected: Set<String> = []
    @State private var initialized = false
    @State private var confirming = false

    private var report: SystemDataReport? { state.report }

    private var selectedRows: [SystemDataReport.Row] {
        (report?.rows ?? []).filter { selected.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedRows.reduce(0) { $0 + ($1.bytes ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let report {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(report.rows) { row in
                            rowView(row)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                actionBar(report)
            } else {
                Spacer()
                Text("System Data breakdown needs a home-folder scan.")
                    .foregroundStyle(UI.textSecondary)
                Spacer()
            }
        }
        .onAppear {
            if !initialized, let report {
                selected = Set(report.rows.filter { $0.safety == .safe && ($0.bytes ?? 0) > 0 }.map(\.id))
                initialized = true
            }
        }
        .sheet(isPresented: $confirming) {
            confirmSheet
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(fmtBytes(report?.totalBytes ?? 0))
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-0.8)
                Text("of System Data & hidden files — here's exactly what's inside.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(UI.textSecondary)
            }
            compositionBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    /// Safe / review / leave-alone shares of the total, at a glance.
    @ViewBuilder
    private var compositionBar: some View {
        if let report, report.totalBytes > 0 {
            let safe = Double(report.safeBytes)
            let review = Double(report.rows.filter { $0.safety == .review }
                .reduce(Int64(0)) { $0 + ($1.bytes ?? 0) })
            let leave = Double(report.totalBytes) - safe - review
            let total = Double(report.totalBytes)
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Color(hex: 0x34C759).frame(width: max(3, geo.size.width * safe / total))
                        Color(hex: 0xFF9F0A).frame(width: max(3, geo.size.width * review / total))
                        Color(hex: 0xC7C7CC)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                HStack(spacing: 16) {
                    legendDot(Color(hex: 0x34C759), "Safe to clean · \(fmtBytes(report.safeBytes))")
                    legendDot(Color(hex: 0xFF9F0A), "Worth a look · \(fmtBytes(Int64(review)))")
                    legendDot(Color(hex: 0xC7C7CC), "Leave alone · \(fmtBytes(Int64(max(0, leave))))")
                }
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(UI.textSecondary)
        }
    }

    @ViewBuilder
    private func rowView(_ row: SystemDataReport.Row) -> some View {
        let isSafe = row.safety == .safe && (row.bytes ?? 0) > 0
        let isSelected = selected.contains(row.id)

        HStack(spacing: 14) {
            if isSafe {
                Toggle("", isOn: .init(
                    get: { selected.contains(row.id) },
                    set: { on in
                        if on { selected.insert(row.id) } else { selected.remove(row.id) }
                    }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            } else {
                Spacer().frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(row.safety == .leaveIt ? UI.textSecondary : UI.textPrimary)
                Text(row.detail ?? row.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(UI.textSecondary)
                    .lineLimit(1)
                    .help(row.explanation)
            }

            Spacer()

            if let path = row.revealPath, row.safety == .review {
                Button("Review files") { state.browse(path) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }

            Text(row.bytes.map(fmtBytes) ?? "—")
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .frame(width: 82, alignment: .trailing)

            SafetyPill(safety: row.safety)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected && isSafe ? UI.selectedRowBG : Color.white,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected && isSafe ? UI.selectedRowBorder : UI.cardBorder))
    }

    private func actionBar(_ report: SystemDataReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("You can safely reclaim \(fmtBytes(selectedBytes))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(UI.safeText)
                Text("Files move to the Trash — you can always put them back.")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.textSecondary)
            }
            Spacer()
            Button("Clean Safely — reclaim \(fmtBytes(selectedBytes))") { confirming = true }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .disabled(selectedRows.isEmpty)
                .opacity(selectedRows.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(hex: 0xFBFBFD))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(UI.cardBorder), alignment: .top)
    }

    private var confirmSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 26))
                .foregroundStyle(UI.accent)
                .padding(14)
                .background(Color(hex: 0xEEF4FF), in: RoundedRectangle(cornerRadius: 14))

            Text("Move \(selectedRows.count) group\(selectedRows.count == 1 ? "" : "s") to the Trash?")
                .font(.system(size: 17, weight: .bold))

            VStack(spacing: 0) {
                ForEach(selectedRows) { row in
                    HStack {
                        Text(row.title).font(.system(size: 13))
                        Spacer()
                        Text(row.bytes.map(fmtBytes) ?? "—")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    if row.id != selectedRows.last?.id {
                        Divider()
                    }
                }
                Divider()
                HStack {
                    Text("Total to reclaim").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text(fmtBytes(selectedBytes))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(UI.safeText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: 0xFBFBFD))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UI.cardBorder))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Label("Nothing is permanently deleted. Everything goes to your Trash.",
                  systemImage: "checkmark.shield")
                .font(.system(size: 12.5))
                .foregroundStyle(UI.safeText)

            HStack {
                Button("Cancel") { confirming = false }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    confirming = false
                    performClean()
                }
                .buttonStyle(.borderedProminent)
                .tint(UI.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 440)
    }

    private func performClean() {
        var trashedItems: [TrashService.TrashedItem] = []
        var failed = 0
        for row in selectedRows {
            for root in row.cleanRoots {
                let result = TrashService.trashContents(of: root)
                trashedItems.append(contentsOf: result.trashed)
                failed += result.failed
            }
        }
        let reclaimed = selectedBytes
        state.applyRemoval(paths: trashedItems.map(\.originalPath), movedToTrash: true)
        state.showToast("Moved \(trashedItems.count) items (\(fmtBytes(reclaimed))) to the Trash."
                        + (failed > 0 ? " \(failed) skipped (in use or protected)." : "")
                        + " Empty the Trash to finish freeing the space.",
                        undo: trashedItems)
    }
}
