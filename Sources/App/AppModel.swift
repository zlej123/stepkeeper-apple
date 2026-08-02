import Foundation
import Observation

enum FlowRecovery: Equatable {
    /// 입력 자체가 복구 불가능하다. 현재 플로우를 닫고 올바른 URL로 다시 시작해야 한다.
    case closeOnly
    /// 같은 영상과 프로파일로 분석을 다시 실행한다.
    case retryAnalysis
    /// 설정을 고친 뒤 같은 영상과 프로파일로 분석을 다시 실행한다.
    case settingsAndRetry
    /// 분석·캡처 결과는 그대로 두고 문서 조립/저장만 다시 실행한다.
    case retryBuild

    var showsRetry: Bool {
        switch self {
        case .retryAnalysis, .settingsAndRetry, .retryBuild: true
        case .closeOnly: false
        }
    }

    var showsSettings: Bool {
        self == .settingsAndRetry
    }
}

struct FlowFailure: Equatable, ExpressibleByStringLiteral {
    var message: String
    var recovery: FlowRecovery

    init(message: String, recovery: FlowRecovery) {
        self.message = message
        self.recovery = recovery
    }

    /// 테스트·프리뷰의 기존 `.failed("…")` 표현은 일반 재시도 오류로 호환한다.
    init(stringLiteral value: String) {
        self.init(message: value, recovery: .retryAnalysis)
    }

    /// 기존 테스트가 오류 문구 일부를 검사할 수 있게 String과 같은 최소 표면을 유지한다.
    func contains(_ other: String) -> Bool {
        message.contains(other)
    }
}

enum FlowStage: Equatable {
    case idle
    case loadingPlayer
    case readyToAnalyze(duration: Int, title: String)
    case analyzing(duration: Int)
    case capturing(current: Int, total: Int)   // Task 11
    case autoPicking                            // AI가 후보를 고르는 중 (설정 켬)
    case picking                                // Task 12
    case building
    case done(DocumentMeta)
    case failed(FlowFailure)
}

enum SharedStartTrigger {
    case automatic
    case userInitiated
}

struct CaptureCandidate: Sendable, Equatable {
    var slot: String   // "before" | "center" | "after"
    var time: Int
    var jpeg: Data?    // nil = 이 후보 캡처 실패
}

struct GuideCapture: Identifiable, Sendable {
    var guide: VisualGuide
    var candidates: [CaptureCandidate]
    var id: String { guide.id }
    /// 세 후보 모두 실패 → 자동 링크 폴백 대상
    var failed: Bool { candidates.allSatisfy { $0.jpeg == nil } }
}

private struct DocumentBuildPayload {
    var result: AnalyzeResult
    var picks: [String: String]
    var images: [String: Data]
}

@MainActor @Observable
final class AppModel {
    var stage: FlowStage = .idle
    var detectedProfile = "generic"
    var profileOverride: String?
    /// E2E처럼 사람이 확인 버튼을 누르지 않는 경로에서 readyToAnalyze를 자동 통과.
    /// 공유 확장 진입은 false 유지 — 사용자가 readyToAnalyze에서 프로파일 확인 후 시작한다.
    var autoContinue = false
    /// AI 자동 선택 결과 (가이드 id → 슬롯·근거). 픽커가 미리 선택 상태와 근거 문구로 쓴다.
    var autoPicks: [String: GeminiAPI.AutoPick] = [:]
    /// 자동 선택을 시도했지만 실패한 경우의 안내 (키 없음·한도·네트워크). 픽커 상단에 표시.
    var autoPickNotice: String?

    let bridge = PlayerBridge()

    private let keychain: any SecretStoring
    private let store: DocumentStore
    private let defaults: UserDefaults
    private let makeAPI: (URL) -> StepkipperAPI
    private let makeGeminiAPI: () -> GeminiAPI
    private var currentVideoId: String?
    private var currentURLString: String?
    private var pendingDuration: Int?
    var captures: [GuideCapture] = []
    var pendingResult: AnalyzeResult?
    /// 저장 실패 시 분석/캡처를 반복하지 않고 동일 결과로 build만 재시도하기 위한 payload.
    private var pendingBuild: DocumentBuildPayload?
    /// reset() 시 증가 — 취소 뒤 도착한 비동기 결과가 stage를 덮어쓰지 않게 한다
    private var generation = 0

    init(keychain: any SecretStoring = KeychainStore.geminiKey,
         documentStore: DocumentStore? = nil,
         defaults: UserDefaults = .standard,
         makeAPI: @escaping (URL) -> StepkipperAPI = { StepkipperAPI(baseURL: $0) },
         makeGeminiAPI: @escaping () -> GeminiAPI = { GeminiAPI() }) {
        self.keychain = keychain
        self.store = documentStore
            ?? ((try? DocumentStore.defaultRoot()).map(DocumentStore.init)
                ?? DocumentStore(root: FileManager.default.temporaryDirectory))
        self.defaults = defaults
        self.makeAPI = makeAPI
        self.makeGeminiAPI = makeGeminiAPI
    }

    /// 공유 인박스에서 다음 URL을 꺼내 분석 시작. 시작할 수 없거나 URL이 없으면 false.
    ///
    /// 자동 픽업은 idle에서만 허용한다. 앱 활성화 이벤트가 분석 중이거나 실패/완료 화면을
    /// 조용히 다른 영상으로 바꾸면 사용자가 현재 작업의 결과를 잃었다고 느끼기 때문이다.
    /// 사용자 탭은 idle뿐 아니라 done/failed에서도 다음 항목을 명시적으로 시작할 수 있다.
    @discardableResult
    func startNextShared(trigger: SharedStartTrigger = .userInitiated) -> Bool {
        guard canStartShared(trigger: trigger) else { return false }
        guard let url = ShareInbox.pop() else { return false }
        autoContinue = false
        profileOverride = nil

        // Task가 실제 start()에 진입하기 전까지도 두 번째 활성화/탭이 큐를 또 pop하지 못하게
        // 즉시 진행 상태를 예약한다. 그 사이 취소되면 generation 가드가 예약 작업도 막는다.
        generation += 1
        let reservation = generation
        stage = .loadingPlayer
        Task { [weak self] in
            guard let self, self.generation == reservation else { return }
            await self.start(urlString: url)
        }
        return true
    }

    private func canStartShared(trigger: SharedStartTrigger) -> Bool {
        switch (trigger, stage) {
        case (.automatic, .idle),
             (.userInitiated, .idle),
             (.userInitiated, .done),
             (.userInitiated, .failed):
            true
        default:
            false
        }
    }

    var profile: String { profileOverride ?? detectedProfile }
    var linkMode: Bool { defaults.bool(forKey: Settings.linkModeKey) }

    static func detectProfile(title: String) -> String {
        title.range(of: "레시피|요리|recipe|cook", options: [.regularExpression, .caseInsensitive])
            != nil ? "recipe" : "generic"
    }

    func documents() -> [DocumentMeta] { (try? store.list()) ?? [] }
    func document(id: String) -> SavedDocument? { try? store.load(id: id) }
    func deleteDocument(id: String) { try? store.delete(id: id) }

    func start(urlString: String) async {
        await start(urlString: urlString, clearProfileOverride: true)
    }

    private func start(urlString: String, clearProfileOverride: Bool) async {
        // 재진입 무효화: 진행 중 플로우(캡처 루프 포함)를 이 시점에 stale로 만든다 (최종 리뷰 Critical 1).
        // 공유 픽업·새 URL 시작이 기존 플로우 위에 겹치는 경로를 봉인하고, retry()의 세대 미증가도 함께 해소.
        generation += 1
        if clearProfileOverride {
            // 프로파일 선택은 영상 단위 상태다. 이전 영상에서 사용자가 고른 override가 다음 영상의
            // 메타데이터 자동 감지를 덮어쓰지 않도록, URL 유효성/키 검사보다 먼저 비운다.
            profileOverride = nil
        }
        captures = []
        pendingResult = nil
        pendingBuild = nil
        currentURLString = urlString   // 키 가드보다 앞 — 진입 전 실패도 retry로 복구 가능 (Important 3)
        guard let videoId = YouTubeURL.videoID(from: urlString) else {
            stage = .failed(FlowFailure(
                message: String(localized: "That's not a YouTube URL — paste a watch/youtu.be/shorts link"),
                recovery: .closeOnly))
            return
        }
        guard let key = try? keychain.load(), !key.isEmpty else {
            stage = .failed(FlowFailure(
                message: String(localized: "Add your Gemini API key in Settings"),
                recovery: .settingsAndRetry))
            return
        }
        currentVideoId = videoId
        let gen = generation
        stage = .loadingPlayer
        bridge.load(videoID: videoId)
        do {
            let meta = try await bridge.waitForMetadata(expecting: videoId)
            guard gen == generation else { return }   // 취소됨
            detectedProfile = Self.detectProfile(title: meta.title)
            pendingDuration = meta.duration
            stage = .readyToAnalyze(duration: meta.duration, title: meta.title)
            if autoContinue { await confirmAnalyze() }
        } catch {
            guard gen == generation else { return }
            stage = .failed(Self.flowFailure(
                for: error,
                fallback: String(localized: "The player didn't load — try again")))
        }
    }

    func confirmAnalyze() async {
        guard let videoId = currentVideoId, let duration = pendingDuration else { return }
        await performAnalysis(videoId: videoId, duration: duration)
    }

    /// 분석 → (Task 11 전까지는 항상) 링크 문서 저장
    func performAnalysis(videoId: String, duration: Int) async {
        guard let key = try? keychain.load(), !key.isEmpty else {
            stage = .failed(FlowFailure(
                message: String(localized: "Add your Gemini API key in Settings"),
                recovery: .settingsAndRetry))
            return
        }
        let serverURLString = (defaults.string(forKey: Settings.serverURLKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let gen = generation
        stage = .analyzing(duration: duration)
        do {
            let videoURL = "https://m.youtube.com/watch?v=\(videoId)"
            let language = defaults.string(forKey: Settings.languageKey) ?? Settings.defaultLanguage
            let result: AnalyzeResult
            if serverURLString.isEmpty {
                // 직접 모드 (v1.3 기본): 서버 없이 Gemini 호출
                result = try await makeGeminiAPI().analyze(
                    videoURL: videoURL, profile: profile, language: language,
                    duration: duration, geminiKey: key)
            } else {
                guard let serverURL = URL(string: serverURLString),
                      let scheme = serverURL.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      serverURL.host != nil else {
                    stage = .failed(FlowFailure(
                        message: String(localized: "That server URL isn't valid — check Settings"),
                        recovery: .settingsAndRetry))
                    return
                }
                result = try await makeAPI(serverURL).analyze(
                    videoURL: videoURL, profile: profile, language: language,
                    duration: duration, geminiKey: key)
            }
            guard gen == generation else { return }   // 취소됨
            if linkMode {
                await buildDocument(result: result, picks: [:], images: [:])
            } else {
                await captureCandidates(result: result)
            }
        } catch {
            guard gen == generation else { return }
            stage = .failed(Self.flowFailure(
                for: error,
                fallback: String(localized: "Analysis failed — try again")))
        }
    }

    func buildDocument(result: AnalyzeResult, picks: [String: String],
                       images: [String: Data]) async {
        pendingBuild = DocumentBuildPayload(result: result, picks: picks, images: images)
        stage = .building
        do {
            let imageRefs = Dictionary(uniqueKeysWithValues: images.keys.map { name in
                (String(name.dropLast(4)), name)   // "vg-1.jpg" → ("vg-1": "vg-1.jpg")
            })
            let markdown = try MarkdownBuilder.markdown(
                videoId: result.videoId, analysis: result.analysis, imageRefs: imageRefs)
            let meta = try store.save(
                videoId: result.videoId, title: result.analysis.title,
                analysis: result.analysis, rawAnalysis: result.rawAnalysis,
                picks: picks, images: images, markdown: markdown)
            pendingBuild = nil
            stage = .done(meta)
        } catch {
            stage = .failed(FlowFailure(
                message: String(localized: "Couldn't save the document")
                    + " — \(error.localizedDescription)",
                recovery: .retryBuild))
        }
    }

    /// 가이드×3슬롯 캡처. 실패는 후보 단위 nil로 격리(가이드 단위 링크 폴백 — 전체 중단 없음).
    func captureCandidates(result: AnalyzeResult) async {
        pendingResult = result
        let steps = result.analysis.stepsByID
        let guides = result.analysis.visualGuides.filter { $0.bestVisualTimestamp != nil }
        guard !guides.isEmpty else {
            await buildDocument(result: result, picks: [:], images: [:])
            return
        }
        let duration = result.analysis.duration ?? pendingDuration ?? 0
        let gen = generation
        captures = []
        try? await bridge.beginCaptureSession()
        for (index, guide) in guides.enumerated() {
            guard gen == generation else { await bridge.endCaptureSession(); return }
            stage = .capturing(current: index + 1, total: guides.count)
            let times = CandidateTimes(step: steps[guide.stepId],
                                       center: guide.bestVisualTimestamp!, duration: duration,
                                       guideType: guide.type)
            var candidates: [CaptureCandidate] = []
            for (slot, time) in times.slots {
                let jpeg = try? await bridge.captureFrame(at: time)
                // 취소(reset) 확인: 슬롯 await 중 세대가 바뀌었으면 어떤 append도 하지 않는다 (리뷰 반영 —
                // stale GuideCapture가 새 세대 captures에 섞이면 id 충돌 크래시/타 영상 이미지 혼입 가능)
                guard gen == generation else { await bridge.endCaptureSession(); return }
                candidates.append(CaptureCandidate(slot: slot, time: time, jpeg: jpeg))
            }
            captures.append(GuideCapture(guide: guide, candidates: candidates))
        }
        await bridge.endCaptureSession()
        guard gen == generation else { return }
        await runAutoPickIfEnabled(gen: gen)
        guard gen == generation else { return }
        stage = .picking
        if autoContinue { await finishPicking(picks: suggestedPicks()) }
    }

    /// 설정이 켜져 있으면 Gemini vision으로 후보를 고른다. 실패해도 흐름은 계속되고
    /// 픽커는 기본값(center)으로 열린다 — 자동 선택은 편의지 필수 경로가 아니다.
    /// gen 생략 = 현재 세대 (테스트 호출 편의 — private 상태를 노출하지 않는다)
    func runAutoPickIfEnabled(gen requested: Int? = nil) async {
        let gen = requested ?? generation
        autoPicks = [:]
        autoPickNotice = nil
        guard defaults.bool(forKey: Settings.autoPickKey) else { return }
        guard let geminiKey = (try? keychain.load()) ?? nil, !geminiKey.isEmpty else {
            autoPickNotice = String(localized: "AI pick needs a Gemini API key — pick manually")
            return
        }
        let language = defaults.string(forKey: Settings.languageKey) ?? Settings.defaultLanguage
        let payload = captures.compactMap { capture -> (guideId: String, phrase: String,
                                                        whatToShow: String, guideText: String,
                                                        candidates: [(slot: String, jpeg: Data)])? in
            let usable = capture.candidates.compactMap { candidate in
                candidate.jpeg.map { (slot: candidate.slot, jpeg: $0) }
            }
            guard usable.count == 3 else { return nil }   // 부분 실패 가이드는 사람이 고른다
            return (capture.guide.id, capture.guide.phrase, capture.guide.whatToShow,
                    capture.guide.guideText, usable)
        }
        guard !payload.isEmpty else { return }
        stage = .autoPicking      // 픽커는 AI 응답 뒤에 연다 — 먼저 열면 기본값이 잡힌 채 시작된다
        do {
            let picks = try await makeGeminiAPI().autoPick(
                captures: payload, language: language, geminiKey: geminiKey)
            guard gen == generation else { return }
            autoPicks = picks
        } catch {
            guard gen == generation else { return }
            autoPickNotice = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "AI pick failed — pick manually")
        }
    }

    /// 픽커가 열릴 때의 미리 선택 — AI 선택이 있으면 그것, 없으면 기본값
    func suggestedPicks() -> [String: String] {
        var picks = defaultPicks()
        for (guideId, pick) in autoPicks where picks[guideId] != nil {
            picks[guideId] = pick.slot
        }
        return picks
    }

    /// center가 살아 있으면 center, 아니면 none (확장의 기본 체크와 동일)
    func defaultPicks() -> [String: String] {
        Dictionary(uniqueKeysWithValues: captures.map { capture in
            (capture.guide.id,
             capture.candidates.contains { $0.slot == "center" && $0.jpeg != nil }
                ? "center" : "none")
        })
    }

    func finishPicking(picks: [String: String]) async {
        guard let result = pendingResult else { return }
        var images: [String: Data] = [:]
        for capture in captures {
            let pick = picks[capture.guide.id] ?? "none"
            guard pick != "none",
                  let jpeg = capture.candidates.first(where: { $0.slot == pick })?.jpeg else {
                continue
            }
            images["\(capture.guide.id).jpg"] = jpeg
        }
        recordAutoPickAgreement(finalPicks: picks)
        await buildDocument(result: result, picks: picks, images: images)
        captures = []
        pendingResult = nil
    }

    /// AI 선택을 사용자가 몇 번이나 바꿨는지만 **기기에** 센다. 어디로도 보내지 않고,
    /// 슬롯 이름(before/center/after/none)만 비교한다 — 영상 내용은 담기지 않는다.
    ///
    /// 한계(설정 화면에도 적어둔다): 자동 선택이 미리 체크돼 있으므로, 사용자가 확인 없이
    /// 그대로 넘긴 경우도 "유지"로 세어진다. 즉 유지 비율은 실제보다 높게 나온다 —
    /// "쓸 만한가"의 대략적 신호로만 읽어야 하는 수치다.
    func recordAutoPickAgreement(finalPicks: [String: String]) {
        guard !autoPicks.isEmpty else { return }
        var offered = defaults.integer(forKey: Settings.autoPickOfferedKey)
        var changed = defaults.integer(forKey: Settings.autoPickChangedKey)
        for (guideId, pick) in autoPicks {
            guard let final = finalPicks[guideId] else { continue }
            offered += 1
            if final != pick.slot { changed += 1 }
        }
        defaults.set(offered, forKey: Settings.autoPickOfferedKey)
        defaults.set(changed, forKey: Settings.autoPickChangedKey)
    }

    /// 픽커 화면의 원탭 신고 — pendingResult 기반. 성공 nil, 실패 시 사용자 메시지 반환.
    func submitIssueReport(reason: ReportReason, note: String,
                           picks: [String: String]) async -> String? {
        guard let result = pendingResult else { return String(localized: "Nothing to report yet") }
        let report = IssueReport(
            url: "https://m.youtube.com/watch?v=\(result.videoId)",
            videoId: result.videoId, reason: reason, note: note,
            profile: result.analysis.profile ?? profile,
            language: result.analysis.outputLanguage
                ?? defaults.string(forKey: Settings.languageKey) ?? Settings.defaultLanguage,
            rawAnalysis: result.rawAnalysis, picks: picks, client: IssueReport.clientTag)
        // 수집기가 없으면 메일 앱으로 폴백 — 배포 전에도 신고 경로가 살아 있게
        guard let serverURL = ReportCollector.resolveURL(defaults: defaults) else {
            return ReportMailer.compose(report) ? nil
                : String(localized: "Couldn't open your mail app — the report was copied to the clipboard")
        }
        do {
            try await makeAPI(serverURL).submitReport(report)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? String(localized: "Couldn't send the report")
        }
    }

    static func flowFailure(for error: Error, fallback: String = "") -> FlowFailure {
        let message = (error as? LocalizedError)?.errorDescription
            ?? (fallback.isEmpty ? String(localized: "Analysis failed — try again") : fallback)
        let recovery: FlowRecovery
        switch error {
        case StepkipperAPIError.missingKey,
             StepkipperAPIError.invalidKey,
             StepkipperAPIError.geminiPermission,
             StepkipperAPIError.network:
            recovery = .settingsAndRetry
        case is PlayerError,
             StepkipperAPIError.badRequest,
             StepkipperAPIError.rateLimited,
             StepkipperAPIError.modelFailure,
             StepkipperAPIError.server,
             StepkipperAPIError.geminiNetwork,
             StepkipperAPIError.invalidResponse:
            recovery = .retryAnalysis
        default:
            recovery = .retryAnalysis
        }
        return FlowFailure(message: message, recovery: recovery)
    }

    func retry() async {
        guard case .failed(let failure) = stage else { return }
        switch failure.recovery {
        case .closeOnly:
            return
        case .retryBuild:
            guard let payload = pendingBuild else { return }
            await buildDocument(
                result: payload.result, picks: payload.picks, images: payload.images)
        case .retryAnalysis, .settingsAndRetry:
            guard let urlString = currentURLString else { reset(); return }
            // 같은 영상의 복구 동작이므로 사용자가 명시적으로 고른 프로파일은 유지한다.
            // 새 URL과 공유 인박스 시작은 public start(urlString:) 경로에서 계속 초기화된다.
            await start(urlString: urlString, clearProfileOverride: false)
        }
    }

    func reset() {
        generation += 1
        stage = .idle
        currentVideoId = nil
        currentURLString = nil
        pendingDuration = nil
        profileOverride = nil
        captures = []
        pendingResult = nil
        pendingBuild = nil
    }
}
