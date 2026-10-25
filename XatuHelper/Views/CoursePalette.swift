import SwiftUI

/// 课程配色：同一门课在周视图、首页、小组件里保持同一个颜色。
enum CoursePalette {
    static let colors: [Color] = [
        Color(red: 0.20, green: 0.47, blue: 0.90),
        Color(red: 0.85, green: 0.42, blue: 0.20),
        Color(red: 0.18, green: 0.60, blue: 0.45),
        Color(red: 0.58, green: 0.35, blue: 0.75),
        Color(red: 0.82, green: 0.55, blue: 0.12),
        Color(red: 0.12, green: 0.53, blue: 0.68),
        Color(red: 0.74, green: 0.30, blue: 0.45),
        Color(red: 0.35, green: 0.50, blue: 0.25)
    ]

    static func color(for block: CourseBlock) -> Color {
        if block.isRemote {
            return Color(red: 0.52, green: 0.44, blue: 0.72)
        }
        if block.isPlaceholder {
            return Color(red: 0.50, green: 0.50, blue: 0.54)
        }
        return color(forCourseKey: block.courseKey)
    }

    static func color(forCourseKey key: String) -> Color {
        var hash = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return colors[abs(hash % colors.count)]
    }
}
