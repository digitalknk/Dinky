import DinkyConfig
import DinkyLayout

extension WorkspaceSettings {
    /// Translate the configured layout after resolving the display's column limit.
    public func tilingAlgorithm(columns: Columns) -> TilingAlgorithm {
        let expansion: FixedExpansion = switch expand {
        case .rows: .rows
        case .columns: .columns
        case .accordion: .accordion
        }
        return switch layout {
        case .tiles, .dwindle: .dwindle(.tiles)
        case .accordion: .dwindle(.accordion)
        case .fixed: .fixed(rows: rows, columns: self.columns, expand: expansion)
        case .scrolling: .scrolling
        case .columns: .columns(max: maxColumns ?? columns.max, groupByApp: groupByApp ?? columns.groupByApp)
        }
    }
}
