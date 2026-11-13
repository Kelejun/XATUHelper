import SwiftUI
import UIKit

/// 独立于页面与 sheet 的单一横幅层；不抢键盘焦点，横幅之外的触摸穿透。
struct InAppNotificationPresenter: UIViewRepresentable {
    var notice: InAppNotice?
    var onTap: () -> Void
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NotificationAnchorView {
        let view = NotificationAnchorView()
        view.onWindowChange = { [weak coordinator = context.coordinator] scene in
            coordinator?.attach(to: scene)
        }
        return view
    }

    func updateUIView(_ view: NotificationAnchorView, context: Context) {
        context.coordinator.update(notice: notice, onTap: onTap, onClose: onClose)
        context.coordinator.attach(to: view.window?.windowScene)
    }

    static func dismantleUIView(_ view: NotificationAnchorView, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.hide()
    }

    @MainActor
    final class Coordinator {
        private var window: NotificationBannerWindow?
        private var host: UIHostingController<AnyView>?
        private var notice: InAppNotice?
        private var renderedID: UUID?
        private var onTap: () -> Void = {}
        private var onClose: () -> Void = {}

        func update(notice: InAppNotice?, onTap: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.notice = notice
            self.onTap = onTap
            self.onClose = onClose
            render()
        }

        func attach(to scene: UIWindowScene?) {
            guard let scene else { return }
            if window?.windowScene !== scene {
                hide()
                let window = NotificationBannerWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
                window.backgroundColor = .clear
                window.windowLevel = .alert + 1
                let host = UIHostingController(rootView: AnyView(EmptyView()))
                host.view.backgroundColor = .clear
                window.rootViewController = host
                self.window = window
                self.host = host
            }
            render()
        }

        func hide() {
            window?.isHidden = true
            host?.rootView = AnyView(EmptyView())
            window?.bannerFrame = .zero
            renderedID = nil
        }

        private func render() {
            guard let window, let host else { return }
            guard let notice else { hide(); return }
            guard renderedID != notice.id else { return }
            renderedID = notice.id
            host.rootView = AnyView(
                NotificationWindowContent(notice: notice, onTap: onTap, onClose: onClose) { [weak window] frame in
                    window?.bannerFrame = frame
                }
            )
            // 不调用 makeKeyAndVisible，保持输入框与网页现有的焦点。
            window.isHidden = false
        }
    }
}

final class NotificationAnchorView: UIView {
    var onWindowChange: ((UIWindowScene?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window?.windowScene)
    }
}

final class NotificationBannerWindow: UIWindow {
    var bannerFrame = CGRect.zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bannerFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct NotificationBannerFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct NotificationWindowContent: View {
    let notice: InAppNotice
    let onTap: () -> Void
    let onClose: () -> Void
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        VStack(spacing: 0) {
            InAppNotificationLayer(notice: notice, onTap: onTap, onClose: onClose)
                .id(notice.id)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: NotificationBannerFrameKey.self,
                                               value: geometry.frame(in: .global))
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(NotificationBannerFrameKey.self, perform: onFrameChange)
    }
}
