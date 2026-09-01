import Core
import SwiftUI

/// Dev-junk screen: rebuildable caches and build artifacts, whole-directory
/// trashing with per-item checkboxes.
struct ReclaimableView: View {
    @Environment(AppState.self) private var state
    @State private var selected: Set<String> = []
    @State private var initializedFor: Date?
    @State private var confirming = false

    private var items: [DevJunkItem] { state.devJunkItems }

    private var selectedItems: [DevJunkItem] {
        items.filter { selected.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Developer junk that rebuilds itself",
                         subtitle: "Build files and package caches. Everything here comes back automatically when a tool needs it.")

            if items.isEmpty {
                Spacer()
                Text("No developer junk found — clean machine!")
                    .foregroundStyle(UI.textSecondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                actionBar
            }
        }
        .onAppear(perform: seedSelection)
        .onChange(of: state.scanDate) { seedSelection() }
        .sheet(isPresented: $confirming) { confirmSheet }
    }

    private func seedSelection() {
        guard initializedFor != state.scanDate else { return }
        initializedFor = state.scanDate
        selected = Set(items.compactMap { item in
            if case .trashable(let defaultSelected) = item.action, defaultSelected {
                return item.id
            }
            return nil
        })
    }

    @ViewBuilder
    private func row(_ item: DevJunkItem) -> some View {
        let trashable = if case .trashable = item.action { true } else { false }
        let isSelected = selected.contains(item.id)

        HStack(spacing: 14) {
            if trashable {
                Toggle("", isOn: .init(
                    get: { selected.contains(item.id) },
                    set: { on in
                        if on { selected.insert(item.id) } else { selected.remove(item.id) }
                    }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            } else {
                Image(systemName: "info.circle")
                    .foregroundStyle(UI.reviewText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(item.note)
                    .font(.system(size: 12))
                    .foregroundStyle(UI.textSecondary)
                    .lineLimit(2)
                Text(abbreviateHome(item.path))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x98989D))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Review") { state.browse(item.path) }
                .buttonStyle(.link)
                .font(.system(size: 12))

            Text(fmtBytes(item.bytes))
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .frame(width: 82, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected && trashable ? UI.selectedRowBG : Color.white,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected && trashable ? UI.selectedRowBorder : UI.cardBorder))
    }

    private var actionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reclaim \(fmtBytes(selectedBytes))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(UI.safeText)
                Text("Whole folders move to the Trash — undo available right after.")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.textSecondary)
            }
            Spacer()
            Button("Clean Selected") { confirming = true }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .disabled(selectedItems.isEmpty)
                .opacity(selectedItems.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(hex: 0xFBFBFD))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(UI.cardBorder), alignment: .top)
    }

    private var confirmSheet: some View {
        VStack(spacing: 16) {
            Text("Move \(selectedItems.count) folder\(selectedItems.count == 1 ? "" : "s") (\(fmtBytes(selectedBytes))) to the Trash?")
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedItems) { item in
                        HStack {
                            Text(item.title).font(.system(size: 13))
                            Spacer()
                            Text(fmtBytes(item.bytes)).font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 220)
            Label("Everything goes to your Trash — Undo brings it straight back.",
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
        .frame(width: 420)
    }

    private func performClean() {
        var trashedItems: [TrashService.TrashedItem] = []
        var failed = 0
        for item in selectedItems {
            do {
                if let url = try TrashService.trash(item.path) {
                    trashedItems.append(TrashService.TrashedItem(originalPath: item.path, trashURL: url))
                }
            } catch {
                failed += 1
            }
        }
        let cleanedBytes = selectedBytes
        selected.removeAll()
        state.applyRemoval(paths: trashedItems.map(\.originalPath), movedToTrash: true)
        state.showToast("Moved \(trashedItems.count) folders (\(fmtBytes(cleanedBytes))) to the Trash."
                        + (failed > 0 ? " \(failed) skipped." : ""),
                        undo: trashedItems)
    }
}
