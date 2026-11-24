import SwiftUI

private func clockText(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

struct NotificationSample: View {
    var time: String
    var timing: String
    var title: String
    var detail: String
    @Environment(\.colorScheme) private var scheme

    static func course(lead: Int) -> Self {
        Self(time: clockText(500 - lead), timing: "课前 \(lead) 分钟",
             title: "下一节课：高等数学", detail: "教室 教1-201")
    }

    static func exam(time: Int, timing: String, prefix: String) -> Self {
        Self(time: clockText(time), timing: timing, title: prefix + "：计算机网络",
             detail: "09:00–11:00 · 考场 教3-109 · 座位 16")
    }

    private var accentFill: Color {
        scheme == .dark ? Color(red: 0.14, green: 0.20, blue: 0.31)
                        : Color(red: 0.89, green: 0.94, blue: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(time).font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text(timing).font(.caption.weight(.medium))
                Spacer()
                Text("通知示例").font(.caption.weight(.medium))
            }
            .foregroundStyle(scheme == .dark ? Color(red: 0.69, green: 0.82, blue: 1) : Color(red: 0.16, green: 0.33, blue: 0.55))
            HStack(spacing: 11) {
                Image("XATuneMark").resizable().scaledToFit().padding(5)
                    .foregroundStyle(.white).frame(width: 36, height: 36).background(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12).background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 13))
        }
        .padding(14)
        .background(accentFill,
                    in: RoundedRectangle(cornerRadius: 18))
    }
}

struct CourseActivityPreview: View {
    let during: Bool
    @Environment(\.colorScheme) private var scheme
    private var remaining: String { during ? "18:00" : "05:00" }
    private var progress: Double { during ? 0.60 : 0.50 }
    private var symbol: String { during ? "book.fill" : "figure.walk" }
    private var blue: Color { scheme == .dark ? Color(red: 0.69, green: 0.82, blue: 1) : Color(red: 0.16, green: 0.33, blue: 0.55) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(during ? "上课中" : "课前", systemImage: symbol)
                Spacer()
                Text(during ? "距下课" : "距上课")
                Text(remaining).monospacedDigit().font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(blue).font(.caption)
            HStack {
                Text("高等数学").font(.headline)
                Spacer()
                Text("教1-201").font(.caption).foregroundStyle(blue)
            }
            ProgressView(value: progress).tint(blue).accessibilityHidden(true)
        }
        .padding(12).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("锁定屏幕，高等数学，教1-201，" + (during ? "距下课18分钟" : "距上课5分钟"))
    }
}
