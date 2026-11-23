#if os(watchOS)
import SwiftUI

extension View {
    func watchCapsule(tint: Color) -> some View {
        modifier(WatchCapsuleStyle(tint: tint))
    }
}

private struct WatchCapsuleStyle: ViewModifier {
    let tint: Color
    @ScaledMetric private var fontSize: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
    }
}
#endif
