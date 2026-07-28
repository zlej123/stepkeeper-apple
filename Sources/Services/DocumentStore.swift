import Foundation
import os

struct DocumentMeta: Codable, Sendable, Equatable, Identifiable {
    var id: String        // 폴더명: <videoId>-<yyyyMMdd-HHmmss>[-n]
    var title: String
    var videoId: String
    var profile: String
    var language: String
    var createdAt: Date
    /// 이 문서로 만든 Notion 페이지 (재시도 안전성 — 외부 리뷰 #9).
    /// 페이지 **생성 직후** 기록한다: 중간 실패 후 재시도하면 이 페이지를 보관 처리하고
    /// 새로 만들므로, 실패가 몇 번이든 살아 있는 페이지는 항상 하나다.
    var notionPageID: String?
    var notionPageURL: String?
}

struct SavedDocument: Sendable {
    var meta: DocumentMeta
    var analysis: Analysis
    var picks: [String: String]
    var markdown: String
    var folder: URL
}

/// 스펙 4.6: Documents/stepkeeper/<id>/ 아래 document.md + vg-N.jpg + meta.json + analysis.json + picks.json
final class DocumentStore: Sendable {
    static let log = Logger(subsystem: "stepkeeper", category: "DocumentStore")
    private let root: URL

    init(root: URL) { self.root = root }

    /// clipnote 시절 문서는 여기로 이전되지 않는다 — 샌드박스 컨테이너가 번들 ID 기준이라
    /// (com.clipnote.app → com.stepkeeper.app) 새 앱에서는 옛 컨테이너 자체가 보이지 않는다.
    /// 옛 앱이 설치돼 있다면 그 앱에서 공유·폴더 저장으로 문서를 꺼내야 한다.
    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("stepkeeper", isDirectory: true)
    }

    func folderURL(id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

    func save(videoId: String, title: String, analysis: Analysis, rawAnalysis: Data,
              picks: [String: String], images: [String: Data], markdown: String,
              now: Date = Date()) throws -> DocumentMeta {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(videoId)-\(formatter.string(from: now))"
        var id = base
        var counter = 2
        while FileManager.default.fileExists(atPath: folderURL(id: id).path) {
            id = "\(base)-\(counter)"
            counter += 1
        }
        let folder = folderURL(id: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let meta = DocumentMeta(id: id, title: title, videoId: videoId,
                                profile: analysis.profile ?? "generic",
                                language: analysis.outputLanguage ?? "ko", createdAt: now)
        let encoder = Self.makeEncoder()

        try Data(markdown.utf8).write(to: folder.appendingPathComponent("document.md"))
        try encoder.encode(meta).write(to: folder.appendingPathComponent("meta.json"))
        try rawAnalysis.write(to: folder.appendingPathComponent("analysis.json"))
        try encoder.encode(picks).write(to: folder.appendingPathComponent("picks.json"))
        for (name, data) in images {
            try data.write(to: folder.appendingPathComponent(name))
        }
        return meta
    }

    func list() throws -> [DocumentMeta] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let decoder = Self.makeDecoder()
        let folders = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return folders.compactMap { folder -> DocumentMeta? in
            // fail-soft: 깨진 폴더 하나가 목록 전체를 막지 않는다. 다만 무음으로 지우지는 않는다 —
            // "저장했는데 목록에 없다"는 증상이 로그 없이는 추적 불가였다.
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")) else {
                Self.log.notice("meta.json 없음/읽기 실패 — 건너뜀: \(folder.lastPathComponent, privacy: .public)")
                return nil
            }
            do {
                return try decoder.decode(DocumentMeta.self, from: data)
            } catch {
                Self.log.error("meta.json 디코드 실패 — 건너뜀: \(folder.lastPathComponent, privacy: .public) (\(String(describing: error), privacy: .public))")
                return nil
            }
        }
        .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    func load(id: String) throws -> SavedDocument {
        let folder = folderURL(id: id)
        let decoder = Self.makeDecoder()
        let meta = try decoder.decode(
            DocumentMeta.self, from: Data(contentsOf: folder.appendingPathComponent("meta.json")))
        let analysis = try JSONDecoder().decode(
            Analysis.self, from: Data(contentsOf: folder.appendingPathComponent("analysis.json")))
        let picks = try JSONDecoder().decode(
            [String: String].self, from: Data(contentsOf: folder.appendingPathComponent("picks.json")))
        let markdown = try String(
            contentsOf: folder.appendingPathComponent("document.md"), encoding: .utf8)
        return SavedDocument(meta: meta, analysis: analysis, picks: picks,
                             markdown: markdown, folder: folder)
    }

    /// meta.json만 갱신 (Notion 페이지 기록 등). 문서 본문·이미지는 건드리지 않는다.
    func updateMeta(_ meta: DocumentMeta) throws {
        try Self.makeEncoder().encode(meta)
            .write(to: folderURL(id: meta.id).appendingPathComponent("meta.json"))
    }

    func delete(id: String) throws {
        try FileManager.default.removeItem(at: folderURL(id: id))
    }

    // 같은 초 저장이 정렬에서 구분되도록 소수점 초까지 보존한다 (리뷰 반영:
    // .iso8601은 초 단위 절삭이라 동시각 항목의 목록 순서가 videoId 알파벳순으로 역전됐음)
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            guard let date = plain.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "잘못된 날짜 형식: \(raw)")
            }
            return date
        }
        return decoder
    }
}
