import Testing
import Foundation
@testable import clipnote

@Suite(.serialized)
struct NotionAPITests {
    private func makeAPI(retries: Int = NotionAPI.maxRetries,
                         sleeper: @escaping @Sendable (Double) async -> Void = { _ in }) -> NotionAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotionAPIStub.self]
        return NotionAPI(token: "test-token", session: URLSession(configuration: config),
                         retries: retries, sleeper: sleeper)
    }

    /// 재시도 대기 시간 기록기 — 실제 sleep 없이 백오프 값만 검증한다.
    private final class SleepLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _seconds: [Double] = []
        var seconds: [Double] { lock.withLock { _seconds } }
        func record(_ value: Double) { lock.withLock { _seconds.append(value) } }
    }
    private func reset() {
        NotionAPIStub.shared.reset()
    }

    @Test func fileUploadTwoStepSequence() async throws {
        defer { reset() }
        NotionAPIStub.shared.handler = { request in
            if request.url!.path == "/v1/file_uploads" {
                return (200, Data(#"{"id": "fu-123"}"#.utf8))
            }
            return (200, Data("{}".utf8))
        }
        let api = makeAPI()
        let id = try await api.createFileUpload()
        #expect(id == "fu-123")

        try await api.sendFileUpload(id: id, data: Data([0xFF, 0xD8]), filename: "vg-1.jpg")
        let request = try #require(NotionAPIStub.shared.capturedRequest)
        #expect(request.url?.path == "/v1/file_uploads/fu-123/send")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?
            .hasPrefix("multipart/form-data; boundary=") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == "2022-06-28")
        let body = try #require(NotionAPIStub.shared.capturedBody)
        let bodyText = String(decoding: body, as: UTF8.self)
        #expect(bodyText.contains(#"filename="vg-1.jpg""#))
    }

    @Test func createPagePayloadAndURL() async throws {
        defer { reset() }
        NotionAPIStub.shared.handler = { _ in
            (200, Data(#"{"id": "page-1", "url": "https://www.notion.so/page-1"}"#.utf8))
        }
        let api = makeAPI()
        let blocks: [NotionBlock] = [["type": "paragraph",
                                      "paragraph": ["rich_text": NotionBlockBuilder.rich("x")]]]
        let page = try await api.createPage(parentPageID: "p" + String(repeating: "0", count: 31),
                                            title: "제목", children: blocks)
        #expect(page.id == "page-1")
        #expect(page.url == "https://www.notion.so/page-1")
        let request = try #require(NotionAPIStub.shared.capturedRequest)
        #expect(request.url?.path == "/v1/pages")
        let payload = try JSONSerialization.jsonObject(
            with: try #require(NotionAPIStub.shared.capturedBody)) as! [String: Any]
        let parent = payload["parent"] as! [String: Any]
        #expect(parent["page_id"] as? String == "p" + String(repeating: "0", count: 31))
        #expect((payload["children"] as! [Any]).count == 1)
        let title = ((payload["properties"] as! [String: Any])["title"] as! [String: Any])["title"] as! [[String: Any]]
        #expect(((title[0]["text"] as! [String: Any])["content"] as? String) == "제목")
    }

    @Test func mapsErrorStatuses() async throws {
        defer { reset() }
        let api = makeAPI()
        NotionAPIStub.shared.handler = { _ in (401, Data(#"{"message": "unauthorized"}"#.utf8)) }
        await #expect(throws: NotionAPIError.invalidToken) { _ = try await api.createFileUpload() }
        NotionAPIStub.shared.handler = { _ in (404, Data(#"{"message": "not found"}"#.utf8)) }
        await #expect(throws: NotionAPIError.parentNotFound) { _ = try await api.createFileUpload() }
        NotionAPIStub.shared.handler = { _ in (400, Data(#"{"message": "bad block"}"#.utf8)) }
        await #expect(throws: NotionAPIError.api(400, "bad block")) { _ = try await api.createFileUpload() }
    }

    @Test func retriesAfterRateLimitThenSucceeds() async throws {
        defer { reset() }
        let attempts = Counter()
        NotionAPIStub.shared.responseHeaders = ["Retry-After": "2"]
        NotionAPIStub.shared.handler = { _ in
            attempts.increment() == 1
                ? (429, Data(#"{"message": "rate"}"#.utf8))
                : (200, Data(#"{"id": "fu-9"}"#.utf8))
        }
        let log = SleepLog()
        let api = makeAPI(sleeper: { log.record($0) })
        let id = try await api.createFileUpload()
        #expect(id == "fu-9")
        #expect(attempts.value == 2)
        #expect(log.seconds == [2])          // Retry-After 헤더값만큼 대기
    }

    @Test func givesUpAfterRetryBudget() async throws {
        defer { reset() }
        let attempts = Counter()
        NotionAPIStub.shared.handler = { _ in
            _ = attempts.increment()
            return (429, Data(#"{"message": "rate"}"#.utf8))
        }
        let log = SleepLog()
        let api = makeAPI(retries: 2, sleeper: { log.record($0) })
        await #expect(throws: NotionAPIError.rateLimited(after: NotionAPI.defaultRetryDelay)) {
            _ = try await api.createFileUpload()
        }
        #expect(attempts.value == 3)         // 최초 1 + 재시도 2
        #expect(log.seconds == [1, 1])       // Retry-After 없으면 기본 1초
    }

    @Test func clampsRetryAfterHeader() throws {
        let url = URL(string: "https://api.notion.com/v1/pages")!
        func response(_ header: String?) throws -> HTTPURLResponse {
            try #require(HTTPURLResponse(
                url: url, statusCode: 429, httpVersion: nil,
                headerFields: header.map { ["Retry-After": $0] } ?? [:]))
        }
        #expect(try NotionAPI.retryDelay(from: response("5")) == 5)
        #expect(try NotionAPI.retryDelay(from: response(" 7 ")) == 7)
        #expect(try NotionAPI.retryDelay(from: response("9999")) == NotionAPI.maxRetryDelay)
        #expect(try NotionAPI.retryDelay(from: response("-3")) == 0)
        #expect(try NotionAPI.retryDelay(from: response("Wed, 21 Oct 2026 07:28:00 GMT"))
                == NotionAPI.defaultRetryDelay)   // HTTP-date 형식은 미지원 → 기본값
        #expect(try NotionAPI.retryDelay(from: response(nil)) == NotionAPI.defaultRetryDelay)
    }
}

/// 스텁 핸들러(비동기 로딩 스레드)에서 호출 횟수를 세는 카운터.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    /// 증가 후의 값을 돌려준다 (첫 호출 = 1).
    @discardableResult func increment() -> Int {
        lock.withLock { count += 1; return count }
    }
    var value: Int { lock.withLock { count } }
}
