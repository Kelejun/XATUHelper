import SwiftUI
import UIKit

/// App 内的通知横幅演示。
/// 用系统材质 + 系统动画曲线，点击打开本 App 的系统设置页。
struct InAppNotificationBanner: View {
    var title: String
    var message: String
    var onTap: () -> Void
    var onClose: () -> Void

    /// 下拉时的位移，用来做跟手拖动关闭
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
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
                    HStack(spacing: 6) {
                        Text("XATU Helper")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Text("现在")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.subheadline)
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
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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

/// 把横幅挂在最上层的容器：进来先播一次，点一下跳系统设置。
struct InAppNotificationHost: View {
    var title: String
    var message: String
    @State private var isShowing = false
    @State private var appeared = false

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                if isShowing {
                    InAppNotificationBanner(
                        title: title,
                        message: message,
                        onTap: openSettings,
                        onClose: dismiss
                    )
                    .padding(.horizontal, 10)
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                }
            }
            .allowsHitTesting(isShowing)
            .task {
                guard !appeared else { return }
                appeared = true
                try? await Task.sleep(nanoseconds: 400 * 1_000_000)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    isShowing = true
                }
                // 6 秒后自动收回去，给用户留够点击时间
                try? await Task.sleep(nanoseconds: 6 * 1_000_000_000)
                if isShowing { dismiss() }
            }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            isShowing = false
        }
    }

    private func openSettings() {
        dismiss()
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
