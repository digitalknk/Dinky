import CoreGraphics
import Testing
@testable import DinkyLayout

private func columns(_ max: Int = 4, grouping: Bool = true) -> Workspace {
    Workspace(bounds: rect(0, 0, 5120, 1440), algorithm: .columns(max: max, groupByApp: grouping))
}

struct ColumnsTests {
    @Test func `Unique apps fill full height columns before overflow`() {
        for cap in [3, 4] {
            var ws = columns(cap)
            for id in 1...cap { ws.insert(WindowID(id), app: "app-\(id)") }
            #expect(ws.root.children.count == cap)
            for frame in ws.layout().frames.values {
                #expect(frame.height == 1440)
                #expect(abs(frame.width - 5120 / CGFloat(cap)) < 1)
            }
            ws.insert(10, app: "extra")
            #expect(ws.root.children.count == cap)
            #expect(ws.layout().frames[1]!.height == 720)
            #expect(ws.layout().frames[10]!.height == 720)
            #expect(ws.layout().frames[2]!.height == 1440)
        }
    }

    @Test func `Same app groups regardless of unrelated focus and third window makes quarters`() {
        var ws = columns()
        ws.insert(1, app: "zed")
        ws.insert(2, app: "browser")
        ws.insert(3, app: "codex")
        ws.insert(4, app: "zed")
        #expect(shape(ws.root) == "h[v[1 4] 2 3]")
        #expect(ws.layout().frames[1]!.height == 720)
        ws.focus(3)
        ws.insert(5, app: "zed")
        #expect(shape(ws.root) == "h[v[h[1 5] 4] 2 3]")
        #expect(ws.layout().frames[1]!.height == 720)
        #expect(abs(ws.layout().frames[1]!.width - 5120 / 6) < 1)
        #expect(ws.layout().frames[2]!.height == 1440)
        #expect(ws.focused == 5)
    }

    @Test func `Largest tile wins before focus and focus breaks equal area ties`() {
        var ws = columns()
        ws.insert(1, app: "zed")
        ws.insert(2, app: "other")
        ws.insert(3, app: "zed")
        ws.insert(4, app: "zed")
        #expect(shape(ws.root) == "h[v[1 h[3 4]] 2]")
        ws.insert(5, app: "zed")
        #expect(shape(ws.root) == "h[v[h[1 5] h[3 4]] 2]")
    }

    @Test func `Overflow fills least crowded columns in stable order`() {
        var ws = columns(3)
        for id: WindowID in 1...6 { ws.insert(id, app: "app-\(id)") }
        #expect(ws.root.children.map { $0.windows.count } == [2, 2, 2])
        ws.insert(7, app: "seventh")
        #expect(ws.root.children.map { $0.windows.count } == [3, 2, 2])
    }

    @Test func `Removing a half tile keeps remaining quarters in their column`() {
        var ws = columns()
        ws.insert(1, app: "zed")
        ws.insert(2, app: "other")
        ws.insert(3, app: "zed")
        ws.insert(4, app: "zed")
        ws.remove(1)
        #expect(shape(ws.root) == "h[h[3 4] 2]")
        #expect(ws.root.children.count == 2)
        #expect(ws.layout().frames[3]!.width == 1280)
        ws.remove(2)
        #expect(shape(ws.root) == "h[h[3 4]]")
        ws.insert(5, app: "new")
        #expect(ws.root.children.count == 2)
    }

    @Test func `Replacement transfers identity and removal clears it`() {
        var ws = columns()
        ws.insert(1, app: "zed")
        ws.replace(1, with: 2)
        ws.insert(3, app: "zed")
        #expect(ws.root.children.count == 1)
        #expect(ws.apps[1] == nil)
        #expect(ws.apps[2] == "zed")
        ws.remove(2)
        #expect(ws.apps[2] == nil)
        ws.insert(2)
        #expect(ws.root.children.count == 2)
    }

    @Test func `Algorithm change and flatten retain identity and focus`() {
        var ws = workspace(4)
        for id: WindowID in 1...4 { ws.setApp("app-\(id)", for: id) }
        ws.focus(2)
        ws.setAlgorithm(.columns(max: 3, groupByApp: true))
        #expect(ws.root.children.count == 3)
        #expect(ws.focused == 2)
        ws.setAlgorithm(.columns(max: 2, groupByApp: true))
        #expect(ws.root.children.count == 2)
        #expect(ws.focused == 2)
        ws.insert(5, app: "app-2")
        #expect(ws.root.path(of: 5)?.first == ws.root.path(of: 2)?.first)
        ws.focus(2)
        ws.flatten()
        #expect(ws.focused == 2)
        #expect(ws.root.children.count == 2)
        #expect(ws.apps[5] == "app-2")
    }

    @Test func `Unknown identities and disabled grouping do not combine early`() {
        var unknown = columns()
        unknown.insert(1)
        unknown.insert(2)
        unknown.insert(3, app: "")
        #expect(unknown.root.children.count == 3)
        var disabled = columns(grouping: false)
        disabled.insert(1, app: "zed")
        disabled.insert(2, app: "zed")
        #expect(disabled.root.children.count == 2)
    }

    @Test func `Commands preserve manual geometry until flatten`() {
        var ws = columns()
        ws.insert(1, app: "zed")
        ws.insert(2, app: "other")
        let joined = ws.join(.left)
        #expect(joined)
        #expect(shape(ws.root) == "h[v[1 2]]")
        ws.insert(3, app: "new")
        #expect(shape(ws.root) == "h[v[1 2] 3]")
        ws.setOrientation(.vertical)
        #expect(ws.root.orientation == .vertical)
        ws.insert(4, app: "fourth")
        #expect(ws.windows.count == 4)
        ws.flatten()
        #expect(ws.root.orientation == .horizontal)
        #expect(ws.root.children.count == 4)
    }

    @Test func `Existing algorithms ignore app placement metadata`() {
        var ws = workspace(0)
        ws.insert(1, app: "same")
        ws.insert(2, app: "same")
        #expect(shape(ws.root) == "h[1 2]")
        ws.setAlgorithm(.scrolling)
        ws.insert(3, app: "same")
        #expect(ws.root.children.count == 3)
    }

    @Test func `Gaps minimum sizes resizing and fullscreen still apply`() {
        var ws = columns(3)
        ws.gaps = Gaps(all: 8)
        ws.insert(1, app: "zed")
        ws.insert(2, app: "other")
        ws.insert(3, app: "zed")
        ws.minimumSizes[1] = CGSize(width: 300, height: 900)
        #expect(ws.layout().frames[1]!.height >= 900)
        #expect(ws.layout().frames[1]!.minX == 8)
        let resized = ws.resize(by: 100, along: .horizontal)
        #expect(resized)
        ws.toggleFullscreen()
        #expect(ws.layout().frames[3] == rect(8, 8, 5104, 1424))
        ws.balanceSizes()
        #expect(ws.fullscreen == nil)
    }
}

struct LinkedAppGroupTests {
    private func sample(_ grouping: Bool = true) -> Workspace {
        var ws = columns(4, grouping: grouping)
        ws.insert(1, app: "editor")
        ws.insert(2, app: "browser")
        ws.insert(3, app: "chat")
        ws.insert(4, app: "editor")
        ws.insert(5, app: "editor")
        return ws
    }

    @Test func `Mouse swap exchanges complete three window app with target`() {
        var ws = sample()
        ws.focus(4)
        let editor = ws.root.children[0]
        let result1 = ws.swap(4, 3)
        #expect(result1)
        #expect(ws.root.children[0].windows == [3])
        #expect(ws.root.children[2] == editor)
        #expect(ws.focused == 4)
        #expect(Set(ws.windows) == Set([1, 2, 3, 4, 5]))
        #expect(ws.windows.count == 5)
    }

    @Test func `Mixed overflow columns exchange app members without moving unrelated apps`() {
        var ws = columns(2)
        ws.insert(1, app: "editor")
        ws.insert(2, app: "browser")
        ws.insert(3, app: "editor")
        ws.insert(4, app: "chat")
        ws.insert(5, app: "terminal")
        #expect(ws.root.children.map { Set($0.windows) } == [Set([1, 3, 5]), Set([2, 4])])
        let result2 = ws.swap(1, 2)
        #expect(result2)
        #expect(Set(ws.root.children[0].windows) == Set([2, 5]))
        #expect(Set(ws.root.children[1].windows) == Set([1, 3, 4]))
        #expect(ws.windows.count == Set(ws.windows).count)
        #expect(ws.focused == 5)
    }

    @Test func `Keyboard moves keep app cohort and same column movement reorders tiles`() {
        var ws = sample()
        ws.focus(1)
        let result3 = ws.move(.right)
        #expect(result3)
        #expect(Set(ws.root.children[1].windows) == Set([1, 4, 5]))
        #expect(ws.root.children[0].windows == [2])
        #expect(ws.focused == 1)
        let result4 = ws.move(.down)
        #expect(result4)
        #expect(Set(ws.root.children[1].windows) == Set([1, 4, 5]))
        #expect(ws.root.path(of: 4)?.first == ws.root.path(of: 1)?.first)
    }

    @Test func `Join transfers whole group and leaves source overflow app behind`() {
        var ws = columns(2)
        ws.insert(1, app: "editor")
        ws.insert(2, app: "browser")
        ws.insert(3, app: "editor")
        ws.insert(4, app: "chat")
        ws.insert(5, app: "terminal")
        ws.focus(3)
        let result5 = ws.join(.right)
        #expect(result5)
        #expect(ws.root.children[0].windows == [5])
        #expect(Set(ws.root.children[1].windows) == Set([1, 2, 3, 4]))
        #expect(ws.focused == 3)
    }

    @Test func `Same column mouse swap keeps ratios and app membership`() {
        var ws = sample()
        let ratios = ws.root.ratios
        let result6 = ws.swap(1, 4)
        #expect(result6)
        #expect(ws.root.ratios == ratios)
        #expect(Set(ws.root.children[0].windows) == Set([1, 4, 5]))
        #expect(ws.focused == 5)
    }

    @Test func `Grouping false permits independent windows across columns`() {
        var ws = sample(false)
        let result7 = ws.swap(1, 3)
        #expect(result7)
        #expect(ws.root.path(of: 1)?.first != ws.root.path(of: 4)?.first)
        #expect(ws.root.children[0].windows == [3, 5])
    }

    @Test func `Repair focuses existing cohort and preserves unrelated column widths`() {
        var ws = columns()
        ws.root = Container(.horizontal, .tiles, [
            .container(Container(.vertical, .tiles, [.window(1), .window(2)])),
            .window(3),
            .container(Container(.vertical, .tiles, [.window(4), .window(5)]))])
        ws.root.setRatios([0.2, 0.3, 0.5])
        for id: WindowID in [1, 3, 4] { ws.setApp("editor", for: id) }
        ws.setApp("browser", for: 2)
        ws.setApp("chat", for: 5)
        ws.focus(3)
        let repaired = ws.enforceAppGroups()
        #expect(repaired)
        #expect(ws.root.children[0].windows == [2])
        #expect(Set(ws.root.children[1].windows) == Set([1, 3, 4]))
        #expect(ws.root.children[2].windows == [5])
        #expect(ws.root.ratios == [0.2, 0.3, 0.5])
        #expect(ws.focused == 3)
        let once = ws
        let repairedAgain = ws.enforceAppGroups()
        #expect(!repairedAgain)
        #expect(ws == once)
    }

    @Test func `Repair chooses largest cohort then first column and insertion repairs metadata`() {
        var ws = columns()
        ws.root = Container(.horizontal, .tiles, [.window(1),
            .container(Container(.vertical, .tiles, [.window(2), .window(3)])), .window(4)])
        for id: WindowID in [1, 2, 3] { ws.setApp("editor", for: id) }
        ws.focus(4)
        let repaired = ws.enforceAppGroups()
        #expect(repaired)
        #expect(Set(ws.root.children[0].windows) == Set([1, 2, 3]))
        #expect(ws.root.children[1].windows == [4])
        ws.setApp("editor", for: 4)
        ws.insert(5, app: "editor")
        #expect(ws.root.children.count == 1)
        #expect(ws.windows.count == 5)
        #expect(ws.focused == 5)

        var tie = columns()
        tie.root = Container(.horizontal, .tiles, [.window(1), .window(2), .window(3)])
        tie.setApp("editor", for: 1)
        tie.setApp("editor", for: 3)
        tie.focus(2)
        tie.enforceAppGroups()
        #expect(Set(tie.root.children[0].windows) == Set([1, 3]))
        #expect(tie.root.children[1].windows == [2])
    }

    @Test func `Unknown and disabled grouping are not repaired and reinsertion regroups`() {
        var ws = sample()
        ws.remove(4)
        #expect(ws.apps[4] == nil)
        ws.insert(4, app: "editor")
        #expect(ws.root.path(of: 4)?.first == ws.root.path(of: 1)?.first)
        ws.replace(4, with: 6)
        #expect(ws.apps[6] == "editor")
        ws.insert(7, app: "editor")
        #expect(ws.root.path(of: 7)?.first == ws.root.path(of: 6)?.first)
        var unknown = columns()
        unknown.insert(1)
        unknown.insert(2, app: "")
        let unchanged = unknown.enforceAppGroups()
        #expect(!unchanged)
        #expect(unknown.root.children.count == 2)
        var disabled = sample(false)
        let disabledRepair = disabled.enforceAppGroups()
        #expect(!disabledRepair)
        var normal = workspace(3)
        for id: WindowID in 1...3 { normal.setApp("editor", for: id) }
        let original = normal
        let normalRepair = normal.enforceAppGroups()
        #expect(!normalRepair)
        #expect(normal == original)
    }

    @Test func `Repair returns true even when commands have no valid target`() {
        func separated() -> Workspace {
            var ws = columns()
            ws.root = Container(.horizontal, .tiles, [.window(1), .window(2), .window(3)])
            ws.setApp("editor", for: 1)
            ws.setApp("editor", for: 3)
            ws.focus(2)
            return ws
        }
        var moved = separated()
        let moveResult = moved.move(.up)
        #expect(moveResult)
        #expect(moved.root.path(of: 1)?.first == moved.root.path(of: 3)?.first)
        var joined = separated()
        let joinResult = joined.join(.up)
        #expect(joinResult)
        #expect(joined.root.path(of: 1)?.first == joined.root.path(of: 3)?.first)
        var swapped = separated()
        let swapResult = swapped.swap(2, 99)
        #expect(swapResult)
        #expect(swapped.root.path(of: 1)?.first == swapped.root.path(of: 3)?.first)
    }

    @Test func `Join uses actual auto orientation when minimum widths change virtual neighbor`() {
        var ws = Workspace(bounds: rect(0, 0, 3000, 1000), gaps: Gaps(all: 24),
                           algorithm: .columns(max: 4, groupByApp: true))
        ws.root = Container(.horizontal, .tiles, [.window(1),
            .container(Container(.auto, .tiles, [.window(2), .window(3)])), .window(4)])
        ws.setApp("browser", for: 2)
        ws.setApp("browser", for: 3)
        ws.minimumSizes[1] = CGSize(width: 1347, height: 0)
        ws.focus(2)
        #expect(ws.neighbor(of: 2, .right) == 3)
        let joined = ws.join(.right)
        #expect(joined)
        #expect(ws.root.children[0].windows == [1])
        #expect(Set(ws.root.children[1].windows) == Set([2, 3, 4]))
        #expect(ws.root.children.count == 2)
        #expect(ws.windows.count == 4)
        #expect(ws.focused == 2)
    }

}
