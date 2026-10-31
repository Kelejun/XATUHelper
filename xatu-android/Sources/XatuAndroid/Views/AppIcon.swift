import SwiftUI

/// Android ships a limited SF Symbols mapping. Keep the remaining symbols as
/// bundled template SVGs so they retain tint and work without network access.
struct AppIcon: View {
    let name: String
    var size: CGFloat = 24
    init(_ name: String, size: CGFloat = 24) { self.name = name; self.size = size }
    var body: some View {
#if os(Android)
        image.resizable().scaledToFit().frame(width: size, height: size)
#else
        Image(systemName: name)
#endif
    }
#if os(Android)
    private var image: Image {
        switch name {
        case "graduationcap.fill": return Image("symbol-school", bundle: .module).renderingMode(.template)
        case "building.columns": return Image("symbol-columns", bundle: .module).renderingMode(.template)
        case "building.columns.fill": return Image("symbol-columns", bundle: .module).renderingMode(.template)
        case "wifi": return Image("symbol-wifi", bundle: .module).renderingMode(.template)
        case "wifi.exclamationmark": return Image("symbol-wifi", bundle: .module).renderingMode(.template)
        case "bolt.fill": return Image("symbol-bolt", bundle: .module).renderingMode(.template)
        case "bolt.slash": return Image("symbol-bolt", bundle: .module).renderingMode(.template)
        case "square.grid.2x2.fill": return Image("symbol-grid", bundle: .module).renderingMode(.template)
        case "doc.text.fill": return Image("symbol-document", bundle: .module).renderingMode(.template)
        case "doc.on.doc": return Image("symbol-copy", bundle: .module).renderingMode(.template)
        case "photo": return Image("symbol-photo", bundle: .module).renderingMode(.template)
        case "yensign": return Image("symbol-money", bundle: .module).renderingMode(.template)
        case "clock": return Image("symbol-clock", bundle: .module).renderingMode(.template)
        case "link.badge.plus": return Image("symbol-link", bundle: .module).renderingMode(.template)
        case "arrow.clockwise": return Image(systemName: "arrow.clockwise.circle")
        case "calendar.badge.clock": return Image(systemName: "calendar")
        case "chart.bar.fill": return Image(systemName: "chart.bar.xaxis")
        case "chart.bar.doc.horizontal": return Image(systemName: "chart.bar.xaxis")
        case "list.bullet.rectangle.fill": return Image(systemName: "list.bullet")
        case "checkmark.seal.fill": return Image(systemName: "checkmark.circle")
        case "line.3.horizontal.decrease.circle": return Image(systemName: "line.3.horizontal")
        case "line.3.horizontal.decrease.circle.fill": return Image(systemName: "line.3.horizontal")
        case "mappin.and.ellipse": return Image(systemName: "location")
        default: return Image(systemName: name)
        }
    }
#endif
}

struct ToolbarIcon: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        AppIcon(name).frame(width: 48, height: 48)
    }
}
