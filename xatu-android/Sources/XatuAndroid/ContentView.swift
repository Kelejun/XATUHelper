import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) var app

    var body: some View {
        @Bindable var app = app
        Group {
            if app.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.isLoggedIn)
        .overlay(alignment: .top) {
            if let notice = app.inAppNotice {
                InAppNotificationLayer(
                    notice: notice,
                    onTap: {
                        switch notice.kind {
                        case .exam: app.deepLink = .exam
                        case .grade: app.deepLink = .grade
                        }
                        app.dismissNotice()
                    },
                    onClose: { app.dismissNotice() }
                )
                .animation(InAppNotificationLayer.bannerAnimation, value: app.inAppNotice)
            }
        }
        .sheet(item: $app.deepLink) { link in
            NavigationStack {
                Group {
                    switch link {
                    case .exam:
                        ExamView()
                    case .grade:
                        GradeView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("完成") { app.deepLink = nil }
                    }
                }
            }
        }
    }
}
