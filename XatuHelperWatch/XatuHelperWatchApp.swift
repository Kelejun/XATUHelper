import SwiftUI
import WatchKit

@main
struct XatuHelperWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var receiver = WatchReceiver.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(receiver)
                .task { receiver.requestLatest() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { receiver.requestLatest() }
                }
        }
    }
}
