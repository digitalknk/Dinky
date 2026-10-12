import CoreGraphics

extension Workspace {
    /// Automatic placement preserves manual tree edits. If the root no longer represents columns,
    /// the usual focused-leaf insertion handles it until flatten or a config change restores the layout.
    mutating func insertIntoColumns(_ id: WindowID, max: Int, groupByApp: Bool) -> Bool {
        guard root.orientation == .horizontal, root.mode == .tiles else { return false }
        let app = groupByApp ? apps[id] : nil
        let matching = root.children.indices.filter { index in
            guard let app else { return false }
            return root.children[index].windows.contains { apps[$0] == app }
        }
        let focusedColumn = focused.flatMap { root.path(of: $0)?.first }
        let column: Int
        if let existing = matching.first(where: { $0 == focusedColumn }) ?? matching.first {
            column = existing
        } else if root.children.count < max {
            root.insert(.window(id), at: root.children.count)
            return true
        } else {
            // Stable tree order breaks ties so successive overflow windows fill different columns.
            guard let leastCrowded = root.children.indices.min(by: {
                root.children[$0].windows.count < root.children[$1].windows.count
            }) else { return false }
            column = leastCrowded
        }
        let ids = root.children[column].windows
        let sameApp = ids.filter { app != nil && apps[$0] == app }
        let candidates = sameApp.isEmpty ? ids : sameApp
        let layout = tiledLayout()
        guard let target = candidates.max(by: { a, b in
            let first = layout.frames[a] ?? .zero, second = layout.frames[b] ?? .zero
            let firstArea = first.width * first.height, secondArea = second.width * second.height
            if abs(firstArea - secondArea) > 0.01 { return firstArea < secondArea }
            if a == focused { return false }
            if b == focused { return true }
            return candidates.firstIndex(of: a)! > candidates.firstIndex(of: b)!
        }), let path = root.path(of: target), let frame = layout.frames[target] else { return false }
        let columnRect: CGRect = if case .container = root.children[column] {
            rect(at: [column], in: layout)
        } else { frame }
        // A full-height column splits top to bottom first, even on an ultrawide display.
        // Smaller tiles split along their longer side, yielding quarters for the third window.
        let fullHeight = abs(frame.height - columnRect.height) < 0.01
        let axis: Orientation = fullHeight ? .vertical : frame.width >= frame.height ? .horizontal : .vertical
        root.modify(at: Array(path.dropLast())) { parent in
            parent.replace(at: path.last!, with: .container(Container(ContainerOrientation(axis), .tiles,
                [.window(target), .window(id)])))
        }
        return true
    }
}
