import Foundation
import Combine
import WatchConnectivity
import WatchKit
import WidgetKit

@MainActor
final class WatchReceiver: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchReceiver()
    @Published private(set) var cache = WatchStore.read()
    @Published private(set) var storageError: String?
    private let session = WCSession.default
    private var pendingTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var contentObservation: NSKeyValueObservation?

    override private init() {
        super.init()
        #if DEBUG
        if WatchPreview.enabled {
            cache = WatchCache(descriptor: WatchSyncDescriptor(WatchPreview.snapshot), snapshot: WatchPreview.snapshot)
        }
        #endif
    }

    func displayDate(_ date: Date) -> Date {
        #if DEBUG
        if WatchPreview.enabled { return WatchPreview.now }
        #endif
        return date
    }

    var snapshot: WatchSnapshot { cache.snapshot ?? .empty }
    var waitingForData: Bool { cache.descriptor?.loggedIn == true && cache.snapshot == nil }

    func start() {
        #if DEBUG
        if WatchPreview.enabled { return }
        #endif
        guard WCSession.isSupported(), session.delegate == nil else { return }
        session.delegate = self
        contentObservation = session.observe(\.hasContentPending, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.finishBackgroundTasks() }
        }
        session.activate()
    }

    func requestLatest() {
        start()
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "snapshot"], replyHandler: { [weak self] reply in
            Task { @MainActor in self?.receive(context: reply) }
        }, errorHandler: { _ in /* Cached data remains available while the phone is unreachable. */ })
    }

    func acceptBackgroundTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        pendingTasks.append(task)
        start()
        finishBackgroundTasks()
    }

    private func finishBackgroundTasks() {
        guard session.activationState == .activated, !session.hasContentPending else { return }
        for task in pendingTasks { task.setTaskCompletedWithSnapshot(false) }
        pendingTasks.removeAll()
    }

    private func save(_ value: WatchCache) {
        cache = value
        do {
            try WatchStore.write(value)
            storageError = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            storageError = "数据暂未保存，请重新打开 App 同步"
        }
    }

    private func receive(data: Data) {
        defer { finishBackgroundTasks() }
        guard let snapshot = try? PropertyListDecoder().decode(WatchSnapshot.self, from: data) else { return }
        var updated = cache
        if updated.receive(snapshot) { save(updated) }
    }

    private func receive(context: [String: Any]) {
        // Process descriptor first so an account switch clears old content immediately.
        if let data = context["descriptor"] as? Data,
           let descriptor = try? PropertyListDecoder().decode(WatchSyncDescriptor.self, from: data) {
            var updated = cache
            if updated.receive(descriptor) { save(updated) }
        }
        if let data = context["snapshot"] as? Data { receive(data: data) }
        finishBackgroundTasks()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.receive(context: context)
            self.requestLatest()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(context: applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WCSession removes the temporary file as soon as this delegate method returns.
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in self.receive(data: data) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.requestLatest() }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in WatchReceiver.shared.start() }
    }
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        Task { @MainActor in
            for task in backgroundTasks {
                if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                    WatchReceiver.shared.acceptBackgroundTask(connectivityTask)
                } else {
                    task.setTaskCompletedWithSnapshot(false)
                }
            }
        }
    }
}
