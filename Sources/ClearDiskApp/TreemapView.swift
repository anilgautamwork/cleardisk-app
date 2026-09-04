import Core
import SwiftUI

/// Squarified treemap with nesting, selection + plain-language detail bar,
/// hover highlight + pointer cursor, and crossfade on drill.
/// Single click = select · double click = look inside · Back / ⌘↑ = up.
struct TreemapView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLayingOut = true
    @State private var layoutRequest = UUID()
    @State private var layoutTask: Task<Void, Never>?
    @State private var snapshotKey: String?
    @State private var snapshotEntries: [TreemapLayout.Entry] = []
    @State private var snapshotNodes: [Int: (FileNode, String)] = [:]
    @State private var stack: [FileNode] = []
    @State private var laidOut: [LaidOutNode] = []
    @State private var canvasSize: CGSize = .zero
    @State private var hovered: LaidOutNode?
    @State private var hoverPoint: CGPoint = .zero
    @State private var selected: LaidOutNode?
    @State private var confirmTrash: LaidOutNode?
    @State private var deleteRequest: DeleteForeverRequest?

    private var current: FileNode? { stack.last ?? state.root }
    private var currentID: ObjectIdentifier? { current.map(ObjectIdentifier.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "Your storage, mapped", subtitle: "Bigger blocks use more space. Explore the largest 60 items in each folder.")
            toolbar

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for item in laidOut {
                            draw(item, in: context)
                        }
                    }

                    if isLayingOut {
                        StorageMapArtwork(active: true)
                            .overlay {
                                VStack(spacing: 10) {
                                    if reduceMotion { Image(systemName: "hourglass").foregroundStyle(UI.accentLight) }
                                    else { ProgressView().controlSize(.small) }
                                    Text("Arranging your storage map")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Calculating blocks for this folder…")
                                        .font(.system(size: 12)).foregroundStyle(UI.textSecondary)
                                }
                                .padding(24).card()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    } else if laidOut.isEmpty {
                        ContentUnavailableView("No measurable files", systemImage: "square.dashed", description: Text("This folder is empty, unreadable, or contains only zero-size files."))
                    }

                    if let selected, !isLayingOut {
                        Path(roundedRect: selected.rect, cornerRadius: selected.depth == 0 ? 8 : 4)
                            .stroke(UI.accent, lineWidth: 3)
                            .allowsHitTesting(false)
                    }
                    if let hovered, hovered.path != selected?.path {
                        Path(roundedRect: hovered.rect, cornerRadius: hovered.depth == 0 ? 8 : 4)
                            .fill(Color.white.opacity(0.14))
                            .allowsHitTesting(false)
                        Path(roundedRect: hovered.rect, cornerRadius: hovered.depth == 0 ? 8 : 4)
                            .stroke(Color.white, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    if let hovered {
                        tooltip(for: hovered, in: geo.size)
                    }
                }
                .id(currentID)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: currentID)
                .onChange(of: geo.size, initial: true) {
                    canvasSize = geo.size
                    relayout()
                }
                .onChange(of: currentID) {
                    selected = nil
                    relayout()
                }
                .onChange(of: state.scanDate) {
                    stack = []
                    selected = nil
                    relayout()
                }
                .onChange(of: state.treeVersion) {
                    validateStack()
                    selected = nil
                    relayout()
                }
                .onChange(of: hovered?.path) {
                    if hovered != nil {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let point):
                        hoverPoint = point
                        hovered = hitTest(point)
                    case .ended:
                        hovered = nil
                    }
                }
                .onTapGesture(count: 2, coordinateSpace: .local) { point in
                    if let hit = hitTest(point) { drill(into: hit) }
                }
                .onTapGesture(coordinateSpace: .local) { point in
                    selected = hitTest(point)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, selected == nil ? 20 : 8)

            if let selected {
                detailBar(for: selected)
            }
        }
        .onDisappear {
            layoutTask?.cancel()
            layoutRequest = UUID()
            NSCursor.arrow.set()
        }
        .confirmationDialog(
            "Move \"\(confirmTrash?.node.name ?? "")\" (\(fmtBytes(confirmTrash?.node.size ?? 0))) to the Trash?",
            isPresented: .init(get: { confirmTrash != nil },
                               set: { if !$0 { confirmTrash = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let item = confirmTrash, let url = try? TrashService.trash(item.path) {
                    let undo = [TrashService.TrashedItem(originalPath: item.path, trashURL: url)]
                    state.applyRemoval(paths: [item.path], movedToTrash: true)
                    state.showToast("Moved \(item.node.name) (\(fmtBytes(item.node.size))) to the Trash.",
                                    undo: undo)
                    selected = nil
                }
                confirmTrash = nil
            }
            Button("Cancel", role: .cancel) { confirmTrash = nil }
        } message: {
            Text("You can put it back from the Trash anytime.")
        }
        .sheet(item: $deleteRequest) { request in
            DeleteForeverSheet(request: request) {
                selected = nil
            }
        }
    }

    // MARK: - toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                if !stack.isEmpty { stack.removeLast() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 12.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(stack.isEmpty)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("Go up one level (⌘↑)")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        breadcrumb(name: abbreviateHome(state.scanPath), depth: 0)
                        ForEach(Array(stack.enumerated()), id: \.offset) { index, node in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundStyle(UI.textSecondary)
                            breadcrumb(name: node.name, depth: index + 1)
                                .id(index)
                        }
                    }
                }
                .onChange(of: stack.count) {
                    if !stack.isEmpty {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(stack.count - 1, anchor: .trailing) }
                    }
                }
            }

            Spacer(minLength: 12)
            Text("Click to select · double-click to look inside")
                .font(.system(size: 12))
                .foregroundStyle(UI.textSecondary)
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func breadcrumb(name: String, depth: Int) -> some View {
        Button {
            stack = Array(stack.prefix(depth))
        } label: {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(UI.elevated, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - interaction

    /// After tree surgery, drop any breadcrumb levels that no longer exist.
    private func validateStack() {
        var parent = state.root
        var valid: [FileNode] = []
        for node in stack {
            guard let children = parent?.children, children.contains(where: { $0 === node }) else { break }
            valid.append(node)
            parent = node
        }
        if valid.count != stack.count {
            stack = valid
        }
    }

    private func drill(into hit: LaidOutNode) {
        if hit.node.isDirectory, !Self.isBundle(hit.node.name),
           !(hit.node.children ?? []).isEmpty {
            if hit.depth == 1, let parent = laidOut.first(where: {
                $0.depth == 0 && $0.rect.contains(CGPoint(x: hit.rect.midX, y: hit.rect.midY))
            }) {
                stack.append(parent.node)
            }
            stack.append(hit.node)
            hovered = nil
        } else {
            revealInFinder(hit.path)
        }
    }

    // MARK: - detail bar

    private func detailBar(for item: LaidOutNode) -> some View {
        let total = current?.size ?? 1
        let share = total > 0 ? Double(item.node.size) / Double(total) * 100 : 0
        let drillable = item.node.isDirectory && !Self.isBundle(item.node.name)
            && !(item.node.children ?? []).isEmpty
        let trashAllowed = TrashService.verdict(forTrashing: item.path) == .allowed

        return HStack(spacing: 14) {
            FileIconChip(name: item.node.name, isDirectory: item.node.isDirectory)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(item.node.name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text("\(fmtBytes(item.node.size)) · \(String(format: "%.1f", share))% of this view")
                        .font(.system(size: 12.5))
                        .foregroundStyle(UI.textSecondary)
                }
                Text(plainDescription(name: item.node.name,
                                      isDirectory: item.node.isDirectory,
                                      childCount: item.node.children?.count ?? 0))
                    .font(.system(size: 12.5))
                    .foregroundStyle(UI.textSecondary)
                    .lineLimit(1)
                Text(abbreviateHome(item.path))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x98989D))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if drillable {
                Button("Look Inside") { drill(into: item) }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
            Button("Reveal in Finder") { revealInFinder(item.path) }
                .buttonStyle(.bordered)
            Button("Move to Trash") { confirmTrash = item }
                .buttonStyle(.bordered)
                .disabled(!trashAllowed)
                .help(trashAllowed ? "Moves to the Trash — undo available"
                      : "Protected location — ClearDisk won't remove this")
            Button("Delete Forever…") {
                deleteRequest = DeleteForeverRequest(name: item.node.name, path: item.path,
                                                     size: item.node.size)
            }
            .buttonStyle(.bordered)
            .foregroundStyle(trashAllowed ? Color(hex: 0xFF3B30) : UI.textSecondary)
            .disabled(!trashAllowed)
            .help(trashAllowed ? "Skips the Trash — frees space immediately, cannot be undone"
                  : "Protected location — ClearDisk won't remove this")
            Button {
                selected = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(UI.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close file details")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .card()
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - drawing

    private func draw(_ item: LaidOutNode, in context: GraphicsContext) {
        let rect = item.rect
        guard rect.width > 1, rect.height > 1 else { return }
        let path = Path(roundedRect: rect, cornerRadius: item.depth == 0 ? 8 : 4)
        context.fill(path, with: .color(item.color))

        guard item.labelVisible else { return }
        var labelContext = context
        labelContext.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5))
        labelContext.draw(
            Text(item.node.name)
                .font(.system(size: item.depth == 0 ? 12.5 : 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white),
            in: CGRect(x: rect.minX + 9, y: rect.minY + 6, width: rect.width - 18, height: 16))
        if rect.height > 40 {
            labelContext.draw(
                Text(fmtBytes(item.node.size))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92)),
                in: CGRect(x: rect.minX + 9, y: rect.minY + 22, width: rect.width - 18, height: 14))
        }
    }

    private func tooltip(for item: LaidOutNode, in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.node.name)
                .font(.system(size: 12.5, weight: .bold))
                .lineLimit(1)
            Text(fmtBytes(item.node.size))
                .font(.system(size: 11.5))
                .foregroundStyle(UI.textSecondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(UI.surface, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .offset(x: min(hoverPoint.x + 14, size.width - 180),
                y: min(hoverPoint.y + 14, max(0, size.height - 56)))
        .allowsHitTesting(false)
    }

    // MARK: - layout

    struct LaidOutNode {
        let node: FileNode
        let path: String
        let rect: CGRect
        let color: Color
        let depth: Int
        let labelVisible: Bool
    }

    /// Jewel tones assigned by size rank. Parent and nested variants keep
    /// white labels readable, including the lighter hover treatment.
    private static let palette: [(h: Double, s: Double, b: Double)] = [
        (0.72, 0.55, 0.54), // violet
        (0.48, 0.70, 0.38), // teal
        (0.095, 0.77, 0.45), // amber
        (0.90, 0.53, 0.51), // mauve
        (0.60, 0.63, 0.53), // slate blue
        (0.39, 0.64, 0.39), // forest
        (0.035, 0.67, 0.51), // terracotta
        (0.66, 0.50, 0.55), // indigo
        (0.82, 0.45, 0.48), // orchid
    ]

    private func hitTest(_ point: CGPoint) -> LaidOutNode? {
        laidOut.last { $0.rect.contains(point) }
    }

    private func relayout() {
        layoutTask?.cancel()
        let request = UUID()
        layoutRequest = request
        hovered = nil
        laidOut = []
        guard let current, canvasSize.width > 10, canvasSize.height > 10 else {
            isLayingOut = false
            return
        }
        isLayingOut = true
        let size = canvasSize
        // A stable snapshot is reused during resize. Mutable FileNodes remain
        // on the main actor, only small value records enter the detached task.
        let base = state.scanPath == "/" ? "" : state.scanPath
        let currentPath = base + stack.map { "/" + $0.name }.joined()
        let version = state.treeVersion
        let key = "\(version):\(currentPath)"
        layoutTask = Task { @MainActor in
            // Coalesce resize bursts and let SwiftUI present loading feedback.
            do { try await Task.sleep(for: .milliseconds(35)) } catch { return }
            guard layoutRequest == request else { return }
            if snapshotKey != key {
                var nodes: [Int: (FileNode, String)] = [:]
                var nextID = 0
                var entries: [TreemapLayout.Entry] = []
                for child in current.largestChildren(limit: 60) {
                    let id = nextID; nextID += 1
                    let path = currentPath + "/" + child.name
                    nodes[id] = (child, path)
                    var children: [TreemapLayout.Entry] = []
                    if child.isDirectory && !Self.isBundle(child.name) {
                        for grandchild in child.largestChildren(limit: 24) {
                            let subID = nextID; nextID += 1
                            nodes[subID] = (grandchild, path + "/" + grandchild.name)
                            children.append(.init(id: subID, size: grandchild.size))
                        }
                    }
                    entries.append(.init(id: id, size: child.size, children: children))
                }
                snapshotNodes = nodes
                snapshotEntries = entries
                snapshotKey = key
            }
            let entries = snapshotEntries
            let worker = Task.detached(priority: .userInitiated) {
                try TreemapLayout.layout(entries: entries, in: CGRect(origin: .zero, size: size))
            }
            do {
                let tiles = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                guard !Task.isCancelled, layoutRequest == request, state.treeVersion == version else { return }
                laidOut = tiles.compactMap { tile in
                    guard let (node, path) = snapshotNodes[tile.id] else { return nil }
                    let hsb = Self.palette[tile.paletteIndex % Self.palette.count]
                    let color = tile.depth == 0
                        ? Color(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)
                        : Color(hue: hsb.h, saturation: hsb.s * (0.94 - Double(tile.tintIndex % 3) * 0.05), brightness: hsb.b * (0.90 + Double(tile.tintIndex % 3) * 0.03))
                    return LaidOutNode(node: node, path: path, rect: tile.rect, color: color, depth: tile.depth,
                                      labelVisible: tile.rect.width > (tile.depth == 0 ? 64 : 68) && tile.rect.height > (tile.depth == 0 ? 22 : 26))
                }
                if let selectedPath = selected?.path {
                    selected = laidOut.first { $0.path == selectedPath }
                }
                isLayingOut = false
            } catch {
                guard layoutRequest == request else { return }
                isLayingOut = false
            }
        }
    }

    /// Packages the UI treats as leaves — falling into an app bundle's guts
    /// is never what a user wants.
    private static let bundleSuffixes = [".app", ".photoslibrary", ".imovielibrary",
                                         ".fcpbundle", ".framework", ".bundle", ".xcodeproj"]

    private static func isBundle(_ name: String) -> Bool {
        bundleSuffixes.contains { name.hasSuffix($0) }
    }
}
