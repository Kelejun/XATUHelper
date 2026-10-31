import SwiftUI

/// Semantic roles shared with the Android MaterialTheme, including dynamic color.
/// Resolve each palette once, outside scroll/recomposition hot paths.
struct MD3Colors {
    let values: [String: String]
    static let light = load(dark: false)
    static let dark = load(dark: true)
    static func scheme(_ scheme: ColorScheme) -> MD3Colors { scheme == .dark ? dark : light }
    private static func load(dark: Bool) -> MD3Colors {
        #if os(Android)
        if let raw = AndroidPlatform.call("materialColors", dark ? "dark" : "light"),
           let data = raw.data(using: .utf8),
           let values = try? JSONDecoder().decode([String: String].self, from: data) {
            return MD3Colors(values: values)
        }
        #endif
        return MD3Colors(values: dark
            ? ["primary":"D0BCFF", "onPrimary":"381E72", "primaryContainer":"4F378B", "onPrimaryContainer":"EADDFF", "surface":"141218", "surfaceContainer":"211F26", "surfaceContainerHigh":"2B2930", "onSurface":"E6E0E9", "onSurfaceVariant":"CAC4D0", "outlineVariant":"49454F", "error":"F2B8B5"]
            : ["primary":"6750A4", "onPrimary":"FFFFFF", "primaryContainer":"EADDFF", "onPrimaryContainer":"21005D", "surface":"FEF7FF", "surfaceContainer":"F3EDF7", "surfaceContainerHigh":"ECE6F0", "onSurface":"1D1B20", "onSurfaceVariant":"49454F", "outlineVariant":"CAC4D0", "error":"B3261E"])
    }
    subscript(_ role: String) -> Color {
        let value = UInt32(values[role] ?? "6750A4", radix: 16) ?? 0x6750A4
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}

enum MD3Type {
    static let headline = Font.system(size: 28, weight: .regular)
    static let title = Font.system(size: 22, weight: .regular)
    static let titleMedium = Font.system(size: 16, weight: .medium)
    static let body = Font.system(size: 16)
    static let bodyMedium = Font.system(size: 14)
    static let label = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12)
}

struct MD3ScreenModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    func body(content: Content) -> some View {
        let colors = MD3Colors.scheme(scheme)
        content.font(MD3Type.body)
            .tint(colors["primary"])
            .background(colors["surface"])
    }
}

struct MD3ListModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    func body(content: Content) -> some View {
        content.listStyle(.plain)
            .scrollContentBackground(.hidden)
            .md3Screen()
    }
}

struct MD3CardModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var prominent: Bool
    func body(content: Content) -> some View {
        let colors = MD3Colors.scheme(scheme)
        content.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors[prominent ? "primaryContainer" : "surfaceContainer"], in: RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func md3Screen() -> some View { modifier(MD3ScreenModifier()) }
    func md3List() -> some View { modifier(MD3ListModifier()) }
    func md3Card(prominent: Bool = false) -> some View { modifier(MD3CardModifier(prominent: prominent)) }
}
