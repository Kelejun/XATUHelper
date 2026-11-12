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
    private static let correctionsKey = "xatu.schoolCalendar.corrections"
    static let didChange = Notification.Name("schoolCalendarDidChange")

    struct Correction: Codable {
        var semesters: [CalendarService.SemesterSpan]
        var notes: [String]

        var validationError: String? {
            guard !semesters.isEmpty else { return "请至少添加一个学期。" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            let ordered = semesters.sorted { $0.start < $1.start }
            for (index, semester) in ordered.enumerated() {
                guard !semester.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return "请填写学期名称。"
                }
                guard let start = formatter.date(from: semester.start),
                      let end = formatter.date(from: semester.end),
                      formatter.string(from: start) == semester.start,
                      formatter.string(from: end) == semester.end else { return "请填写有效日期。" }
                guard start <= end else { return "结课日期不能早于开学日期。" }
                if index > 0, ordered[index - 1].end >= semester.start {
                    return "学期日期不能重叠，请检查开学和结课日期。"
                }
            }
            return nil
        }
    }

    private static var corrections: [String: Correction] {
        guard let data = UserDefaults.standard.data(forKey: correctionsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Correction].self, from: data)) ?? [:]
    }

    static func original() -> CalendarService.Info? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CalendarService.Info.self, from: data)
    }

    static func applyingCorrection(to original: CalendarService.Info) -> CalendarService.Info {
        guard let correction = corrections[original.imageURL] else { return original }
        var result = original
        result.semesters = correction.semesters
        result.notes = correction.notes
        return result
    }

    static func saveCorrection(_ correction: Correction, for imageURL: String) {
        guard correction.validationError == nil else { return }
        var stored = corrections
        if let original = original(), original.imageURL == imageURL,
           original.semesters == correction.semesters, original.notes == correction.notes {
            stored.removeValue(forKey: imageURL)
        } else {
            stored[imageURL] = correction
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: correctionsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func load() -> CalendarService.Info? {
        original().map { applyingCorrection(to: $0) }
    }

    static func load(imageURL: String) -> CalendarService.Info? {
        guard let info = load(), info.imageURL == imageURL else { return nil }
        return info
    }

    static func save(_ info: CalendarService.Info) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
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
