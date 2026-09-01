import Core
import SwiftUI

/// Squarified treemap with nesting, selection + plain-language detail bar,
/// hover highlight + pointer cursor, and crossfade on drill.
/// Single click = select · double click = look inside · Back / ⌘↑ = up.
struct TreemapView: View {
    @Environment(AppState.self) private var state
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
            toolbar

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for item in laidOut {
                            draw(item, in: context)
                        }
                    }

                    if let selected {
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
                .animation(.easeInOut(duration: 0.18), value: currentID)
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
                        withAnimation { proxy.scrollTo(stack.count - 1, anchor: .trailing) }
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
                .background(Color(hex: 0xF0F0F2), in: RoundedRectangle(cornerRadius: 6))
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
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
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

    /// Nine distinct, friendly hues assigned by size rank — adjacent blocks
    /// always contrast. No grays: every block should feel alive.
    private static let palette: [(h: Double, s: Double, b: Double)] = [
        (0.585, 0.72, 0.88), // blue
        (0.075, 0.66, 0.94), // orange
        (0.78, 0.52, 0.84),  // purple
        (0.40, 0.58, 0.74),  // green
        (0.92, 0.50, 0.90),  // pink
        (0.52, 0.58, 0.82),  // teal
        (0.115, 0.58, 0.84), // gold
        (0.67, 0.48, 0.84),  // indigo
        (0.015, 0.55, 0.87), // coral
    ]

    private func hitTest(_ point: CGPoint) -> LaidOutNode? {
        laidOut.last { $0.rect.contains(point) }
    }

    private func relayout() {
        guard let current, canvasSize.width > 10, canvasSize.height > 10 else {
            laidOut = []
            return
        }
        var result: [LaidOutNode] = []
        let frame = CGRect(origin: .zero, size: canvasSize)
        let base = state.scanPath == "/" ? "" : state.scanPath
        let currentPath = base + stack.map { "/" + $0.name }.joined()

        let children = (current.children ?? [])
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
            .prefix(60)
        let level1 = Squarify.layout(sizes: children.map { Double($0.size) }, in: frame)

        for item in level1 {
            let child = children[children.startIndex + item.index]
            let rect = item.rect.insetBy(dx: 2, dy: 2)
            guard rect.width > 3, rect.height > 3 else { continue }

            let hsb = Self.palette[item.index % Self.palette.count]
            let color = Color(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)
            let childPath = currentPath + "/" + child.name
            let canNest = child.isDirectory && !Self.isBundle(child.name)
                && rect.width > 110 && rect.height > 76
            result.append(LaidOutNode(node: child, path: childPath, rect: rect, color: color,
                                      depth: 0, labelVisible: rect.width > 64 && rect.height > 22))

            guard canNest else { continue }
            let inner = CGRect(x: rect.minX + 4, y: rect.minY + 40,
                               width: rect.width - 8, height: rect.height - 44)
            let grandchildren = (child.children ?? [])
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }
                .prefix(24)
            guard !grandchildren.isEmpty else { continue }
            let level2 = Squarify.layout(sizes: grandchildren.map { Double($0.size) }, in: inner)
            for sub in level2 {
                let subRect = sub.rect.insetBy(dx: 1.5, dy: 1.5)
                guard subRect.width > 6, subRect.height > 6 else { continue }
                let grandchild = grandchildren[grandchildren.startIndex + sub.index]
                // Medium tints of the parent hue — light enough to read as
                // "inside", saturated enough for white labels.
                let tint = Color(hue: hsb.h,
                                 saturation: hsb.s * (0.74 - Double(sub.index % 3) * 0.07),
                                 brightness: min(0.97, hsb.b * 1.07))
                result.append(LaidOutNode(node: grandchild, path: childPath + "/" + grandchild.name,
                                          rect: subRect, color: tint, depth: 1,
                                          labelVisible: subRect.width > 68 && subRect.height > 26))
            }
        }
        laidOut = result
    }

    /// Packages the UI treats as leaves — falling into an app bundle's guts
    /// is never what a user wants.
    private static let bundleSuffixes = [".app", ".photoslibrary", ".imovielibrary",
                                         ".fcpbundle", ".framework", ".bundle", ".xcodeproj"]

    private static func isBundle(_ name: String) -> Bool {
        bundleSuffixes.contains { name.hasSuffix($0) }
    }
}
