import Core
import SwiftUI

/// Dev-junk screen: rebuildable caches and build artifacts, whole-directory
/// removal with per-item checkboxes.
struct ReclaimableView: View {
    @Environment(AppState.self) private var state
    @State private var selected: Set<String> = []
    @State private var initializedFor: Date?
    @State private var removalRequest: RemovalRequest?

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
        .sheet(item: $removalRequest) { request in
            RemovalConfirmationSheet(request: request) { _ in selected.removeAll() }
        }
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
        .background(isSelected && trashable ? UI.selectedRowBG : UI.surface,
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
                Text("Choose Move to Trash or Remove Permanently.")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.textSecondary)
            }
            Spacer()
            Button("Clean Selected") { prepareRemoval() }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .disabled(selectedItems.isEmpty)
                .opacity(selectedItems.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(UI.canvas)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(UI.cardBorder), alignment: .top)
    }

    private func prepareRemoval() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        removalRequest = RemovalRequest(
            rows: items.map { .init(id: $0.id, name: $0.title, size: $0.bytes) },
            targets: items.map { .init(path: $0.path) },
            confirmationText: items.count == 1 ? (items[0].path as NSString).lastPathComponent : "DELETE")
    }
}
