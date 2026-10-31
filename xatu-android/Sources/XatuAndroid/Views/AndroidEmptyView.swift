#if os(Android)
import SwiftUI

/// A portable empty state for the iOS 17 ContentUnavailableView API.
struct ContentUnavailableView: View {
    let title: String
    let systemImage: String
    let description: Text?
    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let description { description.font(.subheadline).foregroundStyle(.secondary) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
#endif
