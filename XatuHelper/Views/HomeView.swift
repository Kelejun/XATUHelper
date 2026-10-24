import SwiftUI

struct HomeView: View {
    @State private var now = Date()

    /// 按时间段换问候语。5-11 早，11-14 吃饭没，14-18 下午好，18-23 晚上好，其余晚安。
    private var greeting: String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<11: return "早，"
        case 11..<14: return "吃饭没？"
        case 14..<18: return "下午好，"
        case 18..<23: return "晚上好，"
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
