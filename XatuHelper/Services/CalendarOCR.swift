import Foundation
import UIKit
import Vision

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
}
