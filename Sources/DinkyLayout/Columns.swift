import CoreGraphics

extension Workspace {
    var linksAppGroups: Bool {
        guard case .columns(_, true) = algorithm else { return false }
        return root.orientation == .horizontal && root.mode == .tiles
    }

    /// Repair app cohorts separated by earlier tree edits without rebuilding unrelated columns.
    @discardableResult
    public mutating func enforceAppGroups() -> Bool {
        guard linksAppGroups else { return false }
        let identities = windows.compactMap { apps[$0] }.reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        var changed = false
        for app in identities {
            let cohorts = root.children.indices.filter { index in
                root.children[index].windows.contains { apps[$0] == app }
            }
            guard cohorts.count > 1 else { continue }
            let focusedColumn = focused.flatMap { apps[$0] == app ? root.path(of: $0)?.first : nil }
            let destination = focusedColumn ?? cohorts.min {
                root.children[$0].windows.filter { apps[$0] == app }.count
                    > root.children[$1].windows.filter { apps[$0] == app }.count
            }!
            for source in cohorts where source != destination {
                let ids = Set(root.children[source].windows.filter { apps[$0] == app })
                let group = root.children[source].selecting(ids)!
                let remaining = root.children[source].selecting(Set(root.children[source].windows).subtracting(ids))
                root.replace(at: source, with: remaining ?? Self.emptyCell)
                root.replace(at: destination, with: .container(Container(.vertical, .tiles,
                    [root.children[destination], group])))
            }
            changed = true
        }
        if changed {
            normalize()
            if let focused { focus(focused) }
        }
        return changed
    }

    /// A mouse swap or cross-column keyboard move exchanges complete app cohorts, even in mixed columns.
    mutating func swapAppGroups(_ first: WindowID, _ second: WindowID) -> Bool {
        guard let a = root.path(of: first)?.first, let b = root.path(of: second)?.first, a != b else { return false }
        let firstIDs = groupMembers(first, in: a), secondIDs = groupMembers(second, in: b)
        let firstGroup = root.children[a].selecting(firstIDs)!, secondGroup = root.children[b].selecting(secondIDs)!
        root.replace(at: a, with: root.children[a].replacing(firstIDs, with: secondGroup)!)
        root.replace(at: b, with: root.children[b].replacing(secondIDs, with: firstGroup)!)
        normalize()
        if let focused { focus(focused) }
        return true
    }

    mutating func moveAppGroup(_ direction: Direction) -> Bool {
        guard let focused, let target = neighbor(of: focused, direction) else { return false }
        return swap(focused, target)
    }

    mutating func joinAppGroup(_ direction: Direction) -> Bool? {
        guard let focused, let path = root.path(of: focused) else { return nil }
        // Join follows the actual container axes, including minimum-size adjustments. A virtual
        // focus neighbour can be in this column even when the structural join crosses its edge.
        let layout = tiledLayout(), offset = direction.isForward ? 1 : -1
        guard let depth = path.indices.last(where: { depth in
            let prefix = Array(path.prefix(depth))
            return axisOfContainer(at: prefix, in: layout) == direction.orientation
                && root.container(at: prefix).children.indices.contains(path[depth] + offset)
        }) else { return nil }
        let target = Array(path.prefix(depth)) + [path[depth] + offset]
        let source = path[0], destination = target[0]
        guard source != destination else { return nil }
        let ids = groupMembers(focused, in: source)
        let group = root.children[source].selecting(ids)!
        let remaining = root.children[source].selecting(Set(root.children[source].windows).subtracting(ids))
        root.replace(at: source, with: remaining ?? Self.emptyCell)
        let pair = direction.isForward ? [group, root.children[destination]] : [root.children[destination], group]
        root.replace(at: destination, with: .container(Container(.vertical, .tiles, pair)))
        normalize()
        focus(focused)
        return true
    }

    private func groupMembers(_ id: WindowID, in column: Int) -> Set<WindowID> {
        guard let app = apps[id] else { return [id] }
        return Set(root.children[column].windows.filter { apps[$0] == app })
    }

    /// Automatic placement preserves manual tree edits. If the root no longer represents columns,
    /// the usual focused-leaf insertion handles it until flatten or a config change restores the layout.
    mutating func insertIntoColumns(_ id: WindowID, max: Int, groupByApp: Bool) -> Bool {
        guard root.orientation == .horizontal, root.mode == .tiles else { return false }
        if groupByApp { enforceAppGroups() }
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

private extension Node {
    /// Project a cohort out of a mixed column, retaining its nested orientation and relative ratios.
    func selecting(_ ids: Set<WindowID>) -> Node? {
        switch self {
        case .window(let id): return ids.contains(id) ? self : nil
        case .container(var c):
            for index in c.children.indices.reversed() {
                if let selected = c.children[index].selecting(ids) { c.replace(at: index, with: selected) }
                else { c.remove(at: index) }
            }
            if c.children.isEmpty { return nil }
            return c.children.count == 1 ? c.children[0] : .container(c)
        }
    }

    /// Replace a cohort at its first occupied subtree, removing its other leaves.
    func replacing(_ ids: Set<WindowID>, with group: Node) -> Node? {
        var inserted = false
        func visit(_ node: Node) -> Node? {
            guard !Set(node.windows).isDisjoint(with: ids) else { return node }
            if Set(node.windows).isSubset(of: ids) {
                guard !inserted else { return nil }
                inserted = true
                return group
            }
            guard case .container(var c) = node else { return nil }
            // Visit in tree order, then remove in reverse so indices and ratios remain valid.
            let children = c.children.map(visit)
            for index in children.indices.reversed() {
                if let child = children[index] { c.replace(at: index, with: child) }
                else { c.remove(at: index) }
            }
            return c.children.count == 1 ? c.children[0] : .container(c)
        }
        return visit(self)
    }
}
