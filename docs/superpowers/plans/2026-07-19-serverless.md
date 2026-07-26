# stepkeeper v1.3 서버리스 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 서버 URL이 비어 있으면 앱이 Gemini를 직접 호출(일반 사용자 기본), 신고는 수집기 URL로 분리, 서버 브리지에 토큰 방식 추가(Cloud Run 준비).

**Architecture:** 확장 bg.js의 direct 모드 포팅 — skill-core 자산 번들 + GeminiAPI(구조화 출력) + normalize(MM:SS→초). 기존 파이프(AnalyzeResult 이후)는 무변경. 스펙: `docs/superpowers/specs/2026-07-19-serverless-design.md` — 충돌 시 스펙 우선.

**Tech Stack:** Swift 6 / URLSession / JSONSerialization / Gemini generateContent API / FastAPI(서버 브리지).

## Global Constraints

- 앱: 모든 xcodebuild 앞에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, 로그 /tmp 리다이렉트, `.xcodeproj` 함께 커밋. 서버: `.venv/bin/python`, 코어 수정 금지, 실행 중인 8787 서버 건드리지 말 것.
- Gemini 상수: 모델 `gemini-flash-lite-latest`(설정 비노출), base `https://generativelanguage.googleapis.com/v1beta/models`, 타임아웃 180초, 헤더 `x-goog-api-key`. **키 값은 헤더 세팅 외 등장 금지.**
- 에러는 기존 `StepkeeperAPIError` 재사용: 429→`.rateLimited`, 기타 비2xx→`.modelFailure("Gemini 오류 (HTTP n)")`, 해석 불가→`.invalidResponse` (UI 분기 무변경).
- rawAnalysis = 정규화+메타(`_duration`/`_profile`/`_output_language`) 주입된 dict의 직렬화 — 서버 모드와 동일 형식 유지(저장·신고 호환).
- UI 문구 한국어 아래 코드 그대로. docs/superpowers/ 수정 금지. 커밋 메시지: 앱 한국어·서버 영어 관례.

## File Structure (최종)

```
scripts/sync-assets.sh                     # 확장: prompt/schema/rules 복사 (T1)
Resources/skill-core/{generic,recipe}/{template,prompt}.md+schema.json, engine/rules.md (T1)
Sources/Services/AnalysisNormalizer.swift  # mmssToSec + normalized (T1)
Sources/Services/GeminiAPI.swift           # 직접 분석 (T1)
Sources/Services/Settings.swift            # defaultServerURL=""·reportServerURLKey (T2·T3)
Sources/App/AppModel.swift                 # 라우팅 분기·신고 resolveURL (T2·T3)
Sources/Views/SettingsView.swift           # footer 문구·신고 수집 필드 (T2·T3)
Sources/ContentView.swift                  # STEPKEEPER_SERVER_URL env 훅 (T2)
Sources/Models/ReportCollector.swift       # resolveURL (T3)
Sources/Views/{CandidatePickerView,DocumentView}.swift  # 신고 pre-check (T3)
scripts/e2e-m1.sh·e2e-m2.sh                # SERVER_URL env 주입 (T2)
Tests/: AnalysisNormalizerTests·GeminiAPITests(T1), AppModelTests 조정(T2), ReportCollectorTests(T3), StubURLProtocol.swift에 GeminiAPIStub 추가(T1)
stepkeeper-server: app.py 토큰 브리지 + tests/test_reports.py 확장 + docs/deploy.md + README (T4)
docs/TESTING.md·README.md                  # (T5)
```

**체크포인트**: T5 완료 시 사용자 보고(직접 모드 실키 수동 확인 안내). 태스크 직렬 T1→T5.

---

### Task 1: 자산 번들 + AnalysisNormalizer + GeminiAPI

**Files:**
- Modify: `scripts/sync-assets.sh`, `Tests/StubURLProtocol.swift`(GeminiAPIStub 추가)
- Create: `Resources/skill-core/...`(스크립트 산출·커밋), `Sources/Services/AnalysisNormalizer.swift`, `Sources/Services/GeminiAPI.swift`, `Tests/AnalysisNormalizerTests.swift`, `Tests/GeminiAPITests.swift`

**Interfaces:**
- Consumes: `Analysis`/`AnalyzeResult`/`StepkeeperAPIError`/`Settings.maxGuides`/`MarkdownBuilder.hms`/`YouTubeURL.videoID`, `StubURLProtocolBase`
- Produces: `AnalysisNormalizer.mmssToSec(_ value: Any?) -> Int?`, `AnalysisNormalizer.normalized(rawObject:duration:profile:language:) throws -> (analysis: Analysis, rawAnalysis: Data)`, `GeminiAPI(session:assets:)` — `buildPrompt(profile:duration:language:maxGuides:) throws -> String`, `loadSchema(profile:) throws -> [String: Any]`, `analyze(videoURL:profile:language:maxGuides:duration:geminiKey:) async throws -> AnalyzeResult`(StepkeeperAPI.analyze와 동일 시그니처 — T2 라우팅이 의존). `GeminiAPIStub`.

- [ ] **Step 1: sync-assets.sh 전체 교체 + 실행**

```bash
#!/bin/bash
# skill-core 자산(템플릿·프롬프트·스키마·규칙)을 앱 리소스로 복사 (원본: ../stepkeeper).
# 코어 갱신 시 재실행 후 make-golden.py / make-notion-golden.py 재생성.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${STEPKEEPER_PATH:-../stepkeeper}/src/stepkeeper/skill-core"
for p in generic recipe; do
  mkdir -p "Resources/skill-core/$p"
  cp "$SRC/profiles/$p/template.md" "Resources/skill-core/$p/template.md"
  cp "$SRC/profiles/$p/prompt.md"   "Resources/skill-core/$p/prompt.md"
  cp "$SRC/profiles/$p/schema.json" "Resources/skill-core/$p/schema.json"
done
mkdir -p "Resources/skill-core/engine"
cp "$SRC/engine/rules.md" "Resources/skill-core/engine/rules.md"
echo "synced skill-core assets from $SRC"
```

```bash
chmod +x scripts/sync-assets.sh && ./scripts/sync-assets.sh && git status --short | head
```

Expected: 신규 리소스 5개(?? 표시), 기존 template.md 2개는 무변화. 폴더 레퍼런스라 project.yml 무변경, `xcodegen generate`만.

- [ ] **Step 2: GeminiAPIStub 추가**

`Tests/StubURLProtocol.swift` 끝에:

```swift
final class GeminiAPIStub: StubURLProtocolBase {
    nonisolated(unsafe) static let shared = StubStorage()
    override class var storage: StubStorage { shared }
}
```

- [ ] **Step 3: 실패하는 테스트 작성**

`Tests/AnalysisNormalizerTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct AnalysisNormalizerTests {
    @Test func convertsTimeStrings() {
        #expect(AnalysisNormalizer.mmssToSec("12:34") == 754)
        #expect(AnalysisNormalizer.mmssToSec("1:02") == 62)
        #expect(AnalysisNormalizer.mmssToSec("0:00") == 0)
        #expect(AnalysisNormalizer.mmssToSec(30) == 30)          // 이미 숫자
        #expect(AnalysisNormalizer.mmssToSec(nil) == nil)
        #expect(AnalysisNormalizer.mmssToSec("abc") == nil)
    }

    @Test func normalizesDictAndInjectsMeta() throws {
        let rawObject: [String: Any] = [
            "title": "제목", "summary": "요약", "category": "생활",
            "materials": [["name": "글루건", "amount": "1개"]],
            "steps": [["id": 1, "summary": "s", "detail": "d",
                       "t_start": "0:05", "t_end": "0:20"]],
            "visual_guides": [
                ["id": "vg-1", "step_id": 1, "source_phrase": "sp", "phrase": "p",
                 "type": "state", "what_to_show": "w",
                 "best_visual_timestamp": "0:12", "guide_text": "g", "importance": 0.9],
                ["id": "vg-2", "step_id": 1, "source_phrase": "sp", "phrase": "p",
                 "type": "state", "what_to_show": "w",
                 "best_visual_timestamp": NSNull(), "guide_text": "g", "importance": 0.5],
            ],
        ]
        let (analysis, raw) = try AnalysisNormalizer.normalized(
            rawObject: rawObject, duration: 90, profile: "generic", language: "ko")
        #expect(analysis.steps[0].tStart == 5 && analysis.steps[0].tEnd == 20)
        #expect(analysis.visualGuides[0].bestVisualTimestamp == 12)
        #expect(analysis.visualGuides[1].bestVisualTimestamp == nil)
        #expect(analysis.duration == 90 && analysis.profile == "generic")
        let rawDict = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        #expect(rawDict["_output_language"] as? String == "ko")   // 메타 주입 보존
    }
}
```

`Tests/GeminiAPITests.swift`:

```swift
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
        GeminiAPIStub.shared.handler = { _ in
            (200, try! JSONSerialization.data(withJSONObject: envelope))
        }

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
```

- [ ] **Step 4: RED 확인**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/s1.log 2>&1; tail -5 /tmp/s1.log
```

Expected: 컴파일 실패 — `cannot find 'AnalysisNormalizer' in scope`.

- [ ] **Step 5: 구현**

`Sources/Services/AnalysisNormalizer.swift`:

```swift
import Foundation

/// 직접 Gemini 모드의 정규화 — 확장 bg.js normalize와 동일 부분집합(시간 문자열 → 초 Int).
/// 서버 normalize의 보완 로직(source_phrase/importance/type alias)은 미포팅: 구조화 출력
/// 스키마가 필수 필드를 강제하므로 실효가 낮다 (스펙 2.3, 확장과 동일 범위).
enum AnalysisNormalizer {
    /// "M:SS"~"MMM:SS" → 초. 이미 숫자면 그대로, nil/비정상 문자열은 nil.
    static func mmssToSec(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        guard let text = value as? String, !text.isEmpty else { return nil }
        var seconds = 0
        for part in text.split(separator: ":") {
            guard let n = Int(part) else { return nil }
            seconds = seconds * 60 + n
        }
        return seconds
    }

    /// dict 레벨 정규화 + 메타 주입 → 타입 모델과 원본 직렬화를 함께 반환
    static func normalized(rawObject: [String: Any], duration: Int, profile: String,
                           language: String) throws -> (analysis: Analysis, rawAnalysis: Data) {
        var object = rawObject
        if var steps = object["steps"] as? [[String: Any]] {
            for index in steps.indices {
                steps[index]["t_start"] = mmssToSec(steps[index]["t_start"]) ?? 0
                steps[index]["t_end"] = mmssToSec(steps[index]["t_end"]) ?? 0
            }
            object["steps"] = steps
        }
        if var guides = object["visual_guides"] as? [[String: Any]] {
            for index in guides.indices {
                guides[index]["best_visual_timestamp"] =
                    mmssToSec(guides[index]["best_visual_timestamp"]) ?? NSNull()
            }
            object["visual_guides"] = guides
        }
        object["_duration"] = duration
        object["_profile"] = profile
        object["_output_language"] = language
        let raw = try JSONSerialization.data(withJSONObject: object)
        let analysis = try JSONDecoder().decode(Analysis.self, from: raw)
        return (analysis, raw)
    }
}
```

`Sources/Services/GeminiAPI.swift`:

```swift
import Foundation

/// 직접 Gemini 분석 (BYOK, 서버 없이) — 확장 bg.js analyzeDirect 포팅.
/// 키는 x-goog-api-key 헤더 세팅 외 어디에도 쓰지 않는다.
final class GeminiAPI: Sendable {
    static let model = "gemini-flash-lite-latest"   // v1 결정: 설정 비노출
    private static let base = "https://generativelanguage.googleapis.com/v1beta/models"
    private let session: URLSession
    private let assets: Bundle

    init(session: URLSession = .shared, assets: Bundle = .main) {
        self.session = session
        self.assets = assets
    }

    struct AssetMissing: Error { let name: String }

    private func asset(_ name: String, ext: String, subdirectory: String) throws -> String {
        guard let url = assets.url(forResource: name, withExtension: ext,
                                   subdirectory: subdirectory) else {
            throw AssetMissing(name: "\(subdirectory)/\(name).\(ext)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// bg.js buildPrompt와 동일 치환 (전체 치환)
    func buildPrompt(profile: String, duration: Int, language: String,
                     maxGuides: Int) throws -> String {
        let rules = try asset("rules", ext: "md", subdirectory: "skill-core/engine")
        let prompt = try asset("prompt", ext: "md", subdirectory: "skill-core/\(profile)")
        return prompt
            .replacingOccurrences(of: "{{RULES}}", with: rules)
            .replacingOccurrences(of: "{DURATION}", with: MarkdownBuilder.hms(duration))
            .replacingOccurrences(of: "{OUTPUT_LANGUAGE}", with: language)
            .replacingOccurrences(of: "{MAX_VISUAL_GUIDES}", with: String(maxGuides))
    }

    /// bg.js loadSchema와 동일 — 메타 키 제거
    func loadSchema(profile: String) throws -> [String: Any] {
        let text = try asset("schema", ext: "json", subdirectory: "skill-core/\(profile)")
        guard var schema = try JSONSerialization.jsonObject(with: Data(text.utf8))
            as? [String: Any] else {
            throw AssetMissing(name: "skill-core/\(profile)/schema.json (파싱 실패)")
        }
        schema.removeValue(forKey: "$schema")
        schema.removeValue(forKey: "$comment")
        schema.removeValue(forKey: "title")
        return schema
    }

    func analyze(videoURL: String, profile: String, language: String,
                 maxGuides: Int = Settings.maxGuides, duration: Int,
                 geminiKey: String) async throws -> AnalyzeResult {
        let prompt = try buildPrompt(profile: profile, duration: duration,
                                     language: language, maxGuides: maxGuides)
        let schema = try loadSchema(profile: profile)
        var request = URLRequest(
            url: URL(string: "\(Self.base)/\(Self.model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(geminiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "contents": [["parts": [
                ["file_data": ["file_uri": videoURL]],
                ["text": prompt],
            ]]],
            "generationConfig": [
                "response_mime_type": "application/json",
                "response_json_schema": schema,
                "temperature": 0.2,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StepkeeperAPIError.network(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw StepkeeperAPIError.invalidResponse
        }
        if http.statusCode == 429 { throw StepkeeperAPIError.rateLimited }
        guard (200...299).contains(http.statusCode) else {
            throw StepkeeperAPIError.modelFailure("Gemini 오류 (HTTP \(http.statusCode))")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let rawObject = try? JSONSerialization.jsonObject(with: Data(text.utf8))
                  as? [String: Any],
              let videoId = YouTubeURL.videoID(from: videoURL)
        else { throw StepkeeperAPIError.invalidResponse }

        let (analysis, raw) = try AnalysisNormalizer.normalized(
            rawObject: rawObject, duration: duration, profile: profile, language: language)
        return AnalyzeResult(videoId: videoId, analysis: analysis, rawAnalysis: raw)
    }
}
```

- [ ] **Step 6: GREEN + 커밋**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/s1b.log 2>&1; grep -E "Test run|TEST" /tmp/s1b.log | tail -2
git add scripts Resources Sources Tests stepkeeper-apple.xcodeproj
git commit -m "feat: 직접 Gemini 분석 — 자산 번들·normalize·GeminiAPI"
```

Expected: 61 tests(55+6) 그린 (파라미터화 카운트 관례로 ±는 스위트 로그로 판정).

---

### Task 2: 모드 라우팅 + 설정 문구 + E2E env 주입

**Files:**
- Modify: `Sources/Services/Settings.swift`, `Sources/App/AppModel.swift`, `Sources/Views/SettingsView.swift`, `Sources/ContentView.swift`, `scripts/e2e-m1.sh`, `scripts/e2e-m2.sh`, `Tests/SettingsTests.swift`, `Tests/AppModelTests.swift`

**Interfaces:**
- Consumes: `GeminiAPI`(T1)
- Produces: `Settings.defaultServerURL == ""`, `AppModel` init에 `makeGeminiAPI: () -> GeminiAPI = { GeminiAPI() }` 파라미터, performAnalysis의 빈 URL→직접 모드 라우팅. T3가 이 라우팅 기준을 신고에도 재사용.

- [ ] **Step 1: 테스트 조정+추가 (RED)**

`Tests/SettingsTests.swift`의 serverURL 단언을 교체:

```swift
        #expect(suite.string(forKey: Settings.serverURLKey) == "")   // v1.3: 직접 모드 기본
```

`Tests/AppModelTests.swift`:
- `makeModel`에서 `Settings.registerDefaults(defaults)` 다음 줄에 추가(기존 서버 경로 테스트 유지용):

```swift
        defaults.set("http://stub.local:8787", forKey: Settings.serverURLKey)
```

- `makeModel` 시그니처를 `makeModel(root: URL, linkMode: Bool = false, serverURL: String? = "http://stub.local:8787")`로 바꾸고 위 줄을 `if let serverURL { defaults.set(serverURL, forKey: Settings.serverURLKey) } else { defaults.set("", forKey: Settings.serverURLKey) }`로. `makeGeminiAPI` 주입을 위해 AppModel 생성부를:

```swift
        return AppModel(
            keychain: keychain,
            documentStore: DocumentStore(root: root),
            defaults: defaults,
            makeAPI: { StepkeeperAPI(baseURL: $0, session: session) },
            makeGeminiAPI: { GeminiAPI(session: session) })
```

- 라우팅 테스트 추가:

```swift
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
        StubURLProtocol.handler = { request in
            // 직접 모드 증명: 요청이 Gemini 호스트로 가야 한다
            #expect(request.url?.host == "generativelanguage.googleapis.com")
            return (200, try! JSONSerialization.data(withJSONObject: envelope))
        }
        defer { StubURLProtocol.handler = nil }

        await model.performAnalysis(videoId: "dQw4w9WgXcQ", duration: 90)

        guard case .done = model.stage else { Issue.record("stage=\(model.stage)"); return }
    }
```

주의: AppModelTests의 스텁은 `StubURLProtocol`이 아니라 **`AppModelStub`**이다(스위트별 분리) — 위 코드의 `StubURLProtocol`을 실제 파일의 스텁 타입명(`AppModelStub.shared.handler` 패턴)에 맞춰 조정하라. 호스트 단언은 캡처 후 테스트 본문에서 하는 기존 관례(`AppModelStub.shared.capturedRequest`)를 따른다 (핸들러 내 #expect 금지 — v1 교훈).

- [ ] **Step 2: RED 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/s2.log 2>&1; tail -5 /tmp/s2.log
```

Expected: 컴파일 실패 — AppModel에 `makeGeminiAPI` 파라미터 없음.

- [ ] **Step 3: 구현**

`Sources/Services/Settings.swift`: `defaultServerURL`을 `""`로 변경, 주석 갱신:

```swift
    /// v1.3: 빈 값 = 서버 없이 Gemini 직접 호출(일반 사용자 기본). 개발 서버는 URL 입력.
    static let defaultServerURL = ""
```

`Sources/App/AppModel.swift`:
- 프로퍼티·init에 추가: `private let makeGeminiAPI: () -> GeminiAPI`, init 파라미터 `makeGeminiAPI: @escaping () -> GeminiAPI = { GeminiAPI() }`, 본문 `self.makeGeminiAPI = makeGeminiAPI`.
- `performAnalysis`의 serverURL guard와 analyze 호출부를 교체:

```swift
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
                    stage = .failed("서버 URL이 올바르지 않습니다 — 설정을 확인하세요")
                    return
                }
                result = try await makeAPI(serverURL).analyze(
                    videoURL: videoURL, profile: profile, language: language,
                    duration: duration, geminiKey: key)
            }
            guard gen == generation else { return }   // 취소됨
```

(기존 guard let serverURL 블록과 `let gen`~analyze 호출은 이 구조로 대체 — 이후의 linkMode 분기·catch는 기존 유지.)

`Sources/Views/SettingsView.swift` 서버 섹션 footer 교체:

```swift
                } header: { Text("stepkeeper 서버 (선택)") } footer: {
                    Text("비워두면 서버 없이 Gemini를 직접 호출합니다(기본). 개발용 서버를 쓰려면 URL 입력 — 실기기에서는 Mac의 LAN IP (예: http://192.168.0.10:8787)")
                }
```

`Sources/ContentView.swift` DEBUG 훅의 키 시드 줄 앞에 추가:

```swift
                if let server = ProcessInfo.processInfo.environment["STEPKEEPER_SERVER_URL"] {
                    UserDefaults.standard.set(server, forKey: Settings.serverURLKey)
                }
```

`scripts/e2e-m1.sh`·`e2e-m2.sh`의 launch 줄에 env 추가 (두 파일 모두, 기존 SIMCTL_CHILD_* 나열에):

```bash
SIMCTL_CHILD_STEPKEEPER_SERVER_URL="http://127.0.0.1:8787" \
```

- [ ] **Step 4: GREEN + E2E + 커밋**

```bash
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/s2b.log 2>&1; grep -E "Test run|TEST" /tmp/s2b.log | tail -2
./scripts/e2e-m1.sh && ./scripts/e2e-m2.sh
git add Sources Tests scripts stepkeeper-apple.xcodeproj
git commit -m "feat: 서버 URL 비면 직접 Gemini 모드 (v1.3 기본) + E2E env 주입"
```

Expected: 전체 그린 + 두 E2E PASS (env 주입으로 스텁 서버 경로 유지 증명).

---

### Task 3: 신고 수집기 분리

**Files:**
- Create: `Sources/Models/ReportCollector.swift`, `Tests/ReportCollectorTests.swift`
- Modify: `Sources/Services/Settings.swift`, `Sources/App/AppModel.swift`(submitIssueReport), `Sources/Views/DocumentView.swift`(submitReport+pre-check), `Sources/Views/CandidatePickerView.swift`(pre-check), `Sources/Views/SettingsView.swift`(신고 필드)

**Interfaces:**
- Produces: `Settings.reportServerURLKey`(= "reportServerURL"), `ReportCollector.defaultURL`(현재 "" — 배포 후 호스팅 주소 교체 단일 지점), `ReportCollector.resolveURL(defaults:) -> URL?`(신고 URL > 서버 URL > nil).

- [ ] **Step 1: 실패하는 테스트**

`Tests/ReportCollectorTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct ReportCollectorTests {
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "stepkeeper.tests.collector")!
        suite.removePersistentDomain(forName: "stepkeeper.tests.collector")
        return suite
    }

    @Test func prefersReportURLThenServerThenNil() {
        let defaults = makeDefaults()
        #expect(ReportCollector.resolveURL(defaults: defaults) == nil)   // 둘 다 없음

        defaults.set("http://127.0.0.1:8787", forKey: Settings.serverURLKey)
        #expect(ReportCollector.resolveURL(defaults: defaults)?.absoluteString
                == "http://127.0.0.1:8787")                              // 서버 폴백

        defaults.set("https://collector.example.com", forKey: Settings.reportServerURLKey)
        #expect(ReportCollector.resolveURL(defaults: defaults)?.absoluteString
                == "https://collector.example.com")                       // 신고 URL 우선
    }

    @Test func ignoresWhitespaceOnlyValues() {
        let defaults = makeDefaults()
        defaults.set("   \n", forKey: Settings.reportServerURLKey)
        defaults.set("  ", forKey: Settings.serverURLKey)
        #expect(ReportCollector.resolveURL(defaults: defaults) == nil)
    }
}
```

- [ ] **Step 2: RED 확인** (`cannot find 'ReportCollector'`) — 커맨드는 T1 Step 4와 동일 패턴.

- [ ] **Step 3: 구현**

`Sources/Models/ReportCollector.swift`:

```swift
import Foundation

/// 신고 전송 대상 결정 — 일반 사용자는 배포판에 내장된 수집기 주소(defaultURL)로,
/// 개발자는 설정의 신고 URL 또는 분석 서버로 보낸다.
enum ReportCollector {
    /// 배포 후 호스팅 수집기 주소로 교체하는 단일 지점 (예: "https://stepkeeper-reports-xxxx.run.app").
    /// 비어 있는 동안에는 설정의 신고 URL → 분석 서버 URL 순으로 폴백한다.
    static let defaultURL = ""

    static func resolveURL(defaults: UserDefaults = .standard) -> URL? {
        let candidates = [
            defaults.string(forKey: Settings.reportServerURLKey) ?? "",
            Self.defaultURL,
            defaults.string(forKey: Settings.serverURLKey) ?? "",
        ]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) { return url }
        }
        return nil
    }
}
```

`Sources/Services/Settings.swift` 키 상수에 추가:

```swift
    static let reportServerURLKey = "reportServerURL"
```

`Sources/App/AppModel.swift` `submitIssueReport`의 serverURL guard를 교체:

```swift
        guard let serverURL = ReportCollector.resolveURL(defaults: defaults) else {
            return "신고 수집 서버가 설정되지 않았습니다 — 설정에서 입력하거나 앱 업데이트를 기다려 주세요"
        }
```

(이후 `makeAPI(serverURL).submitReport(report)` 호출은 기존 그대로.)

`Sources/Views/DocumentView.swift` `submitReport`의 serverURL guard를 교체:

```swift
        guard let serverURL = ReportCollector.resolveURL() else {
            return "신고 수집 서버가 설정되지 않았습니다 — 설정에서 입력하거나 앱 업데이트를 기다려 주세요"
        }
```

**pre-check (스펙 3절 — 시트 열기 전 안내, 전송 시도 없음)**: DocumentView의 신고 버튼 액션을:

```swift
                Button {
                    if ReportCollector.resolveURL() == nil {
                        exportMessage = "신고 수집 서버가 설정되지 않았습니다 — 설정에서 입력하거나 앱 업데이트를 기다려 주세요"
                    } else {
                        reporting = true
                    }
                } label: {
                    Label("문서가 이상해요", systemImage: "flag")
                }
```

CandidatePickerView의 신고 버튼도 동일 패턴 (안내는 픽커에 별도 메시지 상태가 없으므로 `@State private var reportNotice: String?` 추가 후 버튼 아래 표시):

```swift
                Button {
                    if ReportCollector.resolveURL() == nil {
                        reportNotice = "신고 수집 서버가 설정되지 않았습니다 — 설정에서 입력하거나 앱 업데이트를 기다려 주세요"
                    } else {
                        reportNotice = nil
                        reporting = true
                    }
                } label: {
                    Label("후보가 이상해요", systemImage: "flag")
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
                if let reportNotice {
                    Text(reportNotice).font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                }
```

`Sources/Views/SettingsView.swift` — 서버 섹션 아래(Notion 섹션 위)에 추가:

```swift
                Section {
                    TextField("신고 수집 서버 URL", text: $reportServerURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } header: { Text("이상 신고 (선택)") } footer: {
                    Text("비워두면 분석 서버로 보냅니다. 일반 배포판에는 기본 수집기가 내장됩니다.")
                }
```

`@AppStorage` 추가: `@AppStorage(Settings.reportServerURLKey) private var reportServerURL = ""`

- [ ] **Step 4: GREEN + 커밋**

```bash
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/s3.log 2>&1; grep -E "Test run|TEST" /tmp/s3.log | tail -2
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build > /tmp/s3b.log 2>&1; tail -1 /tmp/s3b.log
git add Sources Tests stepkeeper-apple.xcodeproj
git commit -m "feat: 신고 수집기 URL 분리 — 배포 기본값 단일 지점 + 미설정 안내"
```

---

### Task 4: 서버 토큰 브리지 + 배포 가이드 (Work from: /Users/choejunhwan/dev/stepkeeper-server)

**Files:**
- Modify: `app.py`(`_create_github_issue` 토큰 경로), `tests/test_reports.py`(토큰 케이스), `README.md`(브리지 문단 갱신)
- Create: `docs/deploy.md`

**Interfaces:**
- Produces: `GITHUB_TOKEN` env 있으면 urllib로 GitHub API 직접(gh CLI 불필요 — Cloud Run 대응), 우선순위 토큰 > gh > skipped.

- [ ] **Step 1: 실패하는 테스트 추가** (tests/test_reports.py, 기존 스타일·mock.patch)

```python
    def test_token_path_posts_via_urllib(self):
        os.environ["STEPKEEPER_REPORTS_REPO"] = "zlej123/stepkeeper-reports"
        os.environ["GITHUB_TOKEN"] = "test-token"
        try:
            captured = {}

            class FakeResponse:
                status = 201
                def __enter__(self):
                    return self
                def __exit__(self, *args):
                    return False

            def fake_urlopen(request, timeout=None):
                captured["url"] = request.full_url
                captured["auth"] = request.get_header("Authorization")
                captured["payload"] = json.loads(request.data.decode())
                return FakeResponse()

            with unittest.mock.patch("app.urllib.request.urlopen", side_effect=fake_urlopen), \
                 unittest.mock.patch("app.subprocess.run") as fake_run:
                response = self.client.post("/v1/reports", json=make_payload())
            self.assertEqual(200, response.status_code)
            self.assertEqual("ok", response.json()["github"])
            self.assertEqual(
                "https://api.github.com/repos/zlej123/stepkeeper-reports/issues",
                captured["url"])
            self.assertEqual("Bearer test-token", captured["auth"])
            self.assertTrue(captured["payload"]["title"].startswith("[report:candidates]"))
            fake_run.assert_not_called()   # 토큰이 gh보다 우선
        finally:
            os.environ.pop("STEPKEEPER_REPORTS_REPO", None)
            os.environ.pop("GITHUB_TOKEN", None)

    def test_token_path_failure_still_ok(self):
        os.environ["STEPKEEPER_REPORTS_REPO"] = "zlej123/stepkeeper-reports"
        os.environ["GITHUB_TOKEN"] = "test-token"
        try:
            with unittest.mock.patch(
                    "app.urllib.request.urlopen",
                    side_effect=OSError("boom")):
                response = self.client.post("/v1/reports", json=make_payload())
            self.assertEqual(200, response.status_code)
            self.assertEqual("failed", response.json()["github"])
        finally:
            os.environ.pop("STEPKEEPER_REPORTS_REPO", None)
            os.environ.pop("GITHUB_TOKEN", None)
```

(파일 상단 import에 `import unittest.mock`가 없으면 추가. 기존 gh 테스트들이 `GITHUB_TOKEN` 미설정 전제로 통과하는지 확인 — setUp에서 `os.environ.pop("GITHUB_TOKEN", None)` 방어 추가.)

- [ ] **Step 2: RED 확인** — `.venv/bin/python -m unittest tests.test_reports -v 2>&1 | tail -5` (urlopen 미사용이라 fake 미호출 → 단언 실패 또는 github=="ok"가 gh 경로 결과와 불일치)

- [ ] **Step 3: 구현** — app.py에 `import urllib.request` 추가, `_create_github_issue`를 교체:

```python
def _post_issue_with_token(repo: str, token: str, payload: dict) -> str:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/issues",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        },
        method="POST")
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return "ok" if 200 <= response.status < 300 else "failed"
    except Exception:
        return "failed"


def _create_github_issue(entry: dict) -> str:
    """Optional bridge after the JSONL write — never fails the report.

    Prefers GITHUB_TOKEN (works on hosted deploys without gh CLI), falls back
    to the local `gh` CLI, else "skipped". Opt-in via STEPKEEPER_REPORTS_REPO.
    Returns "ok" | "skipped" | "failed".
    """
    repo = os.environ.get("STEPKEEPER_REPORTS_REPO")
    if not repo:
        return "skipped"
    payload = _github_issue_payload(entry)
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return _post_issue_with_token(repo, token, payload)
    try:
        result = subprocess.run(
            ["gh", "api", f"repos/{repo}/issues", "--input", "-"],
            input=json.dumps(payload).encode(),
            capture_output=True, timeout=15)
        return "ok" if result.returncode == 0 else "failed"
    except (OSError, subprocess.TimeoutExpired):
        return "failed"
```

- [ ] **Step 4: 전체 테스트 + 문서**

`.venv/bin/python -m unittest discover -s tests 2>&1 | tail -3` → 15 tests OK.
README 브리지 문단에 한 줄 추가: "On hosted deploys set `GITHUB_TOKEN` (fine-grained, Issues RW on the reports repo) — takes precedence over the gh CLI."
`docs/deploy.md` 작성:

```markdown
# Deploying the report collector (Cloud Run)

The app's one-tap reports need a hosted collector so end users configure nothing.
This is the same stepkeeper-server — deploy it once, then point the app's
`ReportCollector.defaultURL` at it.

## Deploy

    gcloud run deploy stepkeeper-reports --source . --region asia-northeast3 \
      --allow-unauthenticated \
      --set-env-vars STEPKEEPER_REPORTS_REPO=zlej123/stepkeeper-reports,GITHUB_TOKEN=<fine-grained PAT>

- Token: fine-grained PAT, **Issues Read/Write on the reports repo only**.
- `STEPKEEPER_REPORTS` (JSONL dir) is ephemeral on Cloud Run — GitHub issues are
  the durable record. Mount a bucket later if you want the JSONL corpus too.
- `/v1/analyze`·`/v1/documents` also work on this deployment (BYOK passthrough,
  the server still pays for nothing) — optional for users who prefer server mode.

## After deploying

1. `curl -s https://<service-url>/healthz` → `{"status": "ok", ...}`
2. stepkeeper-apple의 `Sources/Models/ReportCollector.swift` `defaultURL`을
   서비스 URL로 교체하고 릴리스.
```

- [ ] **Step 5: 커밋**

```bash
git add app.py tests/test_reports.py README.md docs/deploy.md
git commit -m "reports: token-based GitHub bridge for hosted deploys + deploy guide"
```

---

### Task 5: 문서 + 전체 회귀 (Work from: /Users/choejunhwan/dev/stepkeeper-apple, 체크포인트)

**Files:**
- Modify: `docs/TESTING.md`, `README.md`

- [ ] **Step 1: TESTING.md** — 체크리스트에 추가(기존 번호 이어서):

```markdown
15. [ ] 직접 모드(기본): 설정의 서버 URL을 비운 상태에서 분석 → 로컬 서버 프로세스 없이 완주 (Gemini 키만 필요)
16. [ ] 신고 미설정 안내: 서버·신고 URL 모두 빈 상태에서 🚩 → "신고 수집 서버가 설정되지 않았습니다" 안내(전송 없음)
```

준비 절의 서버 안내 문구를 갱신: "서버는 선택 사항 — 기본은 직접 모드(키만). 개발·회귀용 스텁/실서버는 기존 명령."

- [ ] **Step 2: README.md** — 개발 절 위에 갱신: 첫 문단의 서버 설명을 "분석은 기본적으로 앱이 Gemini를 직접 호출(BYOK)하며, [stepkeeper-server](https://github.com/zlej123/stepkeeper-server)는 선택(개발·프롬프트 반복·신고 수집기 호스팅)"으로 교체. 스크립트 목록 아래 문서 링크에 `stepkeeper-server/docs/deploy.md`(신고 수집기 배포) 추가.

- [ ] **Step 3: 전체 회귀**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/s5.log 2>&1; grep -E "Test run|TEST" /tmp/s5.log | tail -2
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test > /tmp/s5b.log 2>&1; grep -E "Test run|TEST" /tmp/s5b.log | tail -2
./scripts/e2e-m1.sh && ./scripts/e2e-m2.sh
cd /Users/choejunhwan/dev/stepkeeper-server && .venv/bin/python -m unittest discover -s tests 2>&1 | tail -2
```

Expected: 앱 양 destination 그린 + E2E 2종 PASS + 서버 15 tests OK.

- [ ] **Step 4: 커밋 (체크포인트: 사용자 보고)**

```bash
cd /Users/choejunhwan/dev/stepkeeper-apple
git add docs/TESTING.md README.md
git commit -m "docs: v1.3 서버리스 안내 (직접 모드·신고 수집기)"
```

**사용자 보고**: 직접 모드 수동 확인 안내(서버 URL 비우고 실키 분석 — 서버 꺼도 됨), Cloud Run 배포 가이드 위치.

---

## 순서: T1→T2→T3→T4→T5 직렬. T4만 서버 레포.

