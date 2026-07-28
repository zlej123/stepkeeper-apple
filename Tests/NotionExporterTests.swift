import Testing
import Foundation
@testable import stepkeeper

@Suite(.serialized)
struct NotionExporterTests {
    /// 스텁 라우팅: 경로별 응답 + 요청 기록 (페이로드 검증용)
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [(path: String, body: Data?)] = []
        func record(_ path: String, _ body: Data?) {
            lock.lock(); defer { lock.unlock() }
            _requests.append((path, body))
        }
        var requests: [(path: String, body: Data?)] {
            lock.lock(); defer { lock.unlock() }
            return _requests
        }
    }

    fileprivate func makeDocument(guideCount: Int, pickedImages: [String: Data]) throws
        -> (SavedDocument, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notion-exp-\(UUID().uuidString)")
        let store = DocumentStore(root: root)
        let steps = (1...max(1, guideCount)).map {
            Step(id: $0, summary: "단계\($0)", detail: "설명\($0)", tStart: $0 * 10, tEnd: $0 * 10 + 5)
        }
        let guides = (1...guideCount).map {
            VisualGuide(id: "vg-\($0)", stepId: $0, sourcePhrase: "p", phrase: "p\($0)",
                        type: "state", whatToShow: "w", bestVisualTimestamp: $0 * 10 + 2,
                        guideText: "g\($0)", importance: 0.5)
        }
        let analysis = Analysis(title: "노션 테스트", summary: "요약", category: "생활",
                                servings: nil, materials: [Material(name: "재료", amount: "1")],
                                steps: steps, visualGuides: guides,
                                duration: 600, profile: "generic", outputLanguage: "ko")
        // 브리프 원문은 raw를 {"title": ...} 단독 객체로 만들었으나, DocumentStore.load()가
        // analysis.json(=rawAnalysis 그대로)을 Analysis로 재디코딩하므로(summary 등 필수 키 없어
        // DecodingError.keyNotFound 발생 — 런타임 강제) analysis 전체를 인코딩하도록 적응.
        let raw = try JSONEncoder().encode(analysis)
        let picks = Dictionary(uniqueKeysWithValues: guides.map {
            ($0.id, pickedImages[$0.id + ".jpg"] != nil ? "center" : "none")
        })
        let meta = try store.save(videoId: "dQw4w9WgXcQ", title: analysis.title,
                                  analysis: analysis, rawAnalysis: raw, picks: picks,
                                  images: pickedImages, markdown: "md\n")
        return (try store.load(id: meta.id), root)
    }

    private func stub(recorder: Recorder, uploadFails: Bool = false) {
        NotionExporterStub.shared.handler = { request in
            let path = request.url!.path
            recorder.record(path, request.bodyData)
            if path == "/v1/file_uploads" {
                return (200, Data(#"{"id": "fu-1"}"#.utf8))
            }
            if path.hasSuffix("/send") {
                return uploadFails ? (500, Data(#"{"message": "boom"}"#.utf8))
                                   : (200, Data("{}".utf8))
            }
            if path == "/v1/pages" {
                return (200, Data(#"{"id": "page-1", "url": "https://www.notion.so/page-1"}"#.utf8))
            }
            return (200, Data("{}".utf8))   // /v1/blocks/.../children
        }
    }
    private func makeExporter() -> NotionExporter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotionExporterStub.self]
        return NotionExporter(
            api: NotionAPI(token: "test-token", session: URLSession(configuration: config)),
            parentPageID: String(repeating: "0", count: 32))
    }
    private func reset() {
        NotionExporterStub.shared.reset()
    }

    @Test func wiresPickedImageIntoImageBlock() async throws {
        defer { reset() }
        let recorder = Recorder()
        stub(recorder: recorder)
        let (document, root) = try makeDocument(
            guideCount: 1, pickedImages: ["vg-1.jpg": Data([0xFF, 0xD8, 0x01])])
        defer { try? FileManager.default.removeItem(at: root) }

        let url = try await makeExporter().export(document: document)

        #expect(url.absoluteString == "https://www.notion.so/page-1")
        // 블록은 페이지 생성 payload가 아니라 append 요청에 들어간다 (페이지 먼저 생성 순서)
        let appendBody = try #require(
            recorder.requests.first { $0.path.hasPrefix("/v1/blocks/") }?.body)
        let payload = try JSONSerialization.jsonObject(with: appendBody) as! [String: Any]
        let children = payload["children"] as! [[String: Any]]
        let imageBlocks = children.filter { $0["type"] as? String == "image" }
        #expect(imageBlocks.count == 1)
        let upload = try #require(
            (imageBlocks.first?["image"] as? [String: Any])?["file_upload"] as? [String: Any])
        #expect(upload["id"] as? String == "fu-1")
    }

    @Test func batchesBlocksOver100() async throws {
        defer { reset() }
        let recorder = Recorder()
        stub(recorder: recorder)
        // 가이드 60개(픽 없음) → 블록 = 요약1+링크1+준비물2+순서1+ (step+quote+ts링크)×60 = 185 → 100/85 분할
        let (document, root) = try makeDocument(guideCount: 60, pickedImages: [:])
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await makeExporter().export(document: document)

        // 페이지는 빈 상태로 먼저 만들고, 블록은 전부 append로 100개씩 나눠 붙인다
        let pageBody = try #require(recorder.requests.first { $0.path == "/v1/pages" }?.body)
        let pagePayload = try JSONSerialization.jsonObject(with: pageBody) as! [String: Any]
        #expect((pagePayload["children"] as? [Any])?.isEmpty ?? true)
        let appends = recorder.requests.filter { $0.path.hasPrefix("/v1/blocks/") }
        #expect(appends.count == 2)
        let counts = try appends.map { request -> Int in
            let payload = try JSONSerialization.jsonObject(with: request.body!) as! [String: Any]
            return (payload["children"] as! [Any]).count
        }
        #expect(counts == [100, 85])
    }

    @Test func uploadFailureLeavesAVisiblePageInsteadOfOrphans() async throws {
        defer { reset() }
        let recorder = Recorder()
        stub(recorder: recorder, uploadFails: true)
        let (document, root) = try makeDocument(
            guideCount: 1, pickedImages: ["vg-1.jpg": Data([0xFF, 0xD8, 0x01])])
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: NotionAPIError.api(500, "boom")) {
            _ = try await self.makeExporter().export(document: document)
        }
        // 업로드가 실패해도 페이지는 이미 있다 — 사용자가 보고 지우거나 다시 시도할 수 있다.
        // (예전 순서에서는 페이지 생성이 마지막이라, 그 단계 실패 시 올라간 이미지가
        //  어디에도 붙지 않은 채 남았다. Notion API에는 업로드 삭제가 없다.)
        #expect(recorder.requests.contains { $0.path == "/v1/pages" })
    }

    @Test func pageIsCreatedBeforeAnyUpload() async throws {
        defer { reset() }
        let recorder = Recorder()
        stub(recorder: recorder)
        let (document, root) = try makeDocument(
            guideCount: 1, pickedImages: ["vg-1.jpg": Data([0xFF, 0xD8, 0x01])])
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await makeExporter().export(document: document)

        let paths = recorder.requests.map(\.path)
        let page = try #require(paths.firstIndex(of: "/v1/pages"))
        let upload = try #require(paths.firstIndex(of: "/v1/file_uploads"))
        #expect(page < upload)   // 부모 페이지 문제는 업로드 0건으로 끝난다
    }
}

@Suite(.serialized)
struct NotionRetryTests {
    private func makeExporter() -> NotionExporter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotionExporterStub.self]
        return NotionExporter(
            api: NotionAPI(token: "t", session: URLSession(configuration: config)),
            parentPageID: String(repeating: "0", count: 32))
    }

    /// 재시도는 이전 부분 페이지를 보관 처리한 뒤 새로 만든다 — 살아 있는 페이지는 항상 하나 (리뷰 #9)
    @Test func retryArchivesThePreviousPageFirst() async throws {
        defer { NotionExporterStub.shared.reset() }
        let recorder = NotionExporterOrderRecorder()
        NotionExporterStub.shared.handler = { request in
            recorder.record("\(request.httpMethod ?? "?") \(request.url!.path)")
            return (200, Data(#"{"id": "page-new", "url": "https://notion.so/new"}"#.utf8))
        }
        let (document, root) = try NotionExporterTests().makeDocument(guideCount: 1, pickedImages: [:])
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await makeExporter().export(document: document, replacingPageID: "page-old")
        let calls = recorder.calls
        #expect(calls.first == "PATCH /v1/pages/page-old")          // 보관이 가장 먼저
        #expect(calls.contains("POST /v1/pages"))
        #expect(try #require(calls.firstIndex(of: "PATCH /v1/pages/page-old"))
                < #require(calls.firstIndex(of: "POST /v1/pages")))
    }

    /// 이전 페이지가 이미 사라졌어도(404) 재시도는 계속된다 — 목적은 "살아 있는 중복 제거"다
    @Test func archiving404IsTreatedAsSuccess() async throws {
        defer { NotionExporterStub.shared.reset() }
        NotionExporterStub.shared.handler = { request in
            if request.httpMethod == "PATCH" { return (404, Data(#"{"message":"gone"}"#.utf8)) }
            return (200, Data(#"{"id": "page-new", "url": "https://notion.so/new"}"#.utf8))
        }
        let (document, root) = try NotionExporterTests().makeDocument(guideCount: 1, pickedImages: [:])
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try await makeExporter().export(document: document, replacingPageID: "page-old")
        #expect(url.absoluteString == "https://notion.so/new")
    }

    /// 페이지 id는 생성 **직후** 콜백된다 — 이후 단계가 실패해도 다음 재시도가 이어받는다
    @Test func pageIDIsDeliveredBeforeLaterStepsCanFail() async throws {
        defer { NotionExporterStub.shared.reset() }
        let recorder = NotionExporterOrderRecorder()
        NotionExporterStub.shared.handler = { request in
            if request.url!.path.hasPrefix("/v1/blocks/") {
                recorder.record("append")
                return (500, Data(#"{"message":"boom"}"#.utf8))    // 생성 뒤 단계에서 실패
            }
            return (200, Data(#"{"id": "page-1", "url": "https://notion.so/p1"}"#.utf8))
        }
        let (document, root) = try NotionExporterTests().makeDocument(guideCount: 1, pickedImages: [:])
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: NotionAPIError.self) {
            _ = try await self.makeExporter().export(document: document) { pageID, _ in
                recorder.record("callback:\(pageID)")
            }
        }
        #expect(recorder.calls.first == "callback:page-1")          // 실패보다 먼저 전달됨
    }
}

/// 스텁 핸들러(로딩 스레드)와 테스트 본문이 교차 접근하는 호출 순서 기록기
final class NotionExporterOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] { lock.withLock { _calls } }
    func record(_ value: String) { lock.withLock { _calls.append(value) } }
}
