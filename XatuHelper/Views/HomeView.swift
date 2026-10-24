import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
                .navigationTitle("首页")
        }
    }
}

#Preview {
    HomeView()
}
