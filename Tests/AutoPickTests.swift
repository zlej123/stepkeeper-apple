import Testing
import Foundation
@testable import stepkipper

/// 코어 autopick.py 포팅 검증. 핵심 계약: **억지로 고르지 않는다** —
/// 모델이 빠뜨렸거나 응답이 이상하면 "none"(링크 폴백)이지, 임의의 프레임이 아니다.
@Suite(.serialized)
struct AutoPickTests {
    private func makeAPI() -> GeminiAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GeminiAPIStub.self]
        return GeminiAPI(session: URLSession(configuration: config))
    }
    private func capture(_ id: String) -> (guideId: String, phrase: String, whatToShow: String,
                                           guideText: String,
                                           candidates: [(slot: String, jpeg: Data)]) {
        (id, "phrase-\(id)", "what-\(id)", "guide-\(id)",
         ["before", "center", "after"].map { ($0, Data([0xFF, 0xD8])) })
    }
    private func reply(_ picks: String) -> (Int, Data) {
        (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"{\"picks\":\#(picks)}"}]}}]}"#.utf8))
    }
    private static func isVerify(_ request: URLRequest) -> Bool {
        String(data: request.bodyData ?? Data(), encoding: .utf8)?
            .contains("선택된 프레임을 검증") == true
    }
    /// 검증 호출에는 shows로, 선택 호출에는 picks로 답하는 핸들러
    private func handler(picks: String, shows: Bool = true, verifyReason: String = "")
        -> @Sendable (URLRequest) -> (Int, Data) {
        let verify = (200, Data(
            #"{"candidates":[{"content":{"parts":[{"text":"{\"shows\":\#(shows),\"reason\":\"\#(verifyReason)\"}"}]}}]}"#.utf8))
        let pick = reply(picks)
        return { request in Self.isVerify(request) ? verify : pick }
    }

    @Test func mapsSlotsAndReasons() async throws {
        defer { GeminiAPIStub.shared.reset() }
        GeminiAPIStub.shared.handler = self.handler(
            picks: #"[{\"guide_id\":\"vg-1\",\"slot\":\"after\",\"reason\":\"crust visible\"}]"#)
        let picks = try await makeAPI().autoPick(
            captures: [capture("vg-1")], language: "en", geminiKey: "k")
        #expect(picks["vg-1"] == GeminiAPI.AutoPick(slot: "after", reason: "crust visible"))
    }

    @Test func verificationRejectionFallsBackToNone() async throws {
        // 자기 검증 패스: 고른 한 장을 다시 보여 "정말 보이는가"를 묻는다.
        // 실측 #6 — 렌치가 어느 후보에도 없는데 "그중 제일 나은" center를 골랐다.
        defer { GeminiAPIStub.shared.reset() }
        GeminiAPIStub.shared.handler = self.handler(
            picks: #"[{\"guide_id\":\"vg-1\",\"slot\":\"center\",\"reason\":\"best\"}]"#,
            shows: false, verifyReason: "렌치가 보이지 않음")
        let picks = try await makeAPI().autoPick(
            captures: [capture("vg-1")], language: "ko", geminiKey: "k")
        #expect(picks["vg-1"] == GeminiAPI.AutoPick(slot: "none", reason: "렌치가 보이지 않음"))
    }

    @Test func verificationRequestCarriesOnlyThePickedFrame() async throws {
        defer { GeminiAPIStub.shared.reset() }
        GeminiAPIStub.shared.handler = self.handler(
            picks: #"[{\"guide_id\":\"vg-1\",\"slot\":\"center\",\"reason\":\"ok\"}]"#)
        _ = try await makeAPI().autoPick(
            captures: [capture("vg-1")], language: "en", geminiKey: "k")
        // 마지막 요청 = 검증 호출: 이미지 1장 + '보여야 할 것'만 담는다
        let body = try #require(GeminiAPIStub.shared.capturedBody)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let parts = try #require(((payload["contents"] as? [[String: Any]])?
            .first?["parts"] as? [[String: Any]]))
        let texts = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        #expect(texts.contains("선택된 프레임을 검증"))
        #expect(texts.contains("what-vg-1"))
        #expect(parts.filter { $0["inline_data"] != nil }.count == 1)
    }

    @Test func missingOrInvalidPicksFallBackToNone() async throws {
        defer { GeminiAPIStub.shared.reset() }
        // vg-1은 응답에 없고, vg-2는 슬롯이 스키마 밖 값 → 둘 다 none 이어야 한다
        GeminiAPIStub.shared.handler = { _ in
            self.reply(#"[{\"guide_id\":\"vg-2\",\"slot\":\"sideways\",\"reason\":\"x\"},"# +
                       #"{\"guide_id\":\"vg-9\",\"slot\":\"center\",\"reason\":\"모르는 가이드\"}]"#)
        }
        let picks = try await makeAPI().autoPick(
            captures: [capture("vg-1"), capture("vg-2")], language: "ko", geminiKey: "k")
        #expect(picks["vg-1"]?.slot == "none")
        #expect(picks["vg-2"]?.slot == "none")
        #expect(picks["vg-9"] == nil)                 // 질문하지 않은 가이드는 받아들이지 않는다
    }

    @Test func skipsGuidesWithIncompleteCandidates() async throws {
        defer { GeminiAPIStub.shared.reset() }
        let partial = ("vg-1", "p", "w", "g", [("center", Data([0xFF]))])
        GeminiAPIStub.shared.handler = { _ in self.reply("[]") }
        // 후보가 3장이 아니면 아예 묻지 않는다 → 요청도 나가지 않고 결과도 비어 있다
        let picks = try await makeAPI().autoPick(
            captures: [partial], language: "en", geminiKey: "k")
        #expect(picks.isEmpty)
        #expect(GeminiAPIStub.shared.capturedRequest == nil)
    }

    @Test func requestCarriesPromptGuideTextAndThreeImages() async throws {
        defer { GeminiAPIStub.shared.reset() }
        GeminiAPIStub.shared.handler = { _ in self.reply("[]") }
        _ = try await makeAPI().autoPick(
            captures: [capture("vg-1")], language: "en", geminiKey: "k")
        let body = try #require(GeminiAPIStub.shared.capturedBody)
        let payload = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let parts = try #require(((payload["contents"] as? [[String: Any]])?
            .first?["parts"] as? [[String: Any]]))
        let texts = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        #expect(texts.contains("what-vg-1"))          // 보여야 할 것
        #expect(texts.contains("guide-vg-1"))         // 가이드 문구
        #expect(texts.contains("reason은 en 언어로"))  // 근거를 문서 언어로
        #expect(parts.filter { $0["inline_data"] != nil }.count == 3)
        let config = try #require(payload["generationConfig"] as? [String: Any])
        #expect(config["response_json_schema"] != nil)   // 구조화 출력 강제
    }

    @Test func rateLimitSurfacesAsTypedError() async throws {
        defer { GeminiAPIStub.shared.reset() }
        GeminiAPIStub.shared.handler = { _ in (429, Data("{}".utf8)) }
        await #expect(throws: StepkipperAPIError.rateLimited) {
            _ = try await self.makeAPI().autoPick(
                captures: [self.capture("vg-1")], language: "en", geminiKey: "k")
        }
    }
}
