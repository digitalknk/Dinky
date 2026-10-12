import CoreGraphics
import DinkyConfig
import DinkyLayout
import Testing
@testable import DinkyCommands

struct WorkspaceLayoutTests {
    @Test func `Configured display limit and workspace grouping reach placement`() throws {
        let config = try Config.parse("""
        default-layout = 'columns'
        [columns]
        max = 4
        [display.'built-in']
        max-columns = 2
        [workspace.1]
        group-by-app = false
        """)
        let monitor = Monitor(name: "Built-in Retina Display", isMain: true, count: 1)
        let algorithm = config.settings(forWorkspace: 1).tilingAlgorithm(columns: config.columns(for: monitor))
        #expect(algorithm == .columns(max: 2, groupByApp: false))
        var workspace = Workspace(bounds: CGRect(x: 0, y: 0, width: 1600, height: 1000), algorithm: algorithm)
        workspace.insert(1, app: "zed")
        workspace.insert(2, app: "zed")
        workspace.insert(3, app: "browser")
        let frames = workspace.layout().frames
        #expect(frames[1]?.minX != frames[2]?.minX)
        #expect(frames[3]?.width == 800)
        #expect(frames[2]?.height == 1000)
    }

    @Test func `Workspace limit takes precedence over display and global settings`() throws {
        let config = try Config.parse("""
        [columns]
        max = 4
        group-by-app = false
        [display.main]
        max-columns = 2
        [workspace.1]
        layout = 'columns'
        max-columns = 3
        group-by-app = true
        """)
        let monitor = Monitor(name: "External", isMain: true, count: 1)
        let algorithm = config.settings(forWorkspace: 1).tilingAlgorithm(columns: config.columns(for: monitor))
        #expect(algorithm == .columns(max: 3, groupByApp: true))
        var workspace = Workspace(bounds: CGRect(x: 0, y: 0, width: 5120, height: 1440), algorithm: algorithm)
        workspace.insert(1, app: "zed")
        workspace.insert(2, app: "browser")
        workspace.insert(3, app: "zed")
        let frames = workspace.layout().frames
        #expect(frames[1]?.minX == frames[3]?.minX)
        #expect(frames[1]?.height == 720)
        #expect(frames[2]?.height == 1440)
    }

    @Test func `Existing layout settings retain their algorithms`() throws {
        let config = try Config.parse("""
        [workspace.1]
        layout = 'fixed'
        rows = 2
        columns = 3
        expand = 'rows'
        [workspace.2]
        layout = 'scrolling'
        [workspace.3]
        layout = 'accordion'
        """)
        #expect(config.settings(forWorkspace: nil).tilingAlgorithm(columns: config.columns) == .dwindle(.tiles))
        #expect(config.settings(forWorkspace: 1).tilingAlgorithm(columns: config.columns) == .fixed(rows: 2, columns: 3, expand: .rows))
        #expect(config.settings(forWorkspace: 2).tilingAlgorithm(columns: config.columns) == .scrolling)
        #expect(config.settings(forWorkspace: 3).tilingAlgorithm(columns: config.columns) == .dwindle(.accordion))
    }
}
