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

    /// 下拉时的位移，用来做跟手拖动关闭
    @State var dragOffset: CGFloat = 0

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.44, blue: 0.94),
                                     Color(red: 0.32, green: 0.68, blue: 0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

        }
        .buttonStyle(.plain)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    dragOffset = min(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height < -40 {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
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
        .padding(.horizontal, 10)
        .transition(
            .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98, anchor: .top))
        )
        .task(id: notice.id) {
            try? await Task.sleep(nanoseconds: 6 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            onClose()
        }
    }
}
