import SwiftUI

struct HomeView: View {
    @State private var now = Date()

    /// 按时间段换问候语。分界点：5:00 早起、11:30 午饭、13:30 下午、18:00 晚上、22:30 晚安。
    private var greeting: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        switch minutes {
        case 300..<690: return "早，"
        case 690..<810: return "吃饭没？"
        case 810..<1080: return "下午好，"
        case 1080..<1350: return "晚上好，"
        default: return "晚安。"
        }
    }

    var body: some View {
        NavigationStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .navigationTitle(greeting)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

#Preview {
    HomeView()
}
