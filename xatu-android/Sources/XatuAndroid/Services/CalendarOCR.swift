import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Vision)
import Vision
#endif

#if canImport(Vision)
extension CalendarService {
    /// 本地 OCR：识别指定区域（Vision 坐标系原点在左下角）
    static func ocr(_ data: Data, region: CGRect) -> String? {
        guard let cgImage = UIImage(data: data)?.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        request.regionOfInterest = region
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}

 #endif

/// 校历解析结果的本地缓存，同一张图不重复 OCR
enum CalendarCache {
    private static let key = "xatu.schoolCalendar"

    static func load() -> CalendarService.Info? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CalendarService.Info.self, from: data)
    }

    static func load(imageURL: String) -> CalendarService.Info? {
        guard let info = load(), info.imageURL == imageURL else { return nil }
        return info
    }

    static func save(_ info: CalendarService.Info) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - 校历原图缓存（离线时也能看）

    private static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("SchoolCalendar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileName(for url: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in url.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16) + ".jpg"
    }

    static func saveImage(_ data: Data, for url: String) {
        guard let dir = directory() else { return }
        try? data.write(to: dir.appendingPathComponent(fileName(for: url)), options: .atomic)
    }

    static func loadImage(for url: String) -> Data? {
        guard let dir = directory() else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(fileName(for: url)))
    }
}
