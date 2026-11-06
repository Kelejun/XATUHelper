import SwiftUI

/// Course colors shared by the phone timetable and Apple Watch.
enum CampusCourseColors {
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

    static func color(index: Int?) -> Color {
        guard let index, index >= 0 else { return colors[0] }
        return colors[index % colors.count]
    }
}
