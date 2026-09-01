import Core
import SwiftUI

struct CategoriesView: View {
    @Environment(AppState.self) private var state

    private var scannedTotal: Int64 {
        state.categoryTotals.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where your \(fmtBytes(scannedTotal)) lives")
                    .font(.system(size: 26, weight: .bold))
                Text("Plain-language groups, no file paths to decode.")
                    .font(.system(size: 14))
                    .foregroundStyle(UI.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            // Proportional bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(state.categoryTotals) { total in
                        UI.color(for: total.category)
                            .frame(width: max(2, geo.size.width * fraction(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                          spacing: 14) {
                    ForEach(state.categoryTotals) { total in
                        card(total)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func fraction(_ total: CategoryTotal) -> Double {
        scannedTotal > 0 ? Double(total.bytes) / Double(scannedTotal) : 0
    }

    private func card(_ total: CategoryTotal) -> some View {
        let action = cardAction(for: total.category)
        return Button {
            action?.perform()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(UI.color(for: total.category))
                        .frame(width: 10, height: 10)
                    Text(total.category.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(UI.textSecondary)
                }
                Text(fmtBytes(total.bytes))
                    .font(.system(size: 26, weight: .bold))
                Text(UI.blurb(for: total.category))
                    .font(.system(size: 12))
                    .foregroundStyle(UI.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Text(action.label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(UI.accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .card()
        .disabled(action == nil)
    }

    private struct CardAction {
        let label: String
        let perform: () -> Void
    }

    /// Every card leads somewhere: a review screen inside the app.
    private func cardAction(for category: Core.Category) -> CardAction? {
        switch category {
        case .systemData:
            return CardAction(label: "See what's inside") { state.section = .systemData }
        case .devJunk:
            return CardAction(label: "See what's reclaimable") { state.section = .reclaimable }
        default:
            let home = NSHomeDirectory()
            let path: String? = switch category {
            case .photosVideos: home + "/Pictures"
            case .music: home + "/Music"
            case .documents: home + "/Documents"
            case .downloads: home + "/Downloads"
            case .apps: home + "/Applications"
            case .mail: home + "/Library/Mail"
            case .cloud: home + "/Library/CloudStorage"
            case .trash: home + "/.Trash"
            default: nil
            }
            guard let path, let root = state.root,
                  TreeSurgery.chain(for: path, root: root, scanPath: state.scanPath) != nil else {
                return nil
            }
            return CardAction(label: "Review files") { state.browse(path) }
        }
    }
}
