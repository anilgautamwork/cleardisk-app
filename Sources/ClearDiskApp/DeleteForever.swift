import Core
import SwiftUI

/// Immutable selection captured when the removal dialog opens.
struct RemovalRequest: Identifiable {
    struct Row: Identifiable {
        let id: String
        let name: String
        let size: Int64
    }
    let id = UUID()
    let rows: [Row]
    let targets: [RemovalBatch.Target]
    var contentsOnly = false

    static func item(name: String, path: String, size: Int64) -> Self {
        Self(rows: [Row(id: path, name: name, size: size)],
             targets: [.init(path: path)])
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(hex: 0xC53232).opacity(!enabled ? 0.4 : configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Every cleanup entry point uses the same two choices. Permanent removal
/// requires a deliberate choice and exact typed confirmation, never Return.
struct RemovalConfirmationSheet: View {
    @Environment(AppState.self) private var state
    @Environment(LicenseStore.self) private var license
    @Environment(\.dismiss) private var dismiss
    let request: RemovalRequest
    var onRemoved: ([String]) -> Void = { _ in }
    @State private var confirmingPermanent = false
    @State private var typed = ""
    @State private var working = false
    @State private var outcome: RemovalBatch.Result?
    @FocusState private var typing: Bool
    @State private var gated: Bool? = nil          // pinned on first render
    @State private var unlockedHere = false        // set by UnlockSheet.onActivated

    private var matches: Bool { RemovalBatch.confirmationMatches(typed) }
    private var selectedBytes: Int64 { request.rows.reduce(0) { $0 + $1.size } }

    var body: some View {
        let showGate = (gated ?? !license.isLicensed) && !unlockedHere
        Group {
            if showGate {
                UnlockSheet(reclaimBytes: selectedBytes, onActivated: { unlockedHere = true })
            } else {
                confirmation
            }
        }
        .onAppear { if gated == nil { gated = !license.isLicensed } }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 13) {
                Image(systemName: confirmingPermanent ? "exclamationmark.triangle.fill" : "trash")
                    .font(.system(size: 25))
                    .foregroundStyle(confirmingPermanent ? Color(hex: 0xFF7979) : UI.accentLight)
                VStack(alignment: .leading, spacing: 5) {
                    Text(confirmingPermanent ? "Confirm permanent removal" : "How would you like to remove these items?")
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(request.rows.count) selected · \(fmtBytes(selectedBytes)) at last scan")
                        .font(.system(size: 13)).foregroundStyle(UI.textSecondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(request.rows) { row in
                        HStack(alignment: .top, spacing: 16) {
                            Text(row.name).font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 10)
                            Text(fmtBytes(row.size)).font(.system(size: 14, weight: .semibold))
                                .monospacedDigit().fixedSize()
                        }
                    }
                }.padding(16)
            }.frame(maxHeight: 180).background(UI.elevated, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 12) {
                explanation("Move to Trash", "Undo is available while the items remain in Trash. Empty Trash later to reclaim space.", icon: "arrow.uturn.backward", color: UI.safeText)
                explanation("Remove Permanently", "Skips the Trash. This cannot be undone.", icon: "exclamationmark.triangle", color: Color(hex: 0xFF7979))
                if request.contentsOnly {
                    Text("Only the contents of the selected groups are removed. Their container folders stay in place.")
                        .font(.system(size: 13)).foregroundStyle(UI.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if confirmingPermanent && outcome == nil {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Type delete to confirm permanent removal:")
                        .font(.system(size: 14)).foregroundStyle(UI.textSecondary)
                    Text("delete")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    TextField("delete", text: $typed)
                        .textFieldStyle(.roundedBorder).font(.system(size: 14))
                        .focused($typing).disabled(working)
                        .accessibilityLabel("Type delete to confirm permanent removal")
                }
            }
            if working {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Removing selected items…") }
                    .font(.system(size: 14)).accessibilityElement(children: .combine)
            }
            if let outcome {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(outcome.removedPaths.count) removed. \(outcome.failures.count) could not be removed.")
                        .font(.system(size: 14, weight: .semibold))
                    ScrollView {
                        Text(outcome.failures.joined(separator: "\n"))
                            .font(.system(size: 13)).foregroundStyle(UI.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                }
            }
            HStack(spacing: 12) {
                Button(outcome == nil ? "Cancel" : "Close") { dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(working)
                Spacer(minLength: 0)
                Button("Remove Permanently", role: .destructive) {
                    if confirmingPermanent { perform(.permanently) }
                    else { confirmingPermanent = true; typed = ""; typing = true }
                }
                .buttonStyle(DestructiveButtonStyle(enabled: !working && outcome == nil && (!confirmingPermanent || matches)))
                .disabled(working || outcome != nil || (confirmingPermanent && !matches))
                Button("Move to Trash") { perform(.trash) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(working || outcome != nil)
            }
        }
        .padding(28).frame(width: 590)
        .interactiveDismissDisabled(working)
    }

    private func explanation(_ title: String, _ detail: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
                Text(detail).font(.system(size: 14)).foregroundStyle(UI.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func perform(_ method: RemovalBatch.Method) {
        guard !working, outcome == nil, !request.targets.isEmpty else { return }
        if method == .permanently { guard confirmingPermanent, matches else { return } }
        working = true
        state.activeRemovals += 1
        let targets = request.targets
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                RemovalBatch.perform(targets: targets, method: method)
            }.value
            working = false
            state.activeRemovals -= 1
            if !result.removedPaths.isEmpty {
                state.applyRemoval(paths: result.removedPaths, movedToTrash: method == .trash)
                onRemoved(result.removedPaths)
                let message = method == .trash
                    ? "Moved \(result.removedPaths.count) items to the Trash. Empty Trash later to reclaim space."
                    : "Permanently removed \(result.removedPaths.count) items."
                state.showToast(message, undo: method == .trash && !result.trashedItems.isEmpty ? result.trashedItems : nil)
            }
            if result.failures.isEmpty {
                if result.removedPaths.isEmpty { state.showToast("No remaining items were found in this selection.") }
                dismiss()
            } else { outcome = result }
        }
    }
}
