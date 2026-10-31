import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// App 内的通知横幅演示。
/// 用系统材质 + 系统动画曲线，点击打开本 App 的系统设置页。
struct InAppNotificationBanner: View {
    var title: String
    var message: String
    var onTap: () -> Void
    var onClose: () -> Void

    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        let colors = MD3Colors.scheme(colorScheme)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(MD3Type.titleMedium)
                Text(message).font(MD3Type.bodyMedium).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("查看", action: onTap)
                .font(MD3Type.label).frame(minWidth: 48, minHeight: 48)
            Button(action: onClose) { AppIcon("xmark", size: 20).frame(width: 48, height: 48) }
                .accessibilityLabel("关闭通知")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .foregroundStyle(colors["surface"])
        .background(colors["onSurface"], in: RoundedRectangle(cornerRadius: 4))
    }
}

/// 挂在根视图上的容器：负责出现/消失的同一条动画，和 6 秒自动收回。
struct InAppNotificationLayer: View {
    static let bannerAnimation = Animation.spring(response: 0.45, dampingFraction: 0.82)

    var notice: InAppNotice
    var onTap: () -> Void
    var onClose: () -> Void

    var body: some View {
        InAppNotificationBanner(
            title: notice.kind.title,
            message: notice.message,
            onTap: onTap,
            onClose: onClose
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 88)
        .transition(
            .move(edge: .bottom)
                .combined(with: .opacity)

        )
        .task(id: notice.id) {
            try? await Task.sleep(nanoseconds: 6 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }
}
