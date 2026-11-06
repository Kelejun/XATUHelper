import SwiftUI

struct PrivacyPolicyLink: View {
    var body: some View {
        NavigationLink("隐私政策") {
            PrivacyPolicyView()
        }
    }
}

private struct PrivacyPolicyView: View {
    private static let paragraphs: [String] = {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md"),
              let policy = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return policy.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if Self.paragraphs.isEmpty {
                    Text("暂时无法读取隐私政策。")
                }
                ForEach(Self.paragraphs, id: \.self) { paragraph in
                    if paragraph.hasPrefix("#") {
                        Text(paragraph.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    } else {
                        Text(.init(paragraph))
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}
