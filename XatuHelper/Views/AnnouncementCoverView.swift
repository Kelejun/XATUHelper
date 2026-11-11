import SwiftUI
import ImageIO

struct AnnouncementCoverView: View {
    @EnvironmentObject private var center: AnnouncementCenter
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                    .accessibilityLabel("公告头图")
            } else if center.isCachingImages {
                ProgressView().frame(maxWidth: .infinity).frame(height: 180)
            }
        }
        .task(id: "\(url.absoluteString)#\(center.imageRevision)") {
            image = nil
            guard let file = await center.cachedImageURL(for: url),
                  let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary), !Task.isCancelled else { return }
            image = UIImage(cgImage: thumbnail)
        }
    }
}
