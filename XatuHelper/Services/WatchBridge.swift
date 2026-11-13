import Foundation
import Combine
import WatchConnectivity

@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()
    private weak var app: AppState?
    private var observation: AnyCancellable?
    private var latest: WatchSnapshot?
    private var lastContent: WatchSnapshot?
    private var pendingData: Data?
    private let session = WCSession.default

    func start(app: AppState) {
        guard !app.isDemoMode, WCSession.isSupported() else { return }
        if self.app !== app {
            self.app = app
            observation = app.objectWillChange
                .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in self?.publish() }
        }
        if session.delegate == nil {
            session.delegate = self
            session.activate()
        }
        publish()
    }

    func publish(force: Bool = false) {
        guard let app, !app.isDemoMode else { return }
        var snapshot = app.makeWatchSnapshot()
        // Ignore transient loading/UI changes when the synchronized content did not change.
        snapshot.generatedAt = .distantPast
        guard force || snapshot != lastContent else { return }
        lastContent = snapshot
        snapshot.generatedAt = Date()
        latest = snapshot
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        pendingData = try? encoder.encode(snapshot)
        sendLatest()
    }

    private func sendLatest() {
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let snapshot = latest, let data = pendingData else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let descriptor = try? encoder.encode(WatchSyncDescriptor(snapshot)) else { return }
        var context: [String: Any] = ["descriptor": descriptor]
        // Application context has a limited payload; large semesters travel as files.
        if data.count < 48_000 { context["snapshot"] = data }
        do {
            try session.updateApplicationContext(context)
            for transfer in session.outstandingFileTransfers { transfer.cancel() }
            if data.count >= 48_000 {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("watch-sync", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("plist")
                try data.write(to: url, options: .atomic)
                session.transferFile(url, metadata: nil)
            }
        } catch {
            // Keep latest in memory; activation, foreground, and watch requests retry it.
            NSLog("Watch sync pending: %@", error.localizedDescription)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.sendLatest() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendLatest() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.publish(force: true)
            var reply: [String: Any] = [:]
            if let latest = self.latest {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                reply["descriptor"] = try? encoder.encode(WatchSyncDescriptor(latest))
            }
            if let data = self.pendingData, data.count < 48_000 { reply["snapshot"] = data }
            replyHandler(reply)
        }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
}

extension AppState {
    func makeWatchSnapshot() -> WatchSnapshot {
        guard isLoggedIn else {
            var empty = WatchSnapshot.empty
            empty.generatedAt = Date()
            return empty
        }
        let calendar = WatchSnapshot.campusCalendar
        let base = calendar.startOfDay(for: reminderMonday)
        var lessons: [WatchSnapshot.Lesson] = []
        let weeks = Set(reminderOccurrences.flatMap(\.weeks)).sorted()
        for week in weeks where week > 0 && week <= 60 {
            for block in reminderOccurrences.filter({ $0.weeks.contains(week) }).courseBlocks() where !block.isPlaceholder && !block.isRemote {
                guard (1...7).contains(block.day),
                      let day = calendar.date(byAdding: .day, value: (week - 1) * 7 + block.day - 1, to: base),
                      let start = calendar.date(byAdding: .minute, value: PeriodSchedule.startMinutes(of: block), to: day),
                      let end = calendar.date(byAdding: .minute, value: PeriodSchedule.endMinutes(of: block), to: day), end > start else { continue }
                lessons.append(.init(id: "\(week)-\(block.id)", name: block.name, room: block.shortRoom,
                                     fullRoom: block.room, teacher: block.teacher, periods: block.periodText,
                                     start: start, end: end, colorIndex: CoursePalette.index(forCourseKey: block.courseKey)))
            }
        }
        let datedExams: [WatchSnapshot.Exam] = currentExams.compactMap { exam in
            guard let day = WatchSnapshot.parseDay(exam.dateKey) else { return nil }
            let normalized = exam.timeWithoutDate.replacingOccurrences(of: "：", with: ":")
            let matches = normalized.regexGroups(#"(\d{1,2}):(\d{2})"#)
            let minutes = matches.compactMap { parts -> Int? in
                guard let h = Int(parts[0]), let m = Int(parts[1]), h < 24, m < 60 else { return nil }
                return h * 60 + m
            }
            let startOfDay = calendar.startOfDay(for: day)
            let start = calendar.date(byAdding: .minute, value: minutes.first ?? 0, to: startOfDay)!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let candidateEnd = minutes.count > 1 ? calendar.date(byAdding: .minute, value: minutes[1], to: startOfDay)! : nextDay
            return .init(id: exam.id, name: exam.course, start: start, end: candidateEnd > start ? candidateEnd : nextDay,
                         time: exam.timeWithoutDate, room: exam.room, seat: exam.seat, note: exam.note)
        }
        var holidays: [WatchSnapshot.Holiday] = []
        if let info = CalendarCache.load() {
            for (index, span) in info.semesters.enumerated() {
                if let start = WatchSnapshot.parseDay(span.start) {
                    holidays.append(.init(id: "start-\(span.start)", title: "\(span.label)开学", date: start))
                }
                if let end = WatchSnapshot.parseDay(span.end), let date = calendar.date(byAdding: .day, value: 1, to: end) {
                    holidays.append(.init(id: "break-\(span.end)", title: index == 0 ? "放寒假" : "放暑假", date: date))
                }
            }
        }
        return WatchSnapshot(generatedAt: Date(), accountID: studentID, loggedIn: true, semester: semesterName,
                             weekOneMonday: base, timetableUpdatedAt: fetchedAt, examsUpdatedAt: examsFetchedAt,
                             lessons: lessons.sorted { $0.start < $1.start }, exams: datedExams,
                             balance: electricityBalance, balanceUpdatedAt: electricityCheckedAt,
                             roomName: dorm?.roomName, holidays: holidays.sorted { $0.date < $1.date })
    }
}
