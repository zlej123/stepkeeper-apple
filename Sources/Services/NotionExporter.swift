import Foundation

/// SavedDocument → Notion 페이지 (스펙 3.3).
/// 절차: **페이지 생성 → 픽 이미지 업로드 → 블록 100개씩 추가.**
///
/// 순서가 중요하다(코어 export_notion과 동일). 업로드를 먼저 하면, 가장 흔한 실패인
/// 부모 페이지 미연결·잘못된 ID·토큰 만료가 마지막 페이지 생성 단계에서 터지면서 올라간
/// 이미지가 전부 어디에도 붙지 않은 채 남는다 — Notion API에는 업로드를 지우는 엔드포인트가
/// 없어 만료 전까지 되돌릴 수 없다. 페이지를 먼저 만들면 그 실패는 업로드 0건으로 끝나고,
/// 이후 실패는 사용자 눈에 보이는 페이지로 남아 직접 지우거나 재시도할 수 있다.
final class NotionExporter: Sendable {
    private let api: NotionAPI
    private let parentPageID: String

    init(api: NotionAPI, parentPageID: String) {
        self.api = api
        self.parentPageID = parentPageID
    }

    /// - Parameters:
    ///   - replacingPageID: 이전 시도가 남긴 페이지 — 새 페이지 생성 전에 보관 처리한다.
    ///     중간 실패 후 재시도해도 살아 있는 페이지는 항상 하나다 (외부 리뷰 #9).
    ///   - onPageCreated: 생성 **직후** 호출 — 호출자는 여기서 페이지 id를 영속화해야
    ///     이후 단계가 실패해도 다음 재시도가 이 페이지를 교체할 수 있다.
    func export(document: SavedDocument, replacingPageID: String? = nil,
                onPageCreated: (@Sendable (String, String?) async -> Void)? = nil) async throws -> URL {
        if let replacingPageID {
            try await api.archivePage(pageID: replacingPageID)
        }
        let page = try await api.createPage(
            parentPageID: parentPageID, title: document.analysis.title, children: [])
        await onPageCreated?(page.id, page.url)

        var uploadIds: [String: String] = [:]
        for guide in document.analysis.visualGuides {
            guard (document.picks[guide.id] ?? "none") != "none" else { continue }
            let file = document.folder.appendingPathComponent("\(guide.id).jpg")
            guard let data = try? Data(contentsOf: file) else { continue }   // 픽은 있는데 파일 없음 → 링크 폴백
            let uploadId = try await api.createFileUpload()
            try await api.sendFileUpload(id: uploadId, data: data, filename: "\(guide.id).jpg")
            uploadIds[guide.id] = uploadId
        }

        let blocks = NotionBlockBuilder.blocks(
            analysis: document.analysis, videoId: document.meta.videoId,
            imageUploadIds: uploadIds)
        var start = 0
        while start < blocks.count {
            try await api.appendChildren(
                pageID: page.id, blocks: Array(blocks[start..<min(start + 100, blocks.count)]))
            start += 100
        }

        if let urlString = page.url, let url = URL(string: urlString) { return url }
        return URL(string: "https://www.notion.so/"
                   + page.id.replacingOccurrences(of: "-", with: ""))!
    }
}

/// 뷰 인스턴스가 재생성돼도 유지되는 진행 중 내보내기 추적 — 재진입 중복 방지 (최종 리뷰 반영).
/// 백그라운드 완주는 보존한다(취소하지 않음): 뒤로가기 후에도 페이지는 만들어지고, 재탭만 막는다.
@MainActor
enum NotionExportTracker {
    private(set) static var inFlight: Set<String> = []

    /// 시작 시도 — 이미 진행 중이면 false
    static func begin(_ documentID: String) -> Bool {
        guard !inFlight.contains(documentID) else { return false }
        inFlight.insert(documentID)
        return true
    }

    static func end(_ documentID: String) {
        inFlight.remove(documentID)
    }
}
