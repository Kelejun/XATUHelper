import Foundation

/// 示例数据只属于独立的 AppState，不写入真实账号的缓存或小组件。
extension AppState {
    func configureDemoAccount() {
        guard isDemoMode else { return }
        let now = Date()
        let calendar = Calendar.current
        let monday = Self.mondayOfWeek(containing: now) ?? now
        weekOneMonday = calendar.date(byAdding: .day, value: -7 * 7, to: monday) ?? monday
        studentID = "示例账号"
        currentSemesterID = "demo-semester"
        selectedSemesterID = currentSemesterID
        semesters = [Semester(id: currentSemesterID, name: "示例学期")]
        let weeks = Array(1...20)
        let samples: [(String, String, String, Int, [Int])] = [
            ("高等数学", "张老师", "教1-201", 1, [1, 2]),
            ("大学英语", "李老师", "教2-305", 2, [3, 4]),
            ("计算机网络", "王老师", "教3-109", 3, [1, 2]),
            ("数据结构", "陈老师", "教2-210", 3, [5, 6]),
            ("大学物理", "刘老师", "教1-402", 4, [3, 4]),
            ("体育", "赵老师", "体育场", 5, [7, 8])
        ]
        occurrences = samples.enumerated().flatMap { index, item in
            item.4.map { period in
                CourseOccurrence(id: "demo-\(index)-\(period)", courseKey: "demo-\(index)",
                                 name: item.0, teacher: item.1, room: item.2,
                                 day: item.3, period: period, weeks: weeks,
                                 isRemote: false, isPlaceholder: false)
            }
        }
        fetchedAt = now
        examsFetchedAt = now
        gradesFetchedAt = now
        planFetchedAt = now
        let examDate = calendar.date(byAdding: .day, value: 12, to: now) ?? now
        exams = [ExamRecord(id: "demo-exam", course: "计算机网络", code: "DEMO101",
                            name: "期末考试", time: "\(ElectricityRecord.dayString(for: examDate)) 09:00-11:00",
                            room: "教3-109", seat: "16", note: "")]
        grades = [
            GradeRecord(id: "demo-grade-1", course: "高等数学", code: "DEMO001", credit: "5", score: "92", gpa: "4.2", components: []),
            GradeRecord(id: "demo-grade-2", course: "大学英语", code: "DEMO002", credit: "3", score: "88", gpa: "3.8", components: [])
        ]
        plan = PlanSnapshot(studentName: "示例同学", major: "计算机科学与技术", gpa: "3.8",
                            totalRequired: 160, totalEarned: 96,
                            sections: [PlanSection(id: "demo-plan", title: "通识教育", required: 60, earned: 48, shortfall: 12)])
        planCatalog = PlanCatalog(updatedAt: now, courses: [])
        dorm = DormSelection(areaID: "demo-area", areaName: "未央校区", buildID: "demo-build",
                             buildName: "9号公寓", roomID: "demo-room", roomName: "320宿舍")
        electricityBalance = "52.77"
        electricityCheckedAt = now
        electricityHistory = (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            return ElectricityRecord(day: ElectricityRecord.dayString(for: day), balance: 52.77 + Double(offset) * 2.3)
        }
        isLoggedIn = true
    }
}
