import Testing
import Foundation
@testable import stepkeeper

@Suite(.serialized)
struct GeminiAPITests {
    private func makeAPI() -> GeminiAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GeminiAPIStub.self]
        return GeminiAPI(session: URLSession(configuration: config))
    }
    private func reset() { GeminiAPIStub.shared.reset() }

    /// 번들 실물 자산으로 프롬프트 치환 검증 — 플레이스홀더가 남아 있으면 실패
    @Test func buildPromptResolvesAllPlaceholders() throws {
        let prompt = try makeAPI().buildPrompt(
            profile: "generic", duration: 754, language: "ko", maxGuides: 5)
        #expect(!prompt.contains("{{RULES}}"))
        #expect(!prompt.contains("{DURATION}"))
        #expect(!prompt.contains("{OUTPUT_LANGUAGE}"))
        #expect(!prompt.contains("{MAX_VISUAL_GUIDES}"))
        #expect(prompt.contains("12:34"))
    }

    @Test func loadSchemaStripsMetaKeys() throws {
        let schema = try makeAPI().loadSchema(profile: "recipe")
        #expect(schema["$schema"] == nil && schema["$comment"] == nil && schema["title"] == nil)
        #expect(schema["required"] != nil)   // 계약 본체는 유지
    }

    @Test func analyzeSendsStructuredRequestAndNormalizes() async throws {
        defer { reset() }
        let analysisText: [String: Any] = [
            "title": "직접 분석", "summary": "s", "category": "생활",
            "materials": [], "steps": [["id": 1, "summary": "a", "detail": "b",
                                        "t_start": "0:05", "t_end": "0:20"]],
            "visual_guides": [],
        ]
        let envelope: [String: Any] = ["candidates": [["content": ["parts": [
            ["text": String(data: try JSONSerialization.data(withJSONObject: analysisText),
                            encoding: .utf8)!]]]]]]
        // 브리프 원안은 `envelope`([String: Any])를 @Sendable 클로저 안에서 직렬화했으나,
        // Swift 6 엄격 동시성이 비Sendable 캡처를 컴파일 에러로 막는다 — 클로저 밖에서
        // Data로 미리 직렬화해 Sendable 값만 캡처하도록 적응(동작은 동일).
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        GeminiAPIStub.shared.handler = { _ in (200, envelopeData) }

        let result = try await makeAPI().analyze(
            videoURL: "https://m.youtube.com/watch?v=4ioPBiTWm3M",
            profile: "generic", language: "ko", duration: 120, geminiKey: "test-key")

        #expect(result.videoId == "4ioPBiTWm3M")
        #expect(result.analysis.steps[0].tStart == 5)          // normalize 적용
        #expect(result.analysis.duration == 120)               // 메타 주입
        let request = try #require(GeminiAPIStub.shared.capturedRequest)
        #expect(request.url?.absoluteString.contains(
            "models/gemini-flash-lite-latest:generateContent") == true)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        let body = try JSONSerialization.jsonObject(
            with: try #require(GeminiAPIStub.shared.capturedBody)) as! [String: Any]
        let generation = body["generationConfig"] as! [String: Any]
        #expect(generation["response_mime_type"] as? String == "application/json")
        #expect(generation["response_json_schema"] != nil)
        let parts = ((body["contents"] as! [[String: Any]])[0]["parts"] as! [[String: Any]])
        #expect((parts[0]["file_data"] as? [String: Any])?["file_uri"] as? String
                == "https://m.youtube.com/watch?v=4ioPBiTWm3M")
    }

    @Test func mapsRateLimitAndModelErrors() async throws {
        defer { reset() }
        GeminiAPIStub.shared.handler = { _ in (429, Data("{}".utf8)) }
        await #expect(throws: StepkeeperAPIError.rateLimited) {
            _ = try await self.makeAPI().analyze(
                videoURL: "https://youtu.be/4ioPBiTWm3M", profile: "generic",
                language: "ko", duration: 10, geminiKey: "k")
        }
        GeminiAPIStub.shared.handler = { _ in (500, Data("{}".utf8)) }
        await #expect(throws: StepkeeperAPIError.modelFailure("Gemini 오류 (HTTP 500)")) {
            _ = try await self.makeAPI().analyze(
                videoURL: "https://youtu.be/4ioPBiTWm3M", profile: "generic",
                language: "ko", duration: 10, geminiKey: "k")
        }
        GeminiAPIStub.shared.handler = { _ in (200, Data(#"{"candidates": []}"#.utf8)) }
        await #expect(throws: StepkeeperAPIError.invalidResponse) {
            _ = try await self.makeAPI().analyze(
                videoURL: "https://youtu.be/4ioPBiTWm3M", profile: "generic",
                language: "ko", duration: 10, geminiKey: "k")
        }
    }
}
