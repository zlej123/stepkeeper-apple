import Testing
import Foundation
@testable import stepkeeper

extension URLRequest {
    /// URLSession이 body를 스트림으로 넘길 때가 있어 둘 다 처리
    var bodyData: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buffer, maxLength: size)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

@Suite(.serialized)
struct StepkeeperAPITests {
    private func makeAPI() -> StepkeeperAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StepkeeperAPIStub.self]
        return StepkeeperAPI(baseURL: URL(string: "http://stub.local:8787")!,
                           session: URLSession(configuration: config))
    }
    private func reset() {
        StepkeeperAPIStub.shared.reset()
    }

    @Test func successDecodesAndPreservesRawAnalysis() async throws {
        defer { reset() }
        let fixture = try Bundle.fixtureData("analyze-response")
        StepkeeperAPIStub.shared.handler = { _ in (200, fixture) }
        let result = try await makeAPI().analyze(
            videoURL: "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
            profile: "generic", language: "ko", duration: 90, geminiKey: "test-key")
        #expect(result.videoId == "dQw4w9WgXcQ")
        #expect(result.analysis.steps.count == 2)
        let raw = try JSONSerialization.jsonObject(with: result.rawAnalysis) as! [String: Any]
        #expect(raw["_model"] as? String == "gemini-flash-lite-latest")  // 모델에 없는 키 보존

        // 요청 형태 검증 — 핸들러 클로저 안 #expect는 Swift Testing 컨텍스트에 전파되지 않아
        // 위반이 배너에서 위장되므로(리뷰 확인) 캡처 후 테스트 본문에서 단언한다.
        let request = try #require(StepkeeperAPIStub.shared.capturedRequest)
        #expect(request.url?.path == "/v1/analyze")
        #expect(request.value(forHTTPHeaderField: "X-Gemini-Key") == "test-key")
        let body = try JSONSerialization.jsonObject(
            with: try #require(StepkeeperAPIStub.shared.capturedBody)) as! [String: Any]
        #expect(body["duration"] as? Int == 90)          // 결정 #3: duration은 앱이 보낸다
        #expect(body["max_guides"] as? Int == 5)
        #expect(body["model"] == nil)                    // 서버 기본값 사용
    }

    @Test func maps401ToMissingKey() async throws {
        defer { reset() }
        StepkeeperAPIStub.shared.handler = { _ in
            (401, Data(#"{"detail": "X-Gemini-Key 헤더가 필요합니다."}"#.utf8))
        }
        await #expect(throws: StepkeeperAPIError.missingKey) {
            _ = try await self.makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
        }
    }

    @Test func maps422To429To502() async throws {
        defer { reset() }
        StepkeeperAPIStub.shared.handler = { _ in (422, Data(#"{"detail": "bad url"}"#.utf8)) }
        await #expect(throws: StepkeeperAPIError.badRequest("bad url")) {
            _ = try await self.makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
        }
        StepkeeperAPIStub.shared.handler = { _ in (429, Data(#"{"detail": "quota"}"#.utf8)) }
        await #expect(throws: StepkeeperAPIError.rateLimited) {
            _ = try await self.makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
        }
        // FastAPI는 detail이 객체일 수도 있음 (계약 위반 케이스)
        StepkeeperAPIStub.shared.handler = { _ in
            (502, Data(#"{"detail": {"message": "분석 결과 계약 위반", "errors": ["steps"]}}"#.utf8))
        }
        do {
            _ = try await makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
            Issue.record("should throw")
        } catch let error as StepkeeperAPIError {
            guard case .modelFailure(let detail) = error else {
                Issue.record("wrong case: \(error)"); return
            }
            #expect(detail.contains("계약 위반"))
        }
    }

    @Test func mapsTransportErrorToNetwork() async throws {
        defer { reset() }
        StepkeeperAPIStub.shared.networkError = URLError(.cannotConnectToHost)
        do {
            _ = try await makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
            Issue.record("should throw")
        } catch let error as StepkeeperAPIError {
            guard case .network = error else { Issue.record("wrong case: \(error)"); return }
        }
    }

    @Test func submitReportPostsPayloadWithoutKey() async throws {
        defer { reset() }
        StepkeeperAPIStub.shared.handler = { _ in (200, Data(#"{"status": "ok"}"#.utf8)) }
        let raw = try JSONSerialization.data(withJSONObject: ["title": "t", "_model": "m"])
        let report = IssueReport(
            url: "https://m.youtube.com/watch?v=GziiD4XqCpc", videoId: "GziiD4XqCpc",
            reason: .candidates, note: "메모", profile: "recipe", language: "ko",
            rawAnalysis: raw, picks: ["vg-1": "none"], client: "apple/test")
        try await makeAPI().submitReport(report)

        let request = try #require(StepkeeperAPIStub.shared.capturedRequest)
        #expect(request.url?.path == "/v1/reports")
        #expect(request.value(forHTTPHeaderField: "X-Gemini-Key") == nil)   // 키 불필요 경로
        let body = try JSONSerialization.jsonObject(
            with: try #require(StepkeeperAPIStub.shared.capturedBody)) as! [String: Any]
        #expect(body["reason"] as? String == "candidates")
        #expect((body["analysis"] as? [String: Any])?["_model"] as? String == "m")   // 원본 병합
        #expect((body["picks"] as? [String: String]) == ["vg-1": "none"])
    }

    @Test func submitReportMapsServerFailure() async throws {
        defer { reset() }
        StepkeeperAPIStub.shared.handler = { _ in (500, Data(#"{"detail": "disk"}"#.utf8)) }
        let report = IssueReport(
            url: "u", videoId: "v", reason: .other, note: "", profile: "generic",
            language: "ko", rawAnalysis: Data("{}".utf8), picks: [:], client: "apple/test")
        do {
            try await makeAPI().submitReport(report)
            Issue.record("should throw")
        } catch let error as StepkeeperAPIError {
            guard case .server(500, _) = error else { Issue.record("wrong: \(error)"); return }
        }
    }
}
