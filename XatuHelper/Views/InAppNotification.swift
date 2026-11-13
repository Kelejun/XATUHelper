import SwiftUI
import UIKit

private extension InAppNoticeKind {
    var symbol: String {
        switch self {
        case .exam: return "calendar.badge.clock"
        case .grade: return "chart.bar.doc.horizontal.fill"
        case .loginFailure: return "exclamationmark.shield.fill"
        case .sessionExpired: return "clock.badge.exclamationmark.fill"
        }
    }

    var accent: Color {
        switch self {
        case .exam: return .blue
        case .grade: return .teal
        case .loginFailure: return .orange
        case .sessionExpired: return .orange
        }
    }

    var opensDetail: Bool {
        switch self {
        case .exam, .grade: return true
        case .loginFailure, .sessionExpired: return false
        }
    }
}

struct InAppNotificationBanner: View {
    var notice: InAppNotice
    var onTap: () -> Void
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var iconSize = 44
    @State private var dragOffset: CGFloat = 0

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notice.kind.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(notice.kind.accent)
                        .frame(width: iconSize, height: iconSize)
                        .background {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(notice.kind.accent.opacity(colorScheme == .dark ? 0.20 : 0.10).gradient)
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(notice.kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if notice.kind.opensDetail {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        Text(notice.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                }
                .multilineTextAlignment(.leading)
                .padding(.leading, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(notice.kind.opensDetail ? "查看详情" : "关闭通知")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 7)
            .padding(.trailing, 5)
            .accessibilityLabel("关闭通知")
        }
        .background(.regularMaterial, in: shape)
        .overlay {
            shape.strokeBorder(
                Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5
            )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 20, y: 8)
        .offset(y: dragOffset)
        .opacity(1 - min(abs(dragOffset) / 160, 0.6))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    dragOffset = min(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height < -40 || value.predictedEndTranslation.height < -100 {
                        onClose()
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .accessibilityAction(.escape, onClose)
    }
}

/// 在统一顶部通知窗口中展示，支持手势关闭和 6 秒自动收回。
struct InAppNotificationLayer: View {
    static let bannerAnimation = Animation.spring(response: 0.45, dampingFraction: 0.82)

    var notice: InAppNotice
    var onTap: () -> Void
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        InAppNotificationBanner(notice: notice, onTap: onTap, onClose: onClose)
            .frame(maxWidth: 560)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : -18)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.bannerAnimation) {
                    isVisible = true
                }
            }
            .task(id: notice.id) {
                try? await Task.sleep(nanoseconds: 6 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                onClose()
            }
    }
}

#Preview("通知 · 浅色") {
    notificationPreview.preferredColorScheme(.light)
}

#Preview("通知 · 深色大字号") {
    notificationPreview
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility1)
}

private var notificationPreview: some View {
    ScrollView {
        VStack(spacing: 18) {
            InAppNotificationBanner(
                notice: .init(kind: .exam, message: "高等数学、大学英语 等 3 门"),
                onTap: {}, onClose: {}
            )
            InAppNotificationBanner(
                notice: .init(kind: .grade, message: "大学物理 92、线性代数 88"),
                onTap: {}, onClose: {}
            )
            InAppNotificationBanner(
                notice: .init(kind: .loginFailure, message: "可能是因为密码错误、触发验证码等原因"),
                onTap: {}, onClose: {}
            )
            InAppNotificationBanner(
                notice: .init(kind: .sessionExpired, message: "自动重新登录未成功，请手动重新登录"),
                onTap: {}, onClose: {}
            )
        }
        .padding(16)
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
