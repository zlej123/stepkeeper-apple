import Foundation
import Observation

enum FlowStage: Equatable {
    case idle
    case loadingPlayer
    case readyToAnalyze(duration: Int, title: String)
    case analyzing(duration: Int)
    case capturing(current: Int, total: Int)   // Task 11
    case picking                                // Task 12
    case building
    case done(DocumentMeta)
    case failed(String)
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

@MainActor @Observable
final class AppModel {
    var stage: FlowStage = .idle
    var detectedProfile = "generic"
    var profileOverride: String?
    /// E2E처럼 사람이 확인 버튼을 누르지 않는 경로에서 readyToAnalyze를 자동 통과.
    /// 공유 확장 진입은 false 유지 — 사용자가 readyToAnalyze에서 프로파일 확인 후 시작한다.
    var autoContinue = false

    let bridge = PlayerBridge()

    private let keychain: KeychainStore
    private let store: DocumentStore
    private let defaults: UserDefaults
    private let makeAPI: (URL) -> StepkeeperAPI
    private let makeGeminiAPI: () -> GeminiAPI
    private var currentVideoId: String?
    private var currentURLString: String?
    private var pendingDuration: Int?
    var captures: [GuideCapture] = []
    var pendingResult: AnalyzeResult?
    /// reset() 시 증가 — 취소 뒤 도착한 비동기 결과가 stage를 덮어쓰지 않게 한다
    private var generation = 0

    init(keychain: KeychainStore = .geminiKey,
         documentStore: DocumentStore? = nil,
         defaults: UserDefaults = .standard,
         makeAPI: @escaping (URL) -> StepkeeperAPI = { StepkeeperAPI(baseURL: $0) },
         makeGeminiAPI: @escaping () -> GeminiAPI = { GeminiAPI() }) {
        self.keychain = keychain
        self.store = documentStore
            ?? ((try? DocumentStore.defaultRoot()).map(DocumentStore.init)
                ?? DocumentStore(root: FileManager.default.temporaryDirectory))
        self.defaults = defaults
        self.makeAPI = makeAPI
        self.makeGeminiAPI = makeGeminiAPI
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
        // 재진입 무효화: 진행 중 플로우(캡처 루프 포함)를 이 시점에 stale로 만든다 (최종 리뷰 Critical 1).
        // 공유 픽업·새 URL 시작이 기존 플로우 위에 겹치는 경로를 봉인하고, retry()의 세대 미증가도 함께 해소.
        generation += 1
        captures = []
        pendingResult = nil
        currentURLString = urlString   // 키 가드보다 앞 — 진입 전 실패도 retry로 복구 가능 (Important 3)
        guard let videoId = YouTubeURL.videoID(from: urlString) else {
            stage = .failed(String(localized: "That's not a YouTube URL — paste a watch/youtu.be/shorts link"))
            return
        }
        guard let key = try? keychain.load(), !key.isEmpty else {
            stage = .failed(String(localized: "Add your Gemini API key in Settings"))
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
            stage = .failed((error as? PlayerError)?.errorDescription
                            ?? String(localized: "The player didn't load — try again"))
        }
    }

    func confirmAnalyze() async {
        guard let videoId = currentVideoId, let duration = pendingDuration else { return }
        await performAnalysis(videoId: videoId, duration: duration)
    }

    /// 분석 → (Task 11 전까지는 항상) 링크 문서 저장
    func performAnalysis(videoId: String, duration: Int) async {
        guard let key = try? keychain.load(), !key.isEmpty else {
            stage = .failed(String(localized: "Add your Gemini API key in Settings"))
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
                guard let serverURL = URL(string: serverURLString) else {
                    stage = .failed(String(localized: "That server URL isn't valid — check Settings"))
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
            stage = .failed((error as? LocalizedError)?.errorDescription
                            ?? String(localized: "Analysis failed — try again"))
        }
    }

    func buildDocument(result: AnalyzeResult, picks: [String: String],
                       images: [String: Data]) async {
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
            stage = .done(meta)
        } catch {
            stage = .failed(String(localized: "Couldn't save the document") + " — \(error.localizedDescription)")
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
                                       center: guide.bestVisualTimestamp!, duration: duration)
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
        stage = .picking
        if autoContinue { await finishPicking(picks: defaultPicks()) }
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
        await buildDocument(result: result, picks: picks, images: images)
        captures = []
        pendingResult = nil
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

    func retry() async {
        guard let urlString = currentURLString else { reset(); return }
        await start(urlString: urlString)
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
    }
}
