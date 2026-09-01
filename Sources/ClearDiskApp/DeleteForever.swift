import Core
import SwiftUI

struct DeleteForeverRequest: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
}

struct DestructiveButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(hex: 0xFF3B30).opacity(!enabled ? 0.35 : configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Permanent deletion, gated hard: a warning stage, then type-the-exact-name
/// to unlock the final button. No undo exists past this sheet.
struct DeleteForeverSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let request: DeleteForeverRequest
    var onDeleted: () -> Void

    @State private var stage = 1
    @State private var typed = ""
    @State private var errorMessage: String?

    private var nameMatches: Bool { typed == request.name }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: 0xFF3B30))

            Text(stage == 1 ? "Delete \"\(request.name)\" forever?" : "Type the name to confirm")
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)

            if stage == 1 {
                VStack(spacing: 8) {
                    Text("This skips the Trash entirely. \(fmtBytes(request.size)) will be freed immediately — and there is **no way to undo it**. Gone means gone.")
                        .font(.system(size: 13))
                        .foregroundStyle(UI.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If you're not sure, use Move to Trash instead — it's reversible.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(UI.safeText)
                }
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("I understand, continue") { stage = 2 }
                        .buttonStyle(DestructiveButtonStyle())
                }
            } else {
                VStack(spacing: 10) {
                    Text("To permanently delete it, type exactly:")
                        .font(.system(size: 13))
                        .foregroundStyle(UI.textSecondary)
                    Text(request.name)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: 0xF0F0F2), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                    TextField("", text: $typed, prompt: Text(request.name).foregroundStyle(Color(hex: 0xC7C7CC)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(nameMatches ? Color(hex: 0x34C759) : UI.cardBorder, lineWidth: 1.5))
                        .frame(maxWidth: 320)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: 0xFF3B30))
                    }
                }
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Delete Forever") { performDelete() }
                        .buttonStyle(DestructiveButtonStyle(enabled: nameMatches))
                        .disabled(!nameMatches)
                }
            }
        }
        .padding(28)
        .frame(width: 430)
    }

    private func performDelete() {
        do {
            try TrashService.deleteForever(request.path)
            state.applyRemoval(paths: [request.path], movedToTrash: false)
            state.showToast("Deleted \(request.name) forever — \(fmtBytes(request.size)) freed immediately.")
            onDeleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
