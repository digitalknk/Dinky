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
