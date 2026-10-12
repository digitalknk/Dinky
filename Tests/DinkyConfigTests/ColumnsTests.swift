import Testing
@testable import DinkyConfig

struct ColumnsTests {
    @Test func `Columns are opt in and defaults preserve existing layouts`() throws {
        let empty = try Config.parse("")
        #expect(empty.defaultLayout == .tiles)
        #expect(empty.columns.max == 3)
        #expect(empty.columns.groupByApp)
        #expect(empty.settings(forWorkspace: 1).maxColumns == nil)
        #expect(empty.settings(forWorkspace: 1).groupByApp == nil)
        #expect(try Config.parse(Config.defaultTOML).columns == empty.columns)
        let configured = try Config.parse("[columns]\nmax = 4\ngroup-by-app = false\n")
        #expect(configured.defaultLayout == .tiles)
        #expect(configured.columns.max == 4)
        #expect(!configured.columns.groupByApp)
    }

    @Test func `Workspace column options resolve layout inheritance`() throws {
        let config = try Config.parse("""
        default-layout = 'columns'
        [columns]
        max = 4
        [workspace.1]
        max-columns = 2
        group-by-app = false
        [workspace.2]
        layout = 'tiles'
        [workspace.3]
        layout = 'columns'
        """)
        let first = config.settings(forWorkspace: 1)
        #expect(first.layout == .columns)
        #expect(first.maxColumns == 2)
        #expect(first.groupByApp == false)
        #expect(config.settings(forWorkspace: 2).layout == .tiles)
        #expect(config.settings(forWorkspace: 3).maxColumns == nil)
        #expect(config.settings(forWorkspace: 3).groupByApp == nil)
        #expect(config.settings(forWorkspace: nil).layout == .columns)
        #expect(config.settings(forWorkspace: 4).maxColumns == nil)
    }

    @Test func `Display column overrides follow gap specificity`() throws {
        let config = try Config.parse("""
        [columns]
        max = 4
        group-by-app = false
        [display.'built-in retina']
        max-columns = 2
        [display.main]
        max-columns = 6
        [display.'built-in']
        max-columns = 3
        [display.secondary]
        max-columns = 5
        [display.dell]
        gaps.inner = 12
        """)
        let builtIn = Monitor(name: "Built-in Retina Display", isMain: true, count: 2)
        let dell = Monitor(name: "DELL U2723QE", isMain: false, count: 2)
        let unmatched = Monitor(name: "LG", isMain: false, count: 3)
        #expect(config.columns(for: builtIn).max == 2, "longer name wins even if declared first")
        #expect(!config.columns(for: builtIn).groupByApp)
        #expect(config.columns(for: dell).max == 5, "a gap-only override preserves the column setting")
        #expect(config.gaps(for: dell).inner == Inner(12))
        #expect(config.columns(for: unmatched) == config.columns)
    }

    @Test func `Invalid column settings fail with their paths`() {
        assertError("[columns]\nmax = 0\n", path: "columns.max", line: 2, contains: "at least 1")
        assertError("[columns]\nmax = 'four'\n", path: "columns.max", line: 2, contains: "expected an integer")
        assertError("[columns]\ngroup-by-app = 1\n", path: "columns.group-by-app", line: 2, contains: "expected true or false")
        assertError("[columns]\nmaximum = 4\n", path: "columns.maximum", line: 2, contains: "unknown key")
        assertError("[display.main]\nmax-columns = -1\n", path: "display.main.max-columns", line: 2, contains: "at least 1")
        assertError("[display.main]\nmax-columns = true\n", path: "display.main.max-columns", line: 2, contains: "expected an integer")
        assertError("[workspace.1]\nlayout = 'columns'\nmax-columns = 0\n", path: "workspace.1.max-columns", line: 3, contains: "at least 1")
        assertError("[workspace.1]\nlayout = 'columns'\ngroup-by-app = 'yes'\n", path: "workspace.1.group-by-app", line: 3, contains: "expected true or false")
        assertError("[workspace.1]\nmax-columns = 3\n", path: "workspace.1.max-columns", line: 2, contains: "only valid for a columns layout")
        assertError("[workspace.1]\nlayout = 'fixed'\ngroup-by-app = false\n", path: "workspace.1.group-by-app", line: 3, contains: "only valid for a columns layout")
        assertError("[workspace.1]\nlayout = 'columns'\ncolumns = 2\n", path: "workspace.1.columns", line: 3, contains: "only valid for a fixed layout")
    }
}
