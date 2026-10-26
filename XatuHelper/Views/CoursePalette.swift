import SwiftUI

/// 课程配色：同一门课在周视图、首页、小组件里保持同一个颜色。
///
/// 先用「本学期课程码排序后的序号」取色，保证同一学期的课不会撞色；
/// 没注册过（比如冷启动只读到某门课）再退回哈希取色。
enum CoursePalette {
    static let colors: [Color] = [
        Color(red: 0.20, green: 0.47, blue: 0.90),
        Color(red: 0.85, green: 0.42, blue: 0.20),
        Color(red: 0.18, green: 0.60, blue: 0.45),
        Color(red: 0.58, green: 0.35, blue: 0.75),
        Color(red: 0.82, green: 0.55, blue: 0.12),
        Color(red: 0.12, green: 0.53, blue: 0.68),
        Color(red: 0.74, green: 0.30, blue: 0.45),
        Color(red: 0.35, green: 0.50, blue: 0.25),
        Color(red: 0.45, green: 0.38, blue: 0.80),
        Color(red: 0.72, green: 0.52, blue: 0.30),
        Color(red: 0.16, green: 0.58, blue: 0.58),
        Color(red: 0.62, green: 0.42, blue: 0.62),
        Color(red: 0.30, green: 0.45, blue: 0.62),
        Color(red: 0.78, green: 0.38, blue: 0.32)
    ]

    private static var registeredKeys: [String] = []

    /// 每学期课程加载后调一次，把课程码按顺序登记下来。
    static func register(_ keys: [String]) {
        let unique = Array(Set(keys)).sorted()
        guard unique != registeredKeys else { return }
        registeredKeys = unique
    }

    static func color(for block: CourseBlock) -> Color {
        if block.isRemote {
            return Color(red: 0.52, green: 0.44, blue: 0.72)
        }
        if block.isPlaceholder {
            return Color(red: 0.50, green: 0.50, blue: 0.54)
        }
        return color(forCourseKey: block.courseKey)
    }

    /// 小组件拿不到这个类，把下标写进快照让它自己上色
    static func index(forCourseKey key: String) -> Int? {
        registeredKeys.firstIndex(of: key).map { $0 % colors.count }
    }

    static func color(forCourseKey key: String) -> Color {
        if let index = registeredKeys.firstIndex(of: key) {
            return colors[index % colors.count]
        }
        var hash = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return colors[abs(hash % colors.count)]
    }
}
