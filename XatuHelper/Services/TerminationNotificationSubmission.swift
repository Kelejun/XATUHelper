import Foundation

/// 退出前只短暂等待通知提交；完成回调和超时写状态时互斥，避免晚到的成功被覆盖。
final class TerminationNotificationSubmission: @unchecked Sendable {
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var finished = false

    func complete(recordResult: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        recordResult()
        finished = true
        completion.signal()
    }

    func wait(timeout: TimeInterval, onTimeout: () -> Void) {
        guard completion.wait(timeout: .now() + timeout) == .timedOut else { return }
        // 若完成回调正在写结果，直接返回，不能为抢锁延长退出等待。
        guard lock.try() else { return }
        defer { lock.unlock() }
        if !finished { onTimeout() }
    }
}
