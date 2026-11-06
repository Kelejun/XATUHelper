import Foundation

/// The same time boundaries and punctuation on iPhone and Apple Watch.
enum CampusGreeting {
    static func text(at date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        switch minutes {
        case 300..<690: return "早，"
        case 690..<810: return "吃饭没？"
        case 810..<1080: return "下午好，"
        case 1080..<1350: return "晚上好，"
        default: return "晚安。"
        }
    }
}
