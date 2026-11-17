import SwiftUI

struct HomeView: View {
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(CampusGreeting.text(at: now))
                        .font(.largeTitle.bold())
                }
                .padding(20)
                .padding(.top, 100)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
            .campusSidebarToolbar()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}
