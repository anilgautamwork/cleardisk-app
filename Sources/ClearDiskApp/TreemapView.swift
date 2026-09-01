import Core
import SwiftUI

/// Squarified treemap with two-level nesting: each block shows its own
/// contents inside (design-canvas style), distinct hues per block, hover
/// tooltip, click to drill, breadcrumbs to climb out.
struct TreemapView: View {
    @Environment(AppState.self) private var state
    @State private var stack: [FileNode] = []
    @State private var laidOut: [LaidOutNode] = []
    @State private var canvasSize: CGSize = .zero
    @State private var hovered: LaidOutNode?
    @State private var hoverPoint: CGPoint = .zero

    private var current: FileNode? { stack.last ?? state.root }
    private var currentID: ObjectIdentifier? { current.map(ObjectIdentifier.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                Text("Click a block to look inside it")
                    .font(.system(size: 12))
                    .foregroundStyle(UI.textSecondary)
                    .fixedSize()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for item in laidOut {
                            draw(item, in: context)
                        }
                    }

                    // Hover highlight + tooltip.
                    if let hovered {
                        Path(roundedRect: hovered.rect, cornerRadius: hovered.depth == 0 ? 8 : 4)
                            .stroke(Color.white, lineWidth: 2)
                            .allowsHitTesting(false)
                        tooltip(for: hovered, in: geo.size)
                    }
                }
                .onChange(of: geo.size, initial: true) {
                    canvasSize = geo.size
                    relayout()
                }
                .onChange(of: currentID) { relayout() }
                .onChange(of: state.scanDate) {
                    stack = []
                    relayout()
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
                .onTapGesture(coordinateSpace: .local) { point in
                    guard let hit = hitTest(point) else { return }
                    if hit.node.isDirectory, !Self.isBundle(hit.node.name),
                       !(hit.node.children ?? []).isEmpty {
                        // Drilling into a grandchild: push its parent first so
                        // breadcrumbs stay a real path.
                        if hit.depth == 1, let parent = laidOut.first(where: {
                            $0.depth == 0 && $0.rect.contains(point)
                        }) {
                            stack.append(parent.node)
                        }
                        stack.append(hit.node)
                        hovered = nil
                    } else {
                        revealInFinder(hit.path)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - drawing

    private func draw(_ item: LaidOutNode, in context: GraphicsContext) {
        let rect = item.rect
        guard rect.width > 1, rect.height > 1 else { return }
        let path = Path(roundedRect: rect, cornerRadius: item.depth == 0 ? 8 : 4)
        context.fill(path, with: .color(item.color))

        guard item.labelVisible else { return }
        let textColor: Color = .white
        context.draw(
            Text(item.node.name)
                .font(.system(size: item.depth == 0 ? 12 : 10.5, weight: .bold))
                .foregroundStyle(textColor),
            in: CGRect(x: rect.minX + 8, y: rect.minY + 5, width: rect.width - 16, height: 15))
        if rect.height > 36 {
            context.draw(
                Text(fmtBytes(item.node.size))
                    .font(.system(size: 10))
                    .foregroundStyle(textColor.opacity(0.85)),
                in: CGRect(x: rect.minX + 8, y: rect.minY + 20, width: rect.width - 16, height: 13))
        }
    }

    private func tooltip(for item: LaidOutNode, in size: CGSize) -> some View {
        let total = current?.size ?? 1
        let share = total > 0 ? Double(item.node.size) / Double(total) * 100 : 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(item.node.name)
                .font(.system(size: 12.5, weight: .bold))
                .lineLimit(1)
            Text("\(fmtBytes(item.node.size)) · \(String(format: "%.1f", share))% of this view")
                .font(.system(size: 11.5))
                .foregroundStyle(UI.textSecondary)
            if item.node.isDirectory && Self.isBundle(item.node.name) {
                Text("App package — click to show in Finder")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.accent)
            } else if item.node.isDirectory && !(item.node.children ?? []).isEmpty {
                Text("Click to look inside")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.accent)
            } else {
                Text("Click to show in Finder")
                    .font(.system(size: 11))
                    .foregroundStyle(UI.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .frame(maxWidth: 260, alignment: .leading)
        .offset(x: min(hoverPoint.x + 14, size.width - 240),
                y: min(hoverPoint.y + 14, max(0, size.height - 70)))
        .allowsHitTesting(false)
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

    /// Packages the UI treats as leaves — falling into an app bundle's guts
    /// is never what a user wants.
    private static let bundleSuffixes = [".app", ".photoslibrary", ".imovielibrary",
                                         ".fcpbundle", ".framework", ".bundle", ".xcodeproj"]

    private static func isBundle(_ name: String) -> Bool {
        bundleSuffixes.contains { name.hasSuffix($0) }
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

    /// Distinct, design-matched hues assigned by size rank at the top level;
    /// children reuse the parent hue in lighter tints.
    private static let palette: [(h: Double, s: Double, b: Double)] = [
        (0.585, 0.75, 0.85), // blue
        (0.78, 0.55, 0.82),  // purple
        (0.09, 0.68, 0.95),  // orange
        (0.38, 0.62, 0.72),  // green
        (0.55, 0.55, 0.85),  // teal
        (0.93, 0.55, 0.88),  // pink
        (0.68, 0.45, 0.80),  // indigo
        (0.13, 0.55, 0.80),  // gold
        (0.0, 0.0, 0.62),    // gray
        (0.02, 0.60, 0.85),  // red
    ]

    private func hitTest(_ point: CGPoint) -> LaidOutNode? {
        // Deepest rects were appended last — search backwards.
        laidOut.last { $0.rect.contains(point) }
    }

    private func relayout() {
        guard let current, canvasSize.width > 10, canvasSize.height > 10 else {
            laidOut = []
            return
        }
        var result: [LaidOutNode] = []
        let frame = CGRect(origin: .zero, size: canvasSize)
        let isHomeTop = stack.isEmpty && state.isHomeScan
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

            let hsb: (h: Double, s: Double, b: Double)
            if isHomeTop {
                hsb = Self.categoryHSB(Categorizer.displayCategory(forTopLevel: child.name))
            } else {
                hsb = Self.palette[item.index % Self.palette.count]
            }
            let color = Color(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)
            let childPath = currentPath + "/" + child.name
            let canNest = child.isDirectory && !Self.isBundle(child.name)
                && rect.width > 110 && rect.height > 76
            result.append(LaidOutNode(node: child, path: childPath, rect: rect, color: color,
                                      depth: 0, labelVisible: rect.width > 64 && rect.height > 22))

            guard canNest else { continue }
            // Nest the block's own contents beneath its header.
            let inner = CGRect(x: rect.minX + 4, y: rect.minY + 38,
                               width: rect.width - 8, height: rect.height - 42)
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
                let tint = Color(hue: hsb.h,
                                 saturation: max(0.12, hsb.s * (0.55 - Double(sub.index % 3) * 0.09)),
                                 brightness: min(1.0, hsb.b * 1.12))
                result.append(LaidOutNode(node: grandchild, path: childPath + "/" + grandchild.name,
                                          rect: subRect, color: tint, depth: 1,
                                          labelVisible: subRect.width > 68 && subRect.height > 24))
            }
        }
        laidOut = result
    }

    private static func categoryHSB(_ category: Core.Category) -> (h: Double, s: Double, b: Double) {
        switch category {
        case .photosVideos: (0.78, 0.55, 0.85)
        case .music: (0.93, 0.60, 0.92)
        case .documents: (0.55, 0.60, 0.85)
        case .apps: (0.585, 0.80, 0.92)
        case .downloads: (0.38, 0.62, 0.75)
        case .mail: (0.68, 0.50, 0.82)
        case .devJunk: (0.09, 0.70, 0.95)
        case .systemData: (0.0, 0.0, 0.58)
        case .cloud: (0.53, 0.55, 0.90)
        case .trash: (0.0, 0.0, 0.65)
        case .other: (0.0, 0.0, 0.76)
        }
    }
}
