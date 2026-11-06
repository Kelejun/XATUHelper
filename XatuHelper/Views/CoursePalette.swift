import SwiftUI

/// 课程配色：同一门课在周视图、首页、小组件里保持同一个颜色。
///
/// 先用「本学期课程码排序后的序号」取色，保证同一学期的课不会撞色；
/// 没注册过（比如冷启动只读到某门课）再退回哈希取色。
enum CoursePalette {
    static let colors = CampusCourseColors.colors

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
