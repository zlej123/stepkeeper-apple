import Testing
import Foundation
@testable import stepkeeper

@Suite(.serialized)
@MainActor
struct AppModelTests {
    private func makeModel(root: URL, linkMode: Bool = false,
                           serverURL: String? = "http://stub.local:8787") -> AppModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AppModelStub.self]
        let session = URLSession(configuration: config)
        let keychain = InMemorySecretStore("test-key")
        let defaults = UserDefaults(suiteName: "stepkeeper.tests.appmodel")!
        defaults.removePersistentDomain(forName: "stepkeeper.tests.appmodel")
        Settings.registerDefaults(defaults)
        if let serverURL {
            defaults.set(serverURL, forKey: Settings.serverURLKey)
        } else {
            defaults.set("", forKey: Settings.serverURLKey)
        }
        defaults.set(linkMode, forKey: Settings.linkModeKey)
        return AppModel(
            keychain: keychain,
            documentStore: DocumentStore(root: root),
            defaults: defaults,
            makeAPI: { StepkeeperAPI(baseURL: $0, session: session) },
            makeGeminiAPI: { GeminiAPI(session: session) })
    }

    @Test func detectsRecipeProfileFromTitle() {
        #expect(AppModel.detectProfile(title: "돼지고기 김치볶음 레시피 - YouTube") == "recipe")
        #expect(AppModel.detectProfile(title: "Easy pasta cooking guide") == "recipe")
        #expect(AppModel.detectProfile(title: "요리 초보 탈출") == "recipe")
        #expect(AppModel.detectProfile(title: "선반 조립 하우투") == "generic")
    }

    @Test func performAnalysisLinkModeSavesDocument() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkeeper-appmodel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // linkMode: true — Task 11이 캡처 분기를 추가해도 이 테스트는 링크 경로를 검증한다
        let model = makeModel(root: root, linkMode: true)
        let fixture = try Bundle.fixtureData("analyze-response")
        AppModelStub.shared.handler = { _ in (200, fixture) }
        defer { AppModelStub.shared.handler = nil }

        await model.performAnalysis(videoId: "dQw4w9WgXcQ", duration: 90)

        guard case .done(let meta) = model.stage else {
            Issue.record("stage=\(model.stage)"); return
        }
        let doc = model.document(id: meta.id)
        #expect(doc != nil)
        #expect(doc!.markdown.contains("▶ [영상 0:30에서 직접 확인](https://youtu.be/dQw4w9WgXcQ?t=30)"))
        #expect(doc!.picks.isEmpty)                    // 링크 모드: 픽 없음
        #expect(model.documents().count == 1)
    }

    @Test func performAnalysisMapsErrorToFailedStage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkeeper-appmodel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        AppModelStub.shared.handler = { _ in (429, Data(#"{"detail": "quota"}"#.utf8)) }
        defer { AppModelStub.shared.handler = nil }

        await model.performAnalysis(videoId: "dQw4w9WgXcQ", duration: 90)

        guard case .failed(let message) = model.stage else {
            Issue.record("stage=\(model.stage)"); return
        }
        #expect(message.contains("한도"))
    }

    /// v1.3: 서버 URL이 비면 StepkeeperAPI(서버)가 아니라 GeminiAPI(직접)로 라우팅된다.
    /// 핸들러 내부 #expect 금지(v1 교훈) — 요청을 캡처만 하고, 단언은 테스트 본문에서 한다.
    @Test func emptyServerURLRoutesToDirectGemini() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkeeper-appmodel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root, linkMode: true, serverURL: nil)   // 빈 URL → 직접
        let analysisText: [String: Any] = [
            "title": "직접", "summary": "s", "category": "c", "materials": [],
            "steps": [["id": 1, "summary": "a", "detail": "b",
                       "t_start": "0:05", "t_end": "0:20"]],
            "visual_guides": [],
        ]
        let envelope: [String: Any] = ["candidates": [["content": ["parts": [
            ["text": String(data: try JSONSerialization.data(withJSONObject: analysisText),
                            encoding: .utf8)!]]]]]]
        // GeminiAPITests(T1)와 동일 적응: 비Sendable [String: Any]를 @Sendable 핸들러 클로저 밖에서
        // Data로 미리 직렬화해 Sendable 값만 캡처(Swift 6 엄격 동시성이 강제, 동작은 동일).
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        AppModelStub.shared.handler = { _ in (200, envelopeData) }
        defer { AppModelStub.shared.handler = nil }

        await model.performAnalysis(videoId: "dQw4w9WgXcQ", duration: 90)

        guard case .done = model.stage else { Issue.record("stage=\(model.stage)"); return }
        // 직접 모드 증명: 요청이 서버가 아니라 Gemini 호스트로 갔다.
        #expect(AppModelStub.shared.capturedRequest?.url?.host == "generativelanguage.googleapis.com")
    }

    @Test func startRejectsInvalidURLWithoutTouchingPlayer() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkeeper-appmodel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        await model.start(urlString: "https://example.com/not-youtube")
        guard case .failed(let message) = model.stage else {
            Issue.record("stage=\(model.stage)"); return
        }
        #expect(message.contains("유튜브"))
    }

    @Test func startInvalidatesInFlightFlowState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkeeper-appmodel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let fixture = try Bundle.fixtureData("analyze-response")
        let envelope = try JSONDecoder().decode(AnalyzeEnvelope.self, from: fixture)
        model.pendingResult = AnalyzeResult(videoId: envelope.videoId,
                                            analysis: envelope.analysis, rawAnalysis: fixture)
        model.captures = [GuideCapture(guide: envelope.analysis.visualGuides[0], candidates: [])]

        await model.start(urlString: "not-a-youtube-url")   // 유효성 실패해도 무효화는 선행돼야 한다

        #expect(model.captures.isEmpty)
        #expect(model.pendingResult == nil)
    }
}

@Suite(.serialized)
@MainActor
struct AutoPickFlowTests {
    private func makeModel(autoPick: Bool, key: String = "test-key")
        -> (AppModel, UserDefaults) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AppModelStub.self]
        let session = URLSession(configuration: config)
        let keychain = InMemorySecretStore(key.isEmpty ? nil : key)
        let suite = "stepkeeper.tests.autopick"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        Settings.registerDefaults(defaults)
        defaults.set(autoPick, forKey: Settings.autoPickKey)
        let model = AppModel(
            keychain: keychain,
            documentStore: DocumentStore(root: FileManager.default.temporaryDirectory
                .appendingPathComponent("stepkeeper-autopick-\(UUID().uuidString)")),
            defaults: defaults,
            makeAPI: { StepkeeperAPI(baseURL: $0, session: session) },
            makeGeminiAPI: { GeminiAPI(session: session) })
        model.captures = [
            GuideCapture(guide: VisualGuide(
                id: "vg-1", stepId: 1, sourcePhrase: "until golden brown",
                phrase: "crust", type: "color",
                whatToShow: "deep brown crust", bestVisualTimestamp: 30,
                guideText: "flip when browned", importance: 0.9),
                candidates: ["before", "center", "after"].map {
                    CaptureCandidate(slot: $0, time: 30, jpeg: Data([0xFF, 0xD8])) }),
        ]
        return (model, defaults)
    }

    @Test func offByDefaultLeavesPicksToTheUser() async {
        let (model, defaults) = makeModel(autoPick: false)
        #expect(defaults.bool(forKey: Settings.autoPickKey) == false)
        await model.runAutoPickIfEnabled()
        #expect(model.autoPicks.isEmpty)
        #expect(model.autoPickNotice == nil)
        #expect(model.suggestedPicks() == ["vg-1": "center"])   // 기본값 그대로
    }

    @Test func aiPickOverridesTheDefaultSelection() async {
        defer { AppModelStub.shared.reset() }
        AppModelStub.shared.handler = { _ in
            (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"{\"picks\":[{\"guide_id\":\"vg-1\",\"slot\":\"after\",\"reason\":\"crust only visible here\"}]}"}]}}]}"#.utf8))
        }
        let (model, _) = makeModel(autoPick: true)
        await model.runAutoPickIfEnabled()
        #expect(model.autoPicks["vg-1"]?.slot == "after")
        #expect(model.suggestedPicks() == ["vg-1": "after"])
        #expect(model.autoPickNotice == nil)
    }

    @Test func failureKeepsTheFlowOnManualPicking() async {
        defer { AppModelStub.shared.reset() }
        AppModelStub.shared.handler = { _ in (429, Data("{}".utf8)) }
        let (model, _) = makeModel(autoPick: true)
        await model.runAutoPickIfEnabled()
        #expect(model.autoPicks.isEmpty)
        #expect(model.autoPickNotice != nil)                    // 이유를 알려주고
        #expect(model.suggestedPicks() == ["vg-1": "center"])   // 기본값으로 계속 진행
    }

    @Test func withoutKeyItExplainsInsteadOfFailingSilently() async {
        let (model, _) = makeModel(autoPick: true, key: "")
        await model.runAutoPickIfEnabled()
        #expect(model.autoPickNotice != nil)
        #expect(model.suggestedPicks() == ["vg-1": "center"])
    }
}

@Suite(.serialized)
@MainActor
struct AutoPickStatsTests {
    private func makeModel() -> (AppModel, UserDefaults) {
        let suite = "stepkeeper.tests.autopickstats"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        Settings.registerDefaults(defaults)
        let model = AppModel(keychain: InMemorySecretStore("k"),
                             documentStore: DocumentStore(root: FileManager.default
                                 .temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                             defaults: defaults)
        return (model, defaults)
    }

    @Test func countsKeptAndChangedPicksLocally() {
        let (model, defaults) = makeModel()
        model.autoPicks = ["vg-1": .init(slot: "after", reason: "r"),
                           "vg-2": .init(slot: "center", reason: "r"),
                           "vg-3": .init(slot: "none", reason: "r")]
        // vg-1 유지, vg-2 변경, vg-3 변경
        model.recordAutoPickAgreement(finalPicks: ["vg-1": "after", "vg-2": "before", "vg-3": "center"])
        #expect(defaults.integer(forKey: Settings.autoPickOfferedKey) == 3)
        #expect(defaults.integer(forKey: Settings.autoPickChangedKey) == 2)

        // 누적된다
        model.autoPicks = ["vg-9": .init(slot: "center", reason: "")]
        model.recordAutoPickAgreement(finalPicks: ["vg-9": "center"])
        #expect(defaults.integer(forKey: Settings.autoPickOfferedKey) == 4)
        #expect(defaults.integer(forKey: Settings.autoPickChangedKey) == 2)
    }

    @Test func countsNothingWhenAutoPickWasNotUsed() {
        let (model, defaults) = makeModel()
        model.autoPicks = [:]
        model.recordAutoPickAgreement(finalPicks: ["vg-1": "center"])
        #expect(defaults.integer(forKey: Settings.autoPickOfferedKey) == 0)
    }

    @Test func ignoresGuidesTheUserNeverSaw() {
        let (model, defaults) = makeModel()
        model.autoPicks = ["vg-1": .init(slot: "after", reason: ""),
                           "vg-2": .init(slot: "center", reason: "")]
        model.recordAutoPickAgreement(finalPicks: ["vg-1": "after"])   // vg-2는 픽커에 없었다
        #expect(defaults.integer(forKey: Settings.autoPickOfferedKey) == 1)
        #expect(defaults.integer(forKey: Settings.autoPickChangedKey) == 0)
    }
}
