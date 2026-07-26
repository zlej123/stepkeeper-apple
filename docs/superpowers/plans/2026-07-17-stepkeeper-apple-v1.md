# stepkeeper-apple v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 유튜브 how-to 영상 URL → 분석(stepkeeper-server) → 사용자 프레임 선택 → 이미지/링크가 첨부된 마크다운 문서 내보내기까지 되는 SwiftUI 멀티플랫폼 앱(iOS/iPadOS/macOS).

**Architecture:** 서버는 분석만, 캡처는 WKWebView(유튜브 재생 화면 canvas 캡처), 문서 조립은 로컬 Swift(코어의 미니 mustache 렌더러 포팅 + template.md 번들). 스펙: `docs/superpowers/specs/2026-07-17-stepkeeper-apple-v1-design.md` — 이 계획과 충돌 시 스펙이 우선.

**Tech Stack:** Swift 6 / SwiftUI / WKWebView / Swift Testing(`import Testing`) / XcodeGen / 로컬 검증용 Python 스텁 서버(stdlib).

## Global Constraints

- 모든 `xcodebuild`/`xcrun` 앞에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (이 Mac의 xcode-select는 CLT를 가리킴).
- 빌드 대상: iOS 17.0+ / macOS 14.0+, Swift 6(strict concurrency), 단일 멀티플랫폼 타깃 `Stepkeeper` + 테스트 타깃 `StepkeeperTests`.
- `project.yml`이 프로젝트 원본 — 파일/타깃 추가 시 project.yml 수정 후 `xcodegen generate` (xcodegen은 소스 glob이라 Sources/Tests 아래 새 .swift 파일은 regen만 하면 됨).
- 단위 테스트 실행(빠른 기본): `xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test`. 시뮬레이터 검증: `-destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
- 영상 다운로드 절대 금지(App Store 5.2.3). yt-dlp/ffmpeg 사용 금지. 캡처는 플레이어 화면 스틸만.
- 시간 값은 전부 초 단위 `Int` (서버가 정규화해서 반환).
- Gemini 키를 로그·에러 메시지·커밋에 절대 노출하지 않는다. 실키 입력이 필요한 검증은 사용자에게 맡긴다(에이전트가 키를 다루지 않음).
- UI 문구는 한국어(스펙 5·6절의 문구 그대로).
- 커밋은 태스크당 1개 이상, 메시지는 각 태스크의 커밋 스텝 참조.
- 작업 디렉토리: `/Users/choejunhwan/dev/stepkeeper-apple`. 참조 레포: `../stepkeeper`(코어), `../stepkeeper-server`, `../stepkeeper-extension`.

## File Structure (최종 상태)

```
project.yml                          # 타깃·plist·리소스 정의 (Task 2, 5, 13, 14에서 수정)
Sources/
  App/StepkeeperApp.swift              # @main + 스파이크/기본값 부팅 (Task 1, 10)
  App/AppModel.swift                 # @Observable 플로우 상태 머신 (Task 9, 11)
  App/ShareInbox.swift               # App Group 인박스 (Task 13)
  Models/Analysis.swift              # Analysis·Step·VisualGuide·Material Codable (Task 2)
  Models/YouTubeURL.swift            # video_id 파싱 (Task 3)
  Models/CandidateTimes.swift        # 3후보 시각 계산 (Task 3)
  Services/MustacheLite.swift        # 코어 render() 포팅 (Task 4)
  Services/MarkdownBuilder.swift     # buildContext 포팅 + 템플릿 렌더 (Task 5)
  Services/KeychainStore.swift       # Gemini 키 (Task 6)
  Services/Settings.swift            # @AppStorage 키·기본값 (Task 6)
  Services/StepkeeperAPI.swift         # /v1/analyze + 에러 매핑 (Task 7)
  Services/DocumentStore.swift       # 문서 저장/목록/재열람 (Task 8)
  Capture/CaptureScript.swift        # 주입 JS 문자열 (Task 1, 11)
  Capture/PlayerBridge.swift         # WKWebView 브리지 (Task 1, 11)
  Capture/PlayerWebView.swift        # Representable 래퍼 (Task 1)
  Capture/SpikeCaptureView.swift     # DEBUG 전용 M0 하네스 (Task 1)
  Views/HomeView.swift               # URL 입력 + 최근 문서 (Task 10)
  Views/AnalyzeFlowView.swift        # 플레이어 + 진행 단계 (Task 10, 12)
  Views/CandidatePickerView.swift    # 3후보+부적합 선택 (Task 12)
  Views/DocumentView.swift           # 모델 기반 네이티브 렌더 + 내보내기 (Task 10)
  Views/SettingsView.swift           # 키·언어·서버·링크모드 (Task 10)
  Views/Support.swift                # Pasteboard·LocalImage·JPEGImage·ExportHelper (Task 10, 12)
  ContentView.swift                  # 루트 (Task 1 스파이크 링크, Task 10 대체, Task 13 픽업)
  Stepkeeper-iOS.entitlements          # App Group (Task 13)
  Stepkeeper-macOS.entitlements        # 샌드박스 (Task 14)
Resources/skill-core/generic/template.md   # ../stepkeeper에서 복사 (Task 5)
Resources/skill-core/recipe/template.md
ShareExtension/ShareViewController.swift   # (Task 13)
ShareExtension/StepkeeperShare.entitlements  # (Task 13; Info.plist는 project.yml info로 생성)
Tests/
  TestBundle.swift·AnalysisTests.swift (Task 2)
  YouTubeURLTests.swift·CandidateTimesTests.swift (Task 3)
  MustacheLiteTests.swift (Task 4) / MarkdownBuilderGoldenTests.swift (Task 5)
  KeychainStoreTests.swift·SettingsTests.swift (Task 6) / StepkeeperAPITests.swift (Task 7)
  DocumentStoreTests.swift (Task 8) / AppModelTests.swift (Task 9)
  CapturePipelineTests.swift (Task 11) / ShareInboxTests.swift (Task 13)
  Fixtures/analyze-response.json (Task 2)
  Fixtures/golden/<case>/{analysis.json,case.json,expected.md} (Task 5)
scripts/spike-verify.sh              # M0 자동 검증 (Task 1)
scripts/sync-assets.sh               # skill-core 템플릿 재복사 (Task 5)
scripts/make-golden.py               # 코어 render.py로 expected.md 생성 (Task 5)
scripts/stub-server.py               # /v1/analyze 스텁 (Task 9)
scripts/e2e-m1.sh                    # M1 링크모드 E2E (Task 10)
scripts/e2e-m2.sh                    # M2 캡처 E2E (Task 12)
docs/spike-capture.md                # M0 결과 기록 (Task 1)
docs/TESTING.md                      # 수동 E2E 체크리스트 (Task 14)
README.md                            # (Task 14)
```

**마일스톤 체크포인트** (완료 시 사용자에게 보고): Task 1(M0 스파이크 성패), Task 10(M1 링크모드 E2E), Task 12(M2 캡처 E2E), Task 14(M4 완료).

---

### Task 1: M0 캡처 스파이크 — WKWebView 유튜브 프레임 캡처 검증

최대 리스크(WebKit에서 seek+canvas 캡처 가능 여부)를 코드 4파일 + 자동 검증으로 판정한다. 성공 기준: iOS 시뮬레이터와 macOS 각각에서 고정 영상(`4ioPBiTWm3M`)의 t=10/30/60s JPEG 3장이 저장되고, 각 프레임 휘도 표준편차 > 8 (순흑/단색 아님).

**Files:**
- Create: `Sources/Capture/CaptureScript.swift`, `Sources/Capture/PlayerBridge.swift`, `Sources/Capture/PlayerWebView.swift`, `Sources/Capture/SpikeCaptureView.swift`, `scripts/spike-verify.sh`, `docs/spike-capture.md`
- Modify: `Sources/ContentView.swift` (DEBUG에서 스파이크 진입 버튼)

**Interfaces:**
- Produces: `PlayerBridge`(@MainActor, ObservableObject) — `load(videoID:)`, `waitForMetadata(timeout:) async throws -> (duration: Int, title: String)`, `captureFrame(at:) async throws -> Data`, `beginCaptureSession()/endCaptureSession()`은 Task 10에서 추가. `PlayerError` enum. Task 8·10이 이 시그니처를 그대로 사용.
- 주입 JS 전역: `window.__stepkeeper.waitMeta(timeoutMs)`, `window.__stepkeeper.capture(t, timeoutMs)` — dataURL 문자열 반환.

- [ ] **Step 1: capture.js를 Swift 상수로 작성**

`Sources/Capture/CaptureScript.swift`:

```swift
// 유튜브 페이지에 주입하는 캡처 스크립트. video 엘리먼트에만 의존한다(DOM 구조 독립).
enum CaptureScript {
    static let source = #"""
    (() => {
      if (window.__stepkeeper) return;
      const video = () => document.querySelector("video");
      const sleep = (ms) => new Promise(r => setTimeout(r, ms));
      async function waitMeta(timeoutMs) {
        const t0 = Date.now();
        while (Date.now() - t0 < timeoutMs) {
          const v = video();
          if (v && v.readyState >= 1 && isFinite(v.duration) && v.duration > 0) {
            return { duration: Math.floor(v.duration), title: document.title };
          }
          await sleep(200);
        }
        throw new Error("metadata timeout");
      }
      function seek(v, t, timeoutMs) {
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => { v.removeEventListener("seeked", done); reject(new Error("seek timeout " + t)); }, timeoutMs);
          const done = () => { clearTimeout(timer); v.removeEventListener("seeked", done); resolve(); };
          v.addEventListener("seeked", done);
          v.currentTime = t;
        });
      }
      async function capture(t, timeoutMs) {
        const v = video();
        if (!v || !v.videoWidth) throw new Error("no player");
        await seek(v, t, timeoutMs);
        await sleep(150); // 렌더 안정화 (content.js와 동일)
        const c = document.createElement("canvas");
        c.width = v.videoWidth; c.height = v.videoHeight;
        c.getContext("2d").drawImage(v, 0, 0);
        return c.toDataURL("image/jpeg", 0.85);
      }
      async function prime() { // muted 재생으로 프레임 디코딩 유도 후 정지
        const v = video();
        if (!v) throw new Error("no player");
        v.muted = true;
        try { await v.play(); } catch (e) {}
        await sleep(500);
        v.pause();
        return true;
      }
      window.__stepkeeper = { waitMeta, capture, prime };
    })();
    """#
}
```

- [ ] **Step 2: PlayerBridge 작성**

`Sources/Capture/PlayerBridge.swift`:

```swift
import WebKit

enum PlayerError: Error, LocalizedError, Equatable {
    case loadFailed(String), metadataTimeout, seekTimeout(Int), captureFailed(String), emptyFrame
    var errorDescription: String? {
        switch self {
        case .loadFailed(let m): return "플레이어 로드 실패: \(m)"
        case .metadataTimeout: return "영상 정보를 가져오지 못했습니다"
        case .seekTimeout(let t): return "장면 이동 시간 초과 (\(t)s)"
        case .captureFailed(let m): return "캡처 실패: \(m)"
        case .emptyFrame: return "빈 프레임"
        }
    }
}

@MainActor
final class PlayerBridge: NSObject, ObservableObject {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(
            source: CaptureScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
    }

    func load(videoID: String) {
        // 스펙 4.4-8: 두 플랫폼 모두 m.youtube.com (macOS 문제 시 www + 데스크톱 UA로 전환하고 spike-capture.md에 기록)
        let url = URL(string: "https://m.youtube.com/watch?v=\(videoID)")!
        webView.load(URLRequest(url: url))
    }

    private func callJS(_ body: String, timeout: TimeInterval) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            body, arguments: [:], in: nil, contentWorld: .page)
    }

    func waitForMetadata(timeout: TimeInterval = 20) async throws -> (duration: Int, title: String) {
        let result = try await callJS(
            "return await window.__stepkeeper.waitMeta(\(Int(timeout * 1000)));", timeout: timeout)
        guard let dict = result as? [String: Any],
              let duration = dict["duration"] as? Int,
              let title = dict["title"] as? String, duration > 0 else {
            throw PlayerError.metadataTimeout
        }
        return (duration, title)
    }

    func primePlayer() async throws {
        _ = try await callJS("return await window.__stepkeeper.prime();", timeout: 5)
    }

    func captureFrame(at seconds: Int) async throws -> Data {
        let result: Any?
        do {
            result = try await callJS(
                "return await window.__stepkeeper.capture(\(seconds), 8000);", timeout: 10)
        } catch {
            throw PlayerError.captureFailed(String(describing: error))
        }
        guard let dataURL = result as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              !data.isEmpty else {
            throw PlayerError.emptyFrame
        }
        return data
    }
}
```

- [ ] **Step 3: PlayerWebView (Representable) 작성**

`Sources/Capture/PlayerWebView.swift`:

```swift
import SwiftUI
import WebKit

#if os(macOS)
struct PlayerWebView: NSViewRepresentable {
    let bridge: PlayerBridge
    func makeNSView(context: Context) -> WKWebView { bridge.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
struct PlayerWebView: UIViewRepresentable {
    let bridge: PlayerBridge
    func makeUIView(context: Context) -> WKWebView { bridge.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
```

- [ ] **Step 4: 스파이크 하네스 뷰 작성**

`Sources/Capture/SpikeCaptureView.swift` — 실행하면 자동으로 캡처를 수행하고 결과를 `Documents/spike/`에 저장(`result.json` + `frame-<t>.jpg`), 화면에도 표시:

```swift
#if DEBUG
import SwiftUI
import CoreGraphics
import ImageIO

struct SpikeResult: Codable {
    struct Frame: Codable { var t: Int; var bytes: Int; var luminanceStdDev: Double; var ok: Bool }
    var platform: String
    var videoID: String
    var duration: Int
    var title: String
    var frames: [Frame]
    var ok: Bool
}

@MainActor
final class SpikeRunner: ObservableObject {
    @Published var status = "대기"
    @Published var images: [CGImage] = []
    let bridge = PlayerBridge()
    static let videoID = "4ioPBiTWm3M"  // 코어 README 데모 영상
    static let times = [10, 30, 60]

    func run() async {
        do {
            status = "플레이어 로드 중"
            bridge.load(videoID: Self.videoID)
            try await Task.sleep(for: .seconds(3))
            let meta = try await bridge.waitForMetadata()
            status = "메타데이터: \(meta.duration)s — 프레임 디코딩 유도"
            try await bridge.primePlayer()
            var frames: [SpikeResult.Frame] = []
            for t in Self.times {
                status = "캡처 중 t=\(t)s"
                let data = try await bridge.captureFrame(at: t)
                let std = Self.luminanceStdDev(jpeg: data) ?? 0
                frames.append(.init(t: t, bytes: data.count, luminanceStdDev: std, ok: std > 8))
                if let img = Self.cgImage(jpeg: data) { images.append(img) }
                try Self.write(data, name: "frame-\(t).jpg")
            }
            let result = SpikeResult(
                platform: Self.platformName, videoID: Self.videoID,
                duration: meta.duration, title: meta.title,
                frames: frames, ok: frames.allSatisfy(\.ok) && frames.count == Self.times.count)
            let json = try JSONEncoder().encode(result)
            try Self.write(json, name: "result.json")
            status = result.ok ? "성공 — result.json 저장됨" : "실패 — 프레임 검증 미달"
        } catch {
            status = "실패: \(error.localizedDescription)"
            if let json = try? JSONEncoder().encode(
                ["error": String(describing: error), "platform": Self.platformName]) {
                try? Self.write(json, name: "result.json")
            }
        }
    }

    static var platformName: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }

    static func spikeDir() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("spike", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(_ data: Data, name: String) throws {
        try data.write(to: spikeDir().appendingPathComponent(name))
    }

    static func cgImage(jpeg: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// 8x8로 다운샘플한 그레이스케일 휘도의 표준편차 — 순흑/단색 프레임 판별
    static func luminanceStdDev(jpeg: Data) -> Double? {
        guard let image = cgImage(jpeg: jpeg) else { return nil }
        let w = 8, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let values = pixels.map(Double.init)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return variance.squareRoot()
    }
}

struct SpikeCaptureView: View {
    @StateObject private var runner = SpikeRunner()
    var body: some View {
        VStack(spacing: 12) {
            Text("M0 캡처 스파이크").font(.headline)
            Text(runner.status).font(.callout).foregroundStyle(.secondary)
            PlayerWebView(bridge: runner.bridge).frame(minHeight: 220)
            HStack {
                ForEach(Array(runner.images.enumerated()), id: \.offset) { _, img in
                    Image(img, scale: 1, label: Text("frame"))
                        .resizable().scaledToFit().frame(height: 70)
                }
            }
        }
        .padding()
        .task {
            if ProcessInfo.processInfo.environment["STEPKEEPER_SPIKE"] == "1" { await runner.run() }
        }
        .toolbar { Button("실행") { Task { await runner.run() } } }
    }
}
#endif
```

- [ ] **Step 5: ContentView에 DEBUG 진입점 추가**

`Sources/ContentView.swift`의 `VStack` 마지막(`.padding()` 앞)에 추가:

```swift
            #if DEBUG
            NavigationLink("M0 캡처 스파이크") { SpikeCaptureView() }
            #endif
```

그리고 `body` 전체를 `NavigationStack { ... }`으로 감싼다:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.image")
                    .font(.system(size: 44))
                Text("stepkeeper")
                    .font(.largeTitle.bold())
                Text("영상을 문서로. 애매한 순간은 실제 화면으로.")
                    .foregroundStyle(.secondary)
                #if DEBUG
                NavigationLink("M0 캡처 스파이크") { SpikeCaptureView() }
                #endif
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 6: 빌드 확인 (양 플랫폼)**

```bash
cd /Users/choejunhwan/dev/stepkeeper-apple
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```

Expected: 둘 다 `BUILD SUCCEEDED`. (경고는 허용, 에러 0)

- [ ] **Step 7: 검증 스크립트 작성**

`scripts/spike-verify.sh`:

```bash
#!/bin/bash
# M0 스파이크: 시뮬레이터에서 앱을 실행해 캡처를 수행하고 result.json을 판정한다.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
SIM="iPhone 17 Pro"
BUNDLE=com.stepkeeper.app

xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build | tail -2
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/stepkeeper.app
xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null || true
SIMCTL_CHILD_STEPKEEPER_SPIKE=1 xcrun simctl launch "$SIM" $BUNDLE

# 스파이크 하네스는 홈 화면에서 진입해야 하므로 UI 없이는 자동 진입이 안 된다 →
# 앱 시작 시 STEPKEEPER_SPIKE=1이면 스파이크 뷰를 루트로 띄우는 분기가 StepkeeperApp에 필요(Step 8).
CONTAINER=$(xcrun simctl get_app_container "$SIM" $BUNDLE data)
RESULT="$CONTAINER/Documents/spike/result.json"
echo "waiting for $RESULT"
for i in $(seq 1 60); do
  [ -f "$RESULT" ] && break
  sleep 2
done
[ -f "$RESULT" ] || { echo "SPIKE FAIL: result.json not produced"; exit 1; }
cat "$RESULT"
python3 - "$RESULT" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
assert r.get("ok"), f"spike not ok: {r}"
print("SPIKE PASS (iOS simulator)")
EOF
```

`chmod +x scripts/spike-verify.sh`

- [ ] **Step 8: 스파이크 자동 진입 분기**

`Sources/App/StepkeeperApp.swift` — 기존 `Sources/StepkeeperApp.swift`를 `Sources/App/`으로 이동하고 내용 교체:

```swift
import SwiftUI

@main
struct StepkeeperApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["STEPKEEPER_SPIKE"] == "1" {
                SpikeCaptureView()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
```

```bash
mkdir -p Sources/App && git mv Sources/StepkeeperApp.swift Sources/App/StepkeeperApp.swift
# 내용을 위 코드로 교체 후
xcodegen generate
```

- [ ] **Step 9: iOS 시뮬레이터 스파이크 실행·판정**

```bash
./scripts/spike-verify.sh
```

Expected: `SPIKE PASS (iOS simulator)` + result.json에 frames 3개, 각 `ok: true`.
실패 시(메타데이터 타임아웃/빈 프레임/휘도 미달): result.json과 에러를 `docs/spike-capture.md`에 기록하고 **여기서 중단, 사용자 보고** — 스펙 9절 M0 실패 경로(embed 대안 → 링크 모드 온리 조정)를 따른다. 흔한 원인과 1차 대응: 동의 팝업/봇 감지 → WKWebView에서 유튜브 첫 로드 시 쿠키 배너가 뜨면 JS로 닫기 시도(관찰 후 결정), 자동재생 거부 → `prime()`의 play() 예외 무시 후에도 readyState 정체면 `v.load()` 호출 추가 시도.

- [ ] **Step 10: macOS 스파이크 실행·판정**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' -derivedDataPath build build | tail -2
STEPKEEPER_SPIKE=1 ./build/Build/Products/Debug/stepkeeper.app/Contents/MacOS/stepkeeper &
APP_PID=$!
sleep 45 && kill $APP_PID 2>/dev/null || true
RESULT=$(ls ~/Library/Containers/com.stepkeeper.app/Data/Documents/spike/result.json 2>/dev/null \
      || ls ~/Documents/spike/result.json 2>/dev/null)
cat "$RESULT" && python3 -c "import json,sys; r=json.load(open('$RESULT')); assert r['ok'], r; print('SPIKE PASS (macOS)')"
```

Expected: `SPIKE PASS (macOS)`. 실패 시 `www.youtube.com` + `webView.customUserAgent`(Safari 데스크톱 UA)로 전환해 재시도, 결과를 기록.

- [ ] **Step 11: 결과 문서화 + 커밋 (체크포인트: 사용자 보고)**

`docs/spike-capture.md`에 기록: 플랫폼별 성패, result.json 요약(bytes·luminanceStdDev), 우회책 적용 여부(m vs www, UA, prime 방식), JS→Swift 전달 방식 판정(callAsyncJavaScript 유지 여부 — 프레임당 소요시간이 2s 넘으면 messageHandler 검토 메모).

```bash
git add Sources scripts docs/spike-capture.md project.yml
git commit -m "feat: M0 캡처 스파이크 — WKWebView 유튜브 프레임 캡처 검증"
```

**사용자에게 M0 결과 보고 후 다음 태스크 진행.**

---

### Task 2: 테스트 타깃 + Analysis 모델

**Files:**
- Modify: `project.yml` (info properties·테스트 타깃·스킴 test)
- Create: `Sources/Models/Analysis.swift`, `Tests/TestBundle.swift`, `Tests/AnalysisTests.swift`, `Tests/Fixtures/analyze-response.json`

**Interfaces:**
- Produces: `Analysis`(`title, summary, category: String?, servings: String?, materials: [Material], steps: [Step], visualGuides: [VisualGuide], duration: Int?, profile: String?, outputLanguage: String?`), `Material(name, amount: String)`, `Step(id: Int, summary, detail: String, tStart, tEnd: Int)`, `VisualGuide(id: String, stepId: Int, sourcePhrase, phrase, type, whatToShow: String, bestVisualTimestamp: Int?, guideText: String, importance: Double)` — 전부 `Codable, Sendable, Equatable`. `Bundle.tests`(테스트 리소스 접근). fixture `analyze-response.json`은 Task 6(API 스텁 응답)·Task 8(스텁 서버 응답)에서도 사용.

- [ ] **Step 1: project.yml 교체**

`project.yml` 전체를 다음으로 교체 (기존 `INFOPLIST_KEY_*`·`GENERATE_INFOPLIST_FILE` 제거, info/테스트 타깃/스킴 test 추가):

```yaml
name: stepkeeper-apple
options:
  bundleIdPrefix: com.stepkeeper
  deploymentTarget:
    iOS: "17.0"
    macOS: "14.0"
  createIntermediateGroups: true
targets:
  Stepkeeper:
    type: application
    supportedDestinations: [iOS, macOS]
    sources:
      - Sources
    info:
      path: Sources/Info.plist
      properties:
        CFBundleDisplayName: stepkeeper
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: true
        UILaunchScreen: {}
        UIFileSharingEnabled: true
        LSSupportsOpeningDocumentsInPlace: true
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.stepkeeper.app
        PRODUCT_NAME: stepkeeper
        CURRENT_PROJECT_VERSION: 1
        MARKETING_VERSION: 0.1.0
        SWIFT_VERSION: "6.0"
        TARGETED_DEVICE_FAMILY: "1,2"
  StepkeeperTests:
    type: bundle.unit-test
    supportedDestinations: [iOS, macOS]
    sources:
      - path: Tests
        excludes:
          - "Fixtures/**"
      - path: Tests/Fixtures
        type: folder
        buildPhase: resources
    dependencies:
      - target: Stepkeeper
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.stepkeeper.tests
        SWIFT_VERSION: "6.0"
        BUNDLE_LOADER: $(TEST_HOST)
        "TEST_HOST[sdk=macosx*]": $(BUILT_PRODUCTS_DIR)/stepkeeper.app/Contents/MacOS/stepkeeper
        "TEST_HOST[sdk=iphonesimulator*]": $(BUILT_PRODUCTS_DIR)/stepkeeper.app/stepkeeper
schemes:
  Stepkeeper:
    build:
      targets:
        Stepkeeper: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - StepkeeperTests
```

주의: `Tests/Fixtures`는 **폴더 레퍼런스(type: folder)** 로 번들에 들어가 디렉토리 구조가 보존된다 — Task 5의 골든 케이스들(`golden/<case>/analysis.json` 3벌)이 같은 파일명이라 평면 복사면 충돌한다. `Sources/Info.plist`는 xcodegen이 생성하므로 커밋에 포함.

- [ ] **Step 2: 테스트 fixture 작성**

`Tests/Fixtures/analyze-response.json` — 서버 `/v1/analyze` 응답 형태(정규화 후: 시간은 초 Int). vg-2는 timestamp null 케이스:

```json
{
  "video_id": "dQw4w9WgXcQ",
  "analysis": {
    "title": "테스트 하우투 영상",
    "summary": "요약 문장.",
    "category": "생활",
    "materials": [
      {"name": "글루건", "amount": "1개"},
      {"name": "펠트지", "amount": "2장"}
    ],
    "steps": [
      {"id": 1, "summary": "재료 준비", "detail": "재료를 책상에 올린다.", "t_start": 5, "t_end": 20},
      {"id": 2, "summary": "붙이기", "detail": "글루건으로 붙인다.", "t_start": 21, "t_end": 55}
    ],
    "visual_guides": [
      {"id": "vg-1", "step_id": 2, "source_phrase": "요만큼", "phrase": "요만큼",
       "type": "amount", "what_to_show": "글루 양이 보이는 장면",
       "best_visual_timestamp": 30, "guide_text": "동전 크기만큼 짠다.", "importance": 0.9},
      {"id": "vg-2", "step_id": 1, "source_phrase": "가지런히", "phrase": "가지런히",
       "type": "position", "what_to_show": "정렬 상태",
       "best_visual_timestamp": null, "guide_text": "긴 변을 맞춰 정렬.", "importance": 0.6}
    ],
    "_duration": 90,
    "_profile": "generic",
    "_output_language": "ko",
    "_max_visual_guides": 5,
    "_model": "gemini-flash-lite-latest"
  },
  "warnings": []
}
```

- [ ] **Step 3: 테스트 번들 헬퍼 + 실패하는 테스트 작성**

`Tests/TestBundle.swift`:

```swift
import Foundation

final class TestBundleToken {}

extension Bundle {
    static var tests: Bundle { Bundle(for: TestBundleToken.self) }

    /// 폴더 레퍼런스로 복사된 Fixtures에서 로드. subdirectory는 "Fixtures" 기준 하위 경로.
    static func fixtureData(_ name: String, ext: String = "json",
                            subdirectory: String = "Fixtures") throws -> Data {
        guard let url = tests.url(forResource: name, withExtension: ext, subdirectory: subdirectory) else {
            throw NSError(domain: "fixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture not found: \(subdirectory)/\(name).\(ext)"])
        }
        return try Data(contentsOf: url)
    }
}
```

`Tests/AnalysisTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct AnalysisTests {
    @Test func decodesAnalyzeResponseFixture() throws {
        let data = try Bundle.fixtureData("analyze-response")
        let envelope = try JSONDecoder().decode(AnalyzeEnvelope.self, from: data)
        #expect(envelope.videoId == "dQw4w9WgXcQ")
        let a = envelope.analysis
        #expect(a.title == "테스트 하우투 영상")
        #expect(a.category == "생활")
        #expect(a.servings == nil)
        #expect(a.materials.count == 2)
        #expect(a.steps[0].tStart == 5 && a.steps[1].tEnd == 55)
        #expect(a.visualGuides[0].bestVisualTimestamp == 30)
        #expect(a.visualGuides[1].bestVisualTimestamp == nil)
        #expect(a.visualGuides[0].stepId == 2)
        #expect(a.duration == 90)
        #expect(a.profile == "generic")
    }
}
```

- [ ] **Step 4: 실패 확인**

```bash
cd /Users/choejunhwan/dev/stepkeeper-apple
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: 컴파일 실패 — `cannot find 'AnalyzeEnvelope' in scope` (테스트가 먼저, 타입이 없음).

- [ ] **Step 5: 모델 구현**

`Sources/Models/Analysis.swift`:

```swift
import Foundation

struct Material: Codable, Sendable, Equatable {
    var name: String
    var amount: String
}

struct Step: Codable, Sendable, Equatable {
    var id: Int
    var summary: String
    var detail: String
    var tStart: Int
    var tEnd: Int

    enum CodingKeys: String, CodingKey {
        case id, summary, detail
        case tStart = "t_start"
        case tEnd = "t_end"
    }
}

struct VisualGuide: Codable, Sendable, Equatable {
    var id: String
    var stepId: Int
    var sourcePhrase: String
    var phrase: String
    var type: String
    var whatToShow: String
    var bestVisualTimestamp: Int?
    var guideText: String
    var importance: Double

    enum CodingKeys: String, CodingKey {
        case id, phrase, type, importance
        case stepId = "step_id"
        case sourcePhrase = "source_phrase"
        case whatToShow = "what_to_show"
        case bestVisualTimestamp = "best_visual_timestamp"
        case guideText = "guide_text"
    }
}

struct Analysis: Codable, Sendable, Equatable {
    var title: String
    var summary: String
    var category: String?
    var servings: String?
    var materials: [Material]
    var steps: [Step]
    var visualGuides: [VisualGuide]
    var duration: Int?
    var profile: String?
    var outputLanguage: String?

    enum CodingKeys: String, CodingKey {
        case title, summary, category, servings, materials, steps
        case visualGuides = "visual_guides"
        case duration = "_duration"
        case profile = "_profile"
        case outputLanguage = "_output_language"
    }

    /// step_id → Step (캡처·렌더에서 공용)
    var stepsByID: [Int: Step] { Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) }) }
}

/// /v1/analyze 응답 envelope
struct AnalyzeEnvelope: Codable, Sendable {
    var videoId: String
    var analysis: Analysis
    var warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case analysis, warnings
    }
}
```

- [ ] **Step 6: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: 커밋**

```bash
git add project.yml Sources/Models Sources/Info.plist Tests
git commit -m "feat: Analysis 모델 + 테스트 타깃 (fixture 디코딩)"
```

---

### Task 3: YouTubeURL 파싱 + CandidateTimes

**Files:**
- Create: `Sources/Models/YouTubeURL.swift`, `Sources/Models/CandidateTimes.swift`, `Tests/YouTubeURLTests.swift`, `Tests/CandidateTimesTests.swift`

**Interfaces:**
- Consumes: `Step` (Task 2)
- Produces: `YouTubeURL.videoID(from: String) -> String?`, `CandidateTimes(step: Step?, center: Int, duration: Int)` — `before/center/after: Int` 프로퍼티, `slots: [(slot: String, time: Int)]`(순서 before,center,after). Task 10·11이 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YouTubeURLTests.swift`:

```swift
import Testing
@testable import stepkeeper

struct YouTubeURLTests {
    @Test func parsesCommonForms() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=4ioPBiTWm3M") == "4ioPBiTWm3M")
        #expect(YouTubeURL.videoID(from: "https://m.youtube.com/watch?v=4ioPBiTWm3M&t=10") == "4ioPBiTWm3M")
        #expect(YouTubeURL.videoID(from: "https://youtu.be/4ioPBiTWm3M?si=abc") == "4ioPBiTWm3M")
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/shorts/4ioPBiTWm3M") == "4ioPBiTWm3M")
    }
    @Test func rejectsInvalid() {
        #expect(YouTubeURL.videoID(from: "https://example.com/watch?v=abc") == nil)
        #expect(YouTubeURL.videoID(from: "그냥 텍스트") == nil)
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=short") == nil)
    }
}
```

`Tests/CandidateTimesTests.swift` (코어 `capture.py::candidate_times`와 동일 규칙):

```swift
import Testing
@testable import stepkeeper

struct CandidateTimesTests {
    private func makeStep(_ tStart: Int, _ tEnd: Int) -> Step {
        Step(id: 1, summary: "s", detail: "d", tStart: tStart, tEnd: tEnd)
    }
    @Test func withStepSpreadsAcrossStep() {
        let t = CandidateTimes(step: makeStep(10, 20), center: 15, duration: 100)
        #expect(t.before == 9 && t.center == 15 && t.after == 21)
    }
    @Test func clampsToVideoRange() {
        let t = CandidateTimes(step: makeStep(0, 99), center: 50, duration: 100)
        #expect(t.before == 0 && t.after == 99)   // duration-1 클램프
    }
    @Test func withoutStepUsesPlusMinus4() {
        let t = CandidateTimes(step: nil, center: 2, duration: 100)
        #expect(t.before == 0 && t.center == 2 && t.after == 6)
    }
    @Test func slotsOrderIsBeforeCenterAfter() {
        let t = CandidateTimes(step: nil, center: 10, duration: 100)
        #expect(t.slots.map(\.slot) == ["before", "center", "after"])
        #expect(t.slots.map(\.time) == [6, 10, 14])
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'YouTubeURL' in scope`.

- [ ] **Step 3: 구현**

`Sources/Models/YouTubeURL.swift` (코어 `common.py`와 동일 정규식):

```swift
import Foundation

enum YouTubeURL {
    private static let pattern = /(?:v=|youtu\.be\/|shorts\/)([\w-]{11})(?![\w-])/

    static func videoID(from string: String) -> String? {
        guard string.contains("youtube.com") || string.contains("youtu.be") else { return nil }
        guard let match = string.firstMatch(of: pattern) else { return nil }
        return String(match.1)
    }

    static func watchURL(videoID: String) -> URL {
        URL(string: "https://m.youtube.com/watch?v=\(videoID)")!
    }
}
```

주의: 코어 정규식 `(?:v=|youtu\.be/|shorts/)([\w-]{11})`에 두 가지를 더했다 — ①`(?![\w-])` 뒤경계(11자 초과 id 오탐 방지, `watch?v=short` 거부), ②유튜브 도메인 확인(임의 사이트의 `v=` 오탐 방지). 코어보다 엄격하지만 유효 URL 집합은 동일.

`Sources/Models/CandidateTimes.swift`:

```swift
/// capture.py::candidate_times 포팅 — 후보 3장을 스텝 범위에 걸쳐 분산
struct CandidateTimes: Equatable, Sendable {
    let before: Int
    let center: Int
    let after: Int

    init(step: Step?, center: Int, duration: Int) {
        self.center = center
        let last = max(0, duration - 1)
        if let step {
            before = max(0, step.tStart - 1)
            after = min(last, step.tEnd + 1)
        } else {
            before = max(0, center - 4)
            after = min(last, center + 4)
        }
    }

    var slots: [(slot: String, time: Int)] {
        [("before", before), ("center", center), ("after", after)]
    }
}
```

- [ ] **Step 4: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add Sources/Models Tests
git commit -m "feat: YouTubeURL 파싱 + CandidateTimes (코어 규칙 포팅)"
```

---

### Task 4: MustacheLite — 코어 미니 mustache 렌더러 포팅

문서 출력 파리티의 핵심. `../stepkeeper/render.py` 47–107행(`render`/`capture_block`/`_lookup`)을 그대로 포팅한다. **동작을 임의로 개선하지 말 것** — 파이썬과 같은 입력이면 같은 출력이 목표.

**Files:**
- Create: `Sources/Services/MustacheLite.swift`, `Tests/MustacheLiteTests.swift`

**Interfaces:**
- Produces: `MustacheValue`(indirect enum: `.string(String) .int(Int) .double(Double) .bool(Bool) .list([MustacheValue]) .dict([String: MustacheValue]) .null`), `MustacheLite.render(_ template: String, _ data: MustacheValue) throws -> String`, `MustacheLite.UnclosedSection: Error`. Task 5가 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/MustacheLiteTests.swift`:

```swift
import Testing
@testable import stepkeeper

struct MustacheLiteTests {
    private func d(_ pairs: [String: MustacheValue]) -> MustacheValue { .dict(pairs) }

    @Test func substitutesVariables() throws {
        #expect(try MustacheLite.render("Hello {{name}}!", d(["name": .string("stepkeeper")]))
                == "Hello stepkeeper!")
    }
    @Test func missingKeyRendersEmpty() throws {
        #expect(try MustacheLite.render("[{{nope}}]", d([:])) == "[]")
    }
    @Test func intVariableRendersLikePythonStr() throws {
        #expect(try MustacheLite.render("{{id}}.", d(["id": .int(3)])) == "3.")
    }
    @Test func sectionIteratesListWithParentLookup() throws {
        let tpl = "{{#items}}{{name}}@{{host}};{{/items}}"
        let data = d(["host": .string("h"),
                      "items": .list([d(["name": .string("a")]), d(["name": .string("b")])])])
        #expect(try MustacheLite.render(tpl, data) == "a@h;b@h;")
    }
    @Test func invertedSectionOnFalsy() throws {
        let tpl = "{{^has}}없음{{/has}}{{#has}}있음{{/has}}"
        #expect(try MustacheLite.render(tpl, d(["has": .bool(false)])) == "없음")
        #expect(try MustacheLite.render(tpl, d(["has": .bool(true)])) == "있음")
        #expect(try MustacheLite.render(tpl, d(["has": .string("")])) == "없음")
        #expect(try MustacheLite.render(tpl, d([:])) == "없음")   // 미존재 키도 falsy
    }
    @Test func emptyListSectionSkipsBody() throws {
        #expect(try MustacheLite.render("[{{#xs}}x{{/xs}}]", d(["xs": .list([])])) == "[]")
    }
    @Test func standaloneSectionLinesLeaveNoBlankLines() throws {
        // 파이썬 전처리: 섹션 태그만 있는 줄은 들여쓰기+개행 제거
        let tpl = "A\n{{#x}}\nB\n{{/x}}\nC\n"
        #expect(try MustacheLite.render(tpl, d(["x": .bool(true)])) == "A\nB\nC\n")
        #expect(try MustacheLite.render(tpl, d(["x": .bool(false)])) == "A\nC\n")
    }
    @Test func nestedSectionsOfSameShapeResolve() throws {
        let tpl = "{{#steps}}{{id}}:{{#visual_guides}}<{{id}}>{{/visual_guides}} {{/steps}}"
        let data = d(["steps": .list([
            d(["id": .int(1), "visual_guides": .list([d(["id": .string("vg-1")])])]),
            d(["id": .int(2), "visual_guides": .list([])]),
        ])])
        #expect(try MustacheLite.render(tpl, data) == "1:<vg-1> 2: ")
    }
    @Test func unclosedSectionThrows() {
        #expect(throws: MustacheLite.UnclosedSection.self) {
            try MustacheLite.render("{{#a}}x", d(["a": .bool(true)]))
        }
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'MustacheLite' in scope`.

- [ ] **Step 3: 구현**

`Sources/Services/MustacheLite.swift`:

```swift
import Foundation

indirect enum MustacheValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case list([MustacheValue])
    case dict([String: MustacheValue])
    case null
}

/// 코어 render.py의 미니 mustache 렌더러 포팅 (sections/inverted/vars, 스택 lookup, 중첩).
/// 파이썬과의 출력 파리티가 목적 — 골든 테스트(Task 5)가 기준. 동작을 "개선"하지 말 것.
enum MustacheLite {
    struct UnclosedSection: Error { let key: String }

    private static let token = /\{\{([#^\/]?)\s*([\w.]+)\s*\}\}/
    // (?m)^[ \t]*({{[#^/]key}})[ \t]*\r?\n → \1 : standalone 섹션 태그 줄의 들여쓰기+개행 제거
    private static let standaloneLine = /(?m)^[ \t]*(\{\{[#^\/][\w.]+\}\})[ \t]*\r?\n/

    static func render(_ template: String, _ data: MustacheValue) throws -> String {
        let cleaned = template.replacing(standaloneLine) { String($0.output.1) }
        return try parse(cleaned[...], [data]).out
    }

    private static func parse(_ text: Substring, _ stack: [MustacheValue]) throws
        -> (out: String, stopped: Bool) {
        var out = ""
        var rest = text
        while let m = rest.firstMatch(of: token) {
            out.append(contentsOf: rest[..<m.range.lowerBound])
            let sigil = String(m.output.1)
            let key = String(m.output.2)
            switch sigil {
            case "#", "^":
                let block = try captureBlock(rest[m.range.upperBound...], key: key)
                let val = lookup(stack, key)
                if sigil == "#" {
                    switch val {
                    case .list(let items):
                        for item in items { out += try parse(block.inner, stack + [item]).out }
                    case .dict:
                        out += try parse(block.inner, stack + [val]).out
                    default:
                        if isTruthy(val) { out += try parse(block.inner, stack).out }
                    }
                } else if !isTruthy(val) {
                    out += try parse(block.inner, stack).out
                }
                rest = block.after
            case "/":
                return (out, true) // 파이썬 동작: 고아 닫힘 태그에서 그대로 반환
            default:
                out += stringify(lookup(stack, key))
                rest = rest[m.range.upperBound...]
            }
        }
        out.append(contentsOf: rest)
        return (out, false)
    }

    private static func captureBlock(_ text: Substring, key: String) throws
        -> (inner: Substring, after: Substring) {
        var depth = 1
        var rest = text
        while let m = rest.firstMatch(of: token) {
            let sigil = String(m.output.1)
            let k = String(m.output.2)
            if (sigil == "#" || sigil == "^") && k == key {
                depth += 1
            } else if sigil == "/" && k == key {
                depth -= 1
                if depth == 0 {
                    return (text[..<m.range.lowerBound], rest[m.range.upperBound...])
                }
            }
            rest = rest[m.range.upperBound...]
        }
        throw UnclosedSection(key: key)
    }

    private static func lookup(_ stack: [MustacheValue], _ key: String) -> MustacheValue {
        for ctx in stack.reversed() {
            if case .dict(let entries) = ctx, let value = entries[key] { return value }
        }
        return .null
    }

    /// 파이썬 truthy: bool(v) and v != [] and v != ""
    private static func isTruthy(_ value: MustacheValue) -> Bool {
        switch value {
        case .null: false
        case .bool(let b): b
        case .int(let i): i != 0
        case .double(let d): d != 0
        case .string(let s): !s.isEmpty
        case .list(let l): !l.isEmpty
        case .dict(let d): !d.isEmpty
        }
    }

    /// 파이썬 str() 대응 (None → "")
    private static func stringify(_ value: MustacheValue) -> String {
        switch value {
        case .null: ""
        case .string(let s): s
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .bool(let b): b ? "True" : "False"
        case .list, .dict: "" // 템플릿에서 컬렉션을 변수로 쓰지 않음
        }
    }
}
```

- [ ] **Step 4: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add Sources/Services/MustacheLite.swift Tests/MustacheLiteTests.swift
git commit -m "feat: MustacheLite — 코어 미니 mustache 렌더러 포팅"
```

---

### Task 5: 템플릿 리소스 + MarkdownBuilder + 골든 테스트

`render.py::build_context`를 포팅하고, 코어 렌더러가 생성한 기대 출력(expected.md)과 문자 단위로 대조한다. 골든이 곧 파리티 증명.

**Files:**
- Create: `scripts/sync-assets.sh`, `Resources/skill-core/{generic,recipe}/template.md`(복사본), `scripts/make-golden.py`, `Tests/Fixtures/golden/<case>/{analysis.json,case.json,expected.md}`(3케이스), `Sources/Services/MarkdownBuilder.swift`, `Tests/MarkdownBuilderGoldenTests.swift`
- Modify: `project.yml` (Stepkeeper 타깃에 Resources 폴더 레퍼런스 추가)

**Interfaces:**
- Consumes: `MustacheValue`/`MustacheLite.render` (Task 4), `Analysis` (Task 2)
- Produces: `Templates.load(profile: String) throws -> String`, `MarkdownBuilder.hms(_ sec: Int) -> String`, `MarkdownBuilder.markdown(videoId: String, analysis: Analysis, imageRefs: [String: String]) throws -> String` (+ `template:` 주입 오버로드). imageRefs는 `guide_id → 상대 파일명`(예: "vg-1.jpg"). Task 9·12가 사용.

- [ ] **Step 1: 템플릿 동기화 스크립트 + 리소스 복사**

`scripts/sync-assets.sh`:

```bash
#!/bin/bash
# skill-core 템플릿을 앱 리소스로 복사 (원본: ../stepkeeper). 코어 템플릿 갱신 시 재실행 후 골든 재생성.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${STEPKEEPER_PATH:-../stepkeeper}/skill-core/profiles"
for p in generic recipe; do
  mkdir -p "Resources/skill-core/$p"
  cp "$SRC/$p/template.md" "Resources/skill-core/$p/template.md"
done
echo "synced templates from $SRC"
```

```bash
chmod +x scripts/sync-assets.sh && ./scripts/sync-assets.sh
```

Expected: `synced templates from ../stepkeeper/skill-core/profiles`, `Resources/skill-core/{generic,recipe}/template.md` 생성.

- [ ] **Step 2: project.yml에 리소스 폴더 레퍼런스 추가**

`project.yml`의 Stepkeeper 타깃 `sources:`를 다음으로 교체:

```yaml
    sources:
      - Sources
      - path: Resources/skill-core
        type: folder
        buildPhase: resources
```

(폴더 레퍼런스라 번들 안에서 `skill-core/generic/template.md` 구조가 보존된다 — `Bundle.main.url(forResource:withExtension:subdirectory:)`로 접근.)

- [ ] **Step 3: 골든 케이스 fixture 작성 (3케이스)**

`Tests/Fixtures/golden/generic-mixed/analysis.json` — Task 2 fixture의 analysis 객체와 동일 내용(vg-1 이미지 선택, vg-2는 timestamp null 엣지):

```json
{
  "title": "테스트 하우투 영상",
  "summary": "요약 문장.",
  "category": "생활",
  "materials": [
    {"name": "글루건", "amount": "1개"},
    {"name": "펠트지", "amount": "2장"}
  ],
  "steps": [
    {"id": 1, "summary": "재료 준비", "detail": "재료를 책상에 올린다.", "t_start": 5, "t_end": 20},
    {"id": 2, "summary": "붙이기", "detail": "글루건으로 붙인다.", "t_start": 21, "t_end": 55}
  ],
  "visual_guides": [
    {"id": "vg-1", "step_id": 2, "source_phrase": "요만큼", "phrase": "요만큼",
     "type": "amount", "what_to_show": "글루 양이 보이는 장면",
     "best_visual_timestamp": 30, "guide_text": "동전 크기만큼 짠다.", "importance": 0.9},
    {"id": "vg-2", "step_id": 1, "source_phrase": "가지런히", "phrase": "가지런히",
     "type": "position", "what_to_show": "정렬 상태",
     "best_visual_timestamp": null, "guide_text": "긴 변을 맞춰 정렬.", "importance": 0.6}
  ],
  "_duration": 90,
  "_profile": "generic",
  "_output_language": "ko"
}
```

`Tests/Fixtures/golden/generic-mixed/case.json`:

```json
{"video_id": "dQw4w9WgXcQ", "image_refs": {"vg-1": "vg-1.jpg"}}
```

`Tests/Fixtures/golden/generic-links-only/analysis.json` — 위와 동일하되 `"category": ""` 로만 변경(빈 분류 + 이미지 없음 케이스).

`Tests/Fixtures/golden/generic-links-only/case.json`:

```json
{"video_id": "dQw4w9WgXcQ", "image_refs": {}}
```

`Tests/Fixtures/golden/recipe-mixed/analysis.json`:

```json
{
  "title": "돼지고기 김치볶음",
  "summary": "간단한 김치볶음 레시피.",
  "category": "요리",
  "servings": "2인분",
  "materials": [
    {"name": "돼지고기", "amount": "300g"},
    {"name": "김치", "amount": "1/2포기"}
  ],
  "steps": [
    {"id": 1, "summary": "고기 볶기", "detail": "달군 팬에 고기를 볶는다.", "t_start": 10, "t_end": 45},
    {"id": 2, "summary": "김치 넣고 졸이기", "detail": "김치를 넣고 자작해질 때까지 졸인다.", "t_start": 46, "t_end": 90}
  ],
  "visual_guides": [
    {"id": "vg-1", "step_id": 1, "source_phrase": "한입 크기", "phrase": "한입 크기",
     "type": "size", "what_to_show": "썰어둔 고기 크기", "best_visual_timestamp": 15,
     "guide_text": "3~4cm 큐브 크기.", "importance": 0.9},
    {"id": "vg-2", "step_id": 2, "source_phrase": "자작해질 때까지", "phrase": "자작해짐",
     "type": "state", "what_to_show": "국물이 줄어든 상태", "best_visual_timestamp": 80,
     "guide_text": "바닥에 국물이 거의 없고 양념이 코팅된 상태.", "importance": 0.8}
  ],
  "_duration": 120,
  "_profile": "recipe",
  "_output_language": "ko"
}
```

`Tests/Fixtures/golden/recipe-mixed/case.json`:

```json
{"video_id": "4ioPBiTWm3M", "image_refs": {"vg-2": "vg-2.jpg"}}
```

- [ ] **Step 4: 골든 생성 스크립트 작성·실행**

`scripts/make-golden.py`:

```python
#!/usr/bin/env python3
"""골든 기대 출력 생성 — 코어 render.py로 Tests/Fixtures/golden/<case>/expected.md 를 만든다.
사용: python3 scripts/make-golden.py   (코어 위치는 STEPKEEPER_PATH, 기본 ../stepkeeper)
서버 /v1/documents 와 동일 파이프라인: template 프론트매터 분리 → build_context(picks={}, image_refs) → render → strip + \\n
"""
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = Path(os.environ.get("STEPKEEPER_PATH", ROOT.parent / "stepkeeper")).resolve()
sys.path.insert(0, str(CORE))
import render as core_render  # noqa: E402

golden_root = ROOT / "Tests" / "Fixtures" / "golden"
for case_dir in sorted(p for p in golden_root.iterdir() if p.is_dir()):
    analysis = json.loads((case_dir / "analysis.json").read_text(encoding="utf-8"))
    case = json.loads((case_dir / "case.json").read_text(encoding="utf-8"))
    template = core_render.load_template(analysis["_profile"])
    body = template.split("\n---\n", 1)[1] if "\n---\n" in template else template
    with tempfile.TemporaryDirectory() as tmp:
        context = core_render.build_context(
            case["video_id"], analysis, picks={},
            source_frames=Path(tmp) / "no-frames", images_dir=Path(tmp),
            image_refs=case.get("image_refs", {}))
    markdown = core_render.render(body, context).strip() + "\n"
    (case_dir / "expected.md").write_text(markdown, encoding="utf-8")
    print(f"wrote {case_dir.name}/expected.md ({len(markdown)} chars)")
```

```bash
python3 scripts/make-golden.py
```

Expected: `wrote generic-links-only/expected.md ...` 등 3줄. 각 expected.md를 열어 눈으로 형태 확인(제목 이모지, 준비물/준비 재료, 이미지/링크 줄, 출처 푸터). **expected.md는 커밋 대상** (재생성 가능하지만 리뷰 가능한 스냅샷).

- [ ] **Step 5: 실패하는 골든 테스트 작성**

`Tests/MarkdownBuilderGoldenTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct MarkdownBuilderGoldenTests {
    struct GoldenCase: Codable {
        var videoId: String
        var imageRefs: [String: String]
        enum CodingKeys: String, CodingKey {
            case videoId = "video_id"
            case imageRefs = "image_refs"
        }
    }

    @Test func hmsMatchesCore() {
        #expect(MarkdownBuilder.hms(0) == "0:00")
        #expect(MarkdownBuilder.hms(59) == "0:59")
        #expect(MarkdownBuilder.hms(754) == "12:34")
        #expect(MarkdownBuilder.hms(3700) == "61:40")   // 시간 단위 없음 — 코어와 동일
    }

    @Test(arguments: ["generic-mixed", "generic-links-only", "recipe-mixed"])
    func matchesCoreRenderOutput(caseName: String) throws {
        let sub = "Fixtures/golden/\(caseName)"
        let analysis = try JSONDecoder().decode(
            Analysis.self, from: Bundle.fixtureData("analysis", subdirectory: sub))
        let golden = try JSONDecoder().decode(
            GoldenCase.self, from: Bundle.fixtureData("case", subdirectory: sub))
        let expected = String(
            data: try Bundle.fixtureData("expected", ext: "md", subdirectory: sub),
            encoding: .utf8)!
        let out = try MarkdownBuilder.markdown(
            videoId: golden.videoId, analysis: analysis, imageRefs: golden.imageRefs)
        #expect(out == expected)
    }
}
```

- [ ] **Step 6: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'MarkdownBuilder' in scope`.

- [ ] **Step 7: 구현**

`Sources/Services/MarkdownBuilder.swift`:

```swift
import Foundation

enum Templates {
    struct NotFound: Error { let profile: String }

    static func load(profile: String) throws -> String {
        guard let url = Bundle.main.url(
            forResource: "template", withExtension: "md",
            subdirectory: "skill-core/\(profile)") else {
            throw NotFound(profile: profile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// render.py::build_context + 서버 /v1/documents 조립 파이프라인 포팅.
/// 앱은 image_refs(클라이언트 캡처 이미지의 상대 파일명)만 쓴다 — 디스크 프레임·picks 분기는 코어 전용이라 생략.
enum MarkdownBuilder {
    /// 코어 hms: 시간 단위 없이 분:초
    static func hms(_ sec: Int) -> String {
        "\(sec / 60):" + String(format: "%02d", sec % 60)
    }

    static func context(videoId: String, analysis: Analysis,
                        imageRefs: [String: String]) -> MustacheValue {
        var byStep: [Int: [VisualGuide]] = [:]
        for guide in analysis.visualGuides {
            byStep[guide.stepId, default: []].append(guide)
        }

        let steps: [MustacheValue] = analysis.steps.map { step in
            let guides: [MustacheValue] = (byStep[step.id] ?? []).map { guide in
                let ts = guide.bestVisualTimestamp
                var ctx: [String: MustacheValue] = [
                    "id": .string(guide.id),
                    "phrase": .string(guide.phrase),
                    "source_phrase": .string(guide.sourcePhrase),
                    "guide_text": .string(guide.guideText),
                    "importance": .double(guide.importance),
                    "has_screenshot": .bool(false),
                    "screenshot": .string(""),
                    "timestamp_hms": .string(ts.map(hms) ?? ""),
                    "timestamp_link": .string(
                        ts.map { "https://youtu.be/\(videoId)?t=\($0)" }
                        ?? "https://youtu.be/\(videoId)"),
                ]
                if let ref = imageRefs[guide.id] {
                    ctx["has_screenshot"] = .bool(true)
                    ctx["screenshot"] = .string(ref)
                }
                return .dict(ctx)
            }
            return .dict([
                "id": .int(step.id),
                "summary": .string(step.summary),
                "detail": .string(step.detail),
                "visual_guides": .list(guides),
            ])
        }

        let materials = MustacheValue.list(analysis.materials.map {
            .dict(["name": .string($0.name), "amount": .string($0.amount)])
        })
        return .dict([
            "title": .string(analysis.title),
            "summary": .string(analysis.summary),
            "video_summary": .string(analysis.summary),
            "category": .string(analysis.category ?? ""),
            "servings": .string(analysis.servings ?? ""),
            "materials": materials,
            "ingredients": materials,
            "steps": .list(steps),
            "video_title": .string(analysis.title),
            "video_url": .string("https://youtu.be/\(videoId)"),
        ])
    }

    static func markdown(videoId: String, analysis: Analysis,
                         imageRefs: [String: String], template: String) throws -> String {
        let body: Substring
        if let range = template.range(of: "\n---\n") {
            body = template[range.upperBound...]
        } else {
            body = template[...]
        }
        let rendered = try MustacheLite.render(
            String(body),
            context(videoId: videoId, analysis: analysis, imageRefs: imageRefs))
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func markdown(videoId: String, analysis: Analysis,
                         imageRefs: [String: String]) throws -> String {
        try markdown(videoId: videoId, analysis: analysis, imageRefs: imageRefs,
                     template: Templates.load(profile: analysis.profile ?? "generic"))
    }
}
```

- [ ] **Step 8: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **` (골든 3케이스 + hms 포함 전부 그린). 골든 불일치 시 출력 diff를 보고 **MustacheLite/컨텍스트 쪽을 고친다** — expected.md를 손으로 고치는 것 금지(그건 파리티 포기).

- [ ] **Step 9: 커밋**

```bash
git add scripts Resources project.yml Sources/Services/MarkdownBuilder.swift Tests
git commit -m "feat: MarkdownBuilder — build_context 포팅 + 코어 골든 테스트"
```

---

### Task 6: KeychainStore + Settings 기본값

**Files:**
- Create: `Sources/Services/KeychainStore.swift`, `Sources/Services/Settings.swift`, `Tests/KeychainStoreTests.swift`, `Tests/SettingsTests.swift`

**Interfaces:**
- Produces: `KeychainStore(service:account:)` — `save(_ value: String) throws`, `load() throws -> String?`, `delete() throws`, 기본 인스턴스 `KeychainStore.geminiKey`. `Settings` — 키 상수(`serverURLKey/languageKey/linkModeKey`), 기본값(`defaultServerURL = "http://127.0.0.1:8787"`, `defaultLanguage = "ko"`), `registerDefaults()`. Task 9·10이 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/KeychainStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct KeychainStoreTests {
    @Test func roundTripSaveLoadOverwriteDelete() throws {
        let store = KeychainStore(service: "stepkeeper.tests.\(UUID().uuidString)")
        defer { try? store.delete() }

        #expect(try store.load() == nil)
        try store.save("key-1")
        #expect(try store.load() == "key-1")
        try store.save("key-2")                 // 덮어쓰기
        #expect(try store.load() == "key-2")
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()                      // 없는 항목 삭제도 에러 아님
    }
}
```

`Tests/SettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct SettingsTests {
    @Test func registersDefaults() {
        let suite = UserDefaults(suiteName: "stepkeeper.tests.settings")!
        suite.removePersistentDomain(forName: "stepkeeper.tests.settings")
        Settings.registerDefaults(suite)
        #expect(suite.string(forKey: Settings.serverURLKey) == "http://127.0.0.1:8787")
        #expect(suite.string(forKey: Settings.languageKey) == "ko")
        #expect(suite.bool(forKey: Settings.linkModeKey) == false)
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'KeychainStore' in scope`.

- [ ] **Step 3: 구현**

`Sources/Services/KeychainStore.swift`:

```swift
import Foundation
import Security

/// Gemini 키 등 비밀 값 저장 (kSecClassGenericPassword).
/// 키 값은 로그·에러 메시지에 절대 포함하지 않는다.
struct KeychainStore: Sendable {
    var service: String
    var account: String = "default"

    static let geminiKey = KeychainStore(service: "stepkeeper.gemini-key")

    struct UnexpectedStatus: Error, Equatable { let status: OSStatus }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw UnexpectedStatus(status: addStatus) }
        } else if status != errSecSuccess {
            throw UnexpectedStatus(status: status)
        }
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw UnexpectedStatus(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UnexpectedStatus(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
```

`Sources/Services/Settings.swift`:

```swift
import Foundation

/// @AppStorage 키와 기본값의 단일 원천. 뷰는 @AppStorage(Settings.xxxKey), 로직은 UserDefaults로 읽는다.
enum Settings {
    static let serverURLKey = "serverURL"
    static let languageKey = "language"
    static let linkModeKey = "linkMode"

    static let defaultServerURL = "http://127.0.0.1:8787"
    static let defaultLanguage = "ko"
    static let maxGuides = 5   // v1 고정 (스펙 4.3)

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            serverURLKey: defaultServerURL,
            languageKey: defaultLanguage,
            linkModeKey: false,
        ])
    }
}
```

- [ ] **Step 4: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add Sources/Services Tests
git commit -m "feat: KeychainStore + Settings 기본값"
```

---

### Task 7: StepkeeperAPI — /v1/analyze 클라이언트 + 에러 매핑

**Files:**
- Create: `Sources/Services/StepkeeperAPI.swift`, `Tests/StepkeeperAPITests.swift`

**Interfaces:**
- Consumes: `AnalyzeEnvelope`/`Analysis` (Task 2), `Settings.maxGuides` (Task 6)
- Produces: `StepkeeperAPIError`(`.missingKey .badRequest(String) .rateLimited .modelFailure(String) .server(Int, String) .network(String) .invalidResponse` — `LocalizedError`, 스펙 6절 문구), `AnalyzeResult(videoId: String, analysis: Analysis, rawAnalysis: Data)`, `StepkeeperAPI(baseURL: URL, session: URLSession = .shared)` — `analyze(videoURL: String, profile: String, language: String, maxGuides: Int = Settings.maxGuides, duration: Int, geminiKey: String) async throws -> AnalyzeResult`. Task 9가 사용. `rawAnalysis`는 서버가 준 analysis 객체를 필드 손실 없이 보존(JSONSerialization 재직렬화 — `_model` 등 모델에 없는 키 유지), Task 8이 analysis.json으로 저장.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/StepkeeperAPITests.swift` (URLProtocol 스텁 — static 상태를 쓰므로 **`.serialized`** 필수):

```swift
import Testing
import Foundation
@testable import stepkeeper

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var networkError: (any Error)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let error = Self.networkError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let (status, data) = Self.handler!(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

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
        config.protocolClasses = [StubURLProtocol.self]
        return StepkeeperAPI(baseURL: URL(string: "http://stub.local:8787")!,
                           session: URLSession(configuration: config))
    }
    private func reset() {
        StubURLProtocol.handler = nil
        StubURLProtocol.networkError = nil
    }

    @Test func successDecodesAndPreservesRawAnalysis() async throws {
        defer { reset() }
        let fixture = try Bundle.fixtureData("analyze-response")
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/analyze")
            #expect(request.value(forHTTPHeaderField: "X-Gemini-Key") == "test-key")
            let body = try! JSONSerialization.jsonObject(
                with: request.bodyData ?? Data()) as! [String: Any]
            #expect(body["duration"] as? Int == 90)          // 결정 #3: duration은 앱이 보낸다
            #expect(body["max_guides"] as? Int == 5)
            #expect(body["model"] == nil)                    // 서버 기본값 사용
            return (200, fixture)
        }
        let result = try await makeAPI().analyze(
            videoURL: "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
            profile: "generic", language: "ko", duration: 90, geminiKey: "test-key")
        #expect(result.videoId == "dQw4w9WgXcQ")
        #expect(result.analysis.steps.count == 2)
        let raw = try JSONSerialization.jsonObject(with: result.rawAnalysis) as! [String: Any]
        #expect(raw["_model"] as? String == "gemini-flash-lite-latest")  // 모델에 없는 키 보존
    }

    @Test func maps401ToMissingKey() async throws {
        defer { reset() }
        StubURLProtocol.handler = { _ in
            (401, Data(#"{"detail": "X-Gemini-Key 헤더가 필요합니다."}"#.utf8))
        }
        await #expect(throws: StepkeeperAPIError.missingKey) {
            _ = try await self.makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
        }
    }

    @Test func maps422To429To502() async throws {
        defer { reset() }
        StubURLProtocol.handler = { _ in (422, Data(#"{"detail": "bad url"}"#.utf8)) }
        await #expect(throws: StepkeeperAPIError.badRequest("bad url")) {
            _ = try await self.makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
        }
        StubURLProtocol.handler = { _ in (429, Data(#"{"detail": "quota"}"#.utf8)) }
        await #expect(throws: StepkeeperAPIError.rateLimited) {
            _ = try await self.makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
        }
        // FastAPI는 detail이 객체일 수도 있음 (계약 위반 케이스)
        StubURLProtocol.handler = { _ in
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
        StubURLProtocol.networkError = URLError(.cannotConnectToHost)
        do {
            _ = try await makeAPI().analyze(
                videoURL: "u", profile: "generic", language: "ko", duration: 10, geminiKey: "k")
            Issue.record("should throw")
        } catch let error as StepkeeperAPIError {
            guard case .network = error else { Issue.record("wrong case: \(error)"); return }
        }
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'StepkeeperAPI' in scope`.

- [ ] **Step 3: 구현**

`Sources/Services/StepkeeperAPI.swift`:

```swift
import Foundation

enum StepkeeperAPIError: Error, Equatable, LocalizedError {
    case missingKey            // 401
    case badRequest(String)    // 422
    case rateLimited           // 429
    case modelFailure(String)  // 502 (모델 오류·계약 위반)
    case server(Int, String)   // 기타 상태코드
    case network(String)       // 연결 실패
    case invalidResponse       // 200이지만 해석 불가

    var errorDescription: String? {
        switch self {
        case .missingKey: "설정에서 Gemini API 키를 입력하세요"
        case .badRequest(let detail): "URL 또는 요청 값 문제 — \(detail)"
        case .rateLimited: "Gemini 무료 한도 도달 — 잠시 후 다시 시도해 주세요"
        case .modelFailure(let detail): "분석에 실패했습니다 — 다시 시도해 주세요 (\(detail))"
        case .server(let code, let detail): "서버 오류 (HTTP \(code)) — \(detail)"
        case .network: "서버에 연결할 수 없습니다 — 서버 URL을 확인하세요"
        case .invalidResponse: "서버 응답을 해석하지 못했습니다"
        }
    }
}

struct AnalyzeResult: Sendable {
    var videoId: String
    var analysis: Analysis
    /// 서버가 준 analysis 객체 그대로(모델에 없는 `_model` 등 보존) — analysis.json 저장용
    var rawAnalysis: Data
}

final class StepkeeperAPI: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func analyze(videoURL: String, profile: String, language: String,
                 maxGuides: Int = Settings.maxGuides, duration: Int,
                 geminiKey: String) async throws -> AnalyzeResult {
        var request = URLRequest(url: baseURL.appending(path: "/v1/analyze"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180   // Gemini 분석은 영상 길이에 따라 수십 초
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(geminiKey, forHTTPHeaderField: "X-Gemini-Key")
        let body: [String: Any] = [
            "url": videoURL, "profile": profile, "language": language,
            "max_guides": maxGuides, "duration": duration,
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
        switch http.statusCode {
        case 200: break
        case 401: throw StepkeeperAPIError.missingKey
        case 422: throw StepkeeperAPIError.badRequest(Self.detail(from: data))
        case 429: throw StepkeeperAPIError.rateLimited
        case 502: throw StepkeeperAPIError.modelFailure(Self.detail(from: data))
        default: throw StepkeeperAPIError.server(http.statusCode, Self.detail(from: data))
        }

        guard let envelope = try? JSONDecoder().decode(AnalyzeEnvelope.self, from: data),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawAnalysisObject = object["analysis"],
              let rawAnalysis = try? JSONSerialization.data(withJSONObject: rawAnalysisObject)
        else { throw StepkeeperAPIError.invalidResponse }
        return AnalyzeResult(videoId: envelope.videoId,
                             analysis: envelope.analysis, rawAnalysis: rawAnalysis)
    }

    /// FastAPI 에러 body {"detail": <string|object>}에서 사람이 읽을 문자열 추출
    private static func detail(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = object["detail"] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        if let text = detail as? String { return text }
        if let encoded = try? JSONSerialization.data(withJSONObject: detail),
           let text = String(data: encoded, encoding: .utf8) { return text }
        return ""
    }
}
```

- [ ] **Step 4: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add Sources/Services/StepkeeperAPI.swift Tests/StepkeeperAPITests.swift
git commit -m "feat: StepkeeperAPI — /v1/analyze 클라이언트 + 상태코드 에러 매핑"
```

---

### Task 8: DocumentStore — 문서 저장·목록·재열람

**Files:**
- Create: `Sources/Services/DocumentStore.swift`, `Tests/DocumentStoreTests.swift`

**Interfaces:**
- Consumes: `Analysis` (Task 2)
- Produces: `DocumentMeta(id, title, videoId, profile, language, createdAt)`(`Codable, Identifiable`), `SavedDocument(meta, analysis, picks: [String: String], markdown, folder: URL)`, `DocumentStore(root: URL)` — `save(videoId:title:analysis:rawAnalysis:picks:images:markdown:) throws -> DocumentMeta`(images는 `파일명→JPEG Data`), `list() throws -> [DocumentMeta]`(생성일 내림차순), `load(id:) throws -> SavedDocument`, `delete(id:) throws`, `folderURL(id:) -> URL`, `static defaultRoot() throws -> URL`(= `Documents/stepkeeper`). Task 9·10·12가 사용. 폴더 구성은 스펙 4.6: `document.md`, `vg-N.jpg`, `meta.json`, `analysis.json`(rawAnalysis 그대로), `picks.json`.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/DocumentStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct DocumentStoreTests {
    private func makeStore() throws -> (DocumentStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("stepkeeper-tests-\(UUID().uuidString)")
        return (DocumentStore(root: root), root)
    }
    private func sampleAnalysis() throws -> (Analysis, Data) {
        let data = try Bundle.fixtureData("analyze-response")
        let envelope = try JSONDecoder().decode(AnalyzeEnvelope.self, from: data)
        let raw = try JSONSerialization.data(
            withJSONObject: (try JSONSerialization.jsonObject(with: data) as! [String: Any])["analysis"]!)
        return (envelope.analysis, raw)
    }

    @Test func saveWritesAllFilesAndListLoadsBack() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        let meta = try store.save(
            videoId: "dQw4w9WgXcQ", title: analysis.title, analysis: analysis,
            rawAnalysis: raw, picks: ["vg-1": "center", "vg-2": "none"],
            images: ["vg-1.jpg": jpeg], markdown: "## 문서\n")

        #expect(meta.id.hasPrefix("dQw4w9WgXcQ-"))
        let folder = store.folderURL(id: meta.id)
        for name in ["document.md", "meta.json", "analysis.json", "picks.json", "vg-1.jpg"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path),
                    "missing \(name)")
        }
        #expect(try Data(contentsOf: folder.appendingPathComponent("vg-1.jpg")) == jpeg)

        let listed = try store.list()
        #expect(listed.count == 1 && listed[0].title == "테스트 하우투 영상")

        let doc = try store.load(id: meta.id)
        #expect(doc.analysis == analysis)
        #expect(doc.picks == ["vg-1": "center", "vg-2": "none"])
        #expect(doc.markdown == "## 문서\n")

        try store.delete(id: meta.id)
        #expect(try store.list().isEmpty)
    }

    @Test func savedAnalysisJSONPreservesUnknownKeys() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let meta = try store.save(videoId: "v", title: "t", analysis: analysis,
                                  rawAnalysis: raw, picks: [:], images: [:], markdown: "m\n")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf:
            store.folderURL(id: meta.id).appendingPathComponent("analysis.json"))) as! [String: Any]
        #expect(saved["_model"] as? String == "gemini-flash-lite-latest")
    }

    @Test func listSortsByCreatedAtDescending() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let (analysis, raw) = try sampleAnalysis()
        let first = try store.save(videoId: "aaaaaaaaaaa", title: "먼저", analysis: analysis,
                                   rawAnalysis: raw, picks: [:], images: [:], markdown: "1\n")
        let second = try store.save(videoId: "bbbbbbbbbbb", title: "나중", analysis: analysis,
                                    rawAnalysis: raw, picks: [:], images: [:], markdown: "2\n")
        #expect(first.id != second.id)   // 같은 초에 저장돼도 id 유일
        let listed = try store.list()
        #expect(listed.first?.title == "나중")
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'DocumentStore' in scope`.

- [ ] **Step 3: 구현**

`Sources/Services/DocumentStore.swift`:

```swift
import Foundation

struct DocumentMeta: Codable, Sendable, Equatable, Identifiable {
    var id: String        // 폴더명: <videoId>-<yyyyMMdd-HHmmss>[-n]
    var title: String
    var videoId: String
    var profile: String
    var language: String
    var createdAt: Date
}

struct SavedDocument: Sendable {
    var meta: DocumentMeta
    var analysis: Analysis
    var picks: [String: String]
    var markdown: String
    var folder: URL
}

/// 스펙 4.6: Documents/stepkeeper/<id>/ 아래 document.md + vg-N.jpg + meta.json + analysis.json + picks.json
final class DocumentStore: Sendable {
    private let root: URL

    init(root: URL) { self.root = root }

    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("stepkeeper", isDirectory: true)
    }

    func folderURL(id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

    func save(videoId: String, title: String, analysis: Analysis, rawAnalysis: Data,
              picks: [String: String], images: [String: Data], markdown: String) throws -> DocumentMeta {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(videoId)-\(formatter.string(from: now))"
        var id = base
        var counter = 2
        while FileManager.default.fileExists(atPath: folderURL(id: id).path) {
            id = "\(base)-\(counter)"
            counter += 1
        }
        let folder = folderURL(id: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let meta = DocumentMeta(id: id, title: title, videoId: videoId,
                                profile: analysis.profile ?? "generic",
                                language: analysis.outputLanguage ?? "ko", createdAt: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try Data(markdown.utf8).write(to: folder.appendingPathComponent("document.md"))
        try encoder.encode(meta).write(to: folder.appendingPathComponent("meta.json"))
        try rawAnalysis.write(to: folder.appendingPathComponent("analysis.json"))
        try encoder.encode(picks).write(to: folder.appendingPathComponent("picks.json"))
        for (name, data) in images {
            try data.write(to: folder.appendingPathComponent(name))
        }
        return meta
    }

    func list() throws -> [DocumentMeta] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return folders.compactMap { folder -> DocumentMeta? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
                  let meta = try? decoder.decode(DocumentMeta.self, from: data) else { return nil }
            return meta
        }
        .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    func load(id: String) throws -> SavedDocument {
        let folder = folderURL(id: id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = try decoder.decode(
            DocumentMeta.self, from: Data(contentsOf: folder.appendingPathComponent("meta.json")))
        let analysis = try JSONDecoder().decode(
            Analysis.self, from: Data(contentsOf: folder.appendingPathComponent("analysis.json")))
        let picks = try JSONDecoder().decode(
            [String: String].self, from: Data(contentsOf: folder.appendingPathComponent("picks.json")))
        let markdown = try String(
            contentsOf: folder.appendingPathComponent("document.md"), encoding: .utf8)
        return SavedDocument(meta: meta, analysis: analysis, picks: picks,
                             markdown: markdown, folder: folder)
    }

    func delete(id: String) throws {
        try FileManager.default.removeItem(at: folderURL(id: id))
    }
}
```

주의: `($0.createdAt, $0.id) > ($1.createdAt, $1.id)` 튜플 비교로 같은 초 저장도 순서 안정. Swift 6에서 `DateFormatter`는 지역 변수로만 사용(공유 안 함 — Sendable 문제 없음).

- [ ] **Step 4: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 커밋**

```bash
git add Sources/Services/DocumentStore.swift Tests/DocumentStoreTests.swift
git commit -m "feat: DocumentStore — 문서 폴더 저장·목록·재열람"
```

---

### Task 9: 스텁 서버 + AppModel 플로우 상태 머신 (링크 모드)

Gemini 키 없이 전체 플로우를 돌리기 위한 스텁 서버와, 진입→메타데이터→분석→문서 저장까지의 상태 머신. 이 태스크에서는 링크 모드 경로만 — 캡처 분기는 Task 11이 교체한다.

**Files:**
- Create: `scripts/stub-server.py`, `Sources/App/AppModel.swift`, `Tests/AppModelTests.swift`

**Interfaces:**
- Consumes: `PlayerBridge`(Task 1), `YouTubeURL`(Task 3), `MarkdownBuilder`(Task 5), `KeychainStore`/`Settings`(Task 6), `StepkeeperAPI`(Task 7), `DocumentStore`(Task 8)
- Produces: `FlowStage`(`.idle .loadingPlayer .readyToAnalyze(duration: Int, title: String) .analyzing(duration: Int) .capturing(current: Int, total: Int) .picking .building .done(DocumentMeta) .failed(String)`), `AppModel`(@MainActor @Observable) — `stage`, `bridge: PlayerBridge`, `detectedProfile: String`, `profileOverride: String?`, `autoContinue: Bool`, `start(urlString: String) async`, `confirmAnalyze() async`, `retry() async`, `reset()`, `documents() -> [DocumentMeta]`, `document(id: String) -> SavedDocument?`, `static detectProfile(title: String) -> String`, 내부 `performAnalysis(videoId: String, duration: Int) async`. Task 10~13이 사용.

- [ ] **Step 1: 스텁 서버 작성**

`scripts/stub-server.py`:

```python
#!/usr/bin/env python3
"""Gemini 없이 E2E를 돌리는 /v1/analyze 스텁 (stdlib only).
Tests/Fixtures/analyze-response.json을 돌려주되 video_id·duration은 요청값을 반영하고,
타임스탬프를 duration 안으로 클램프해 실영상 캡처 E2E에도 쓸 수 있게 한다.
사용: python3 scripts/stub-server.py [포트=8787]
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = json.loads(
    (ROOT / "Tests" / "Fixtures" / "analyze-response.json").read_text(encoding="utf-8"))
VIDEO_ID = re.compile(r"(?:v=|youtu\.be/|shorts/)([\w-]{11})")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/analyze":
            return self._send(404, {"detail": "not found"})
        if not self.headers.get("X-Gemini-Key"):
            return self._send(401, {"detail": "X-Gemini-Key 헤더가 필요합니다."})
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        match = VIDEO_ID.search(body.get("url", ""))
        duration = body.get("duration")
        if not match or not duration:
            return self._send(422, {"detail": "url 또는 duration 확인"})
        reply = json.loads(json.dumps(FIXTURE, ensure_ascii=False))
        reply["video_id"] = match.group(1)
        analysis = reply["analysis"]
        analysis["_duration"] = duration
        for step in analysis["steps"]:
            step["t_start"] = min(step["t_start"], max(0, duration - 10))
            step["t_end"] = min(step["t_end"], max(1, duration - 2))
        for guide in analysis["visual_guides"]:
            if guide["best_visual_timestamp"] is not None:
                guide["best_visual_timestamp"] = min(
                    guide["best_visual_timestamp"], max(1, duration - 5))
        self._send(200, reply)

    def do_GET(self):
        if self.path == "/healthz":
            self._send(200, {"status": "stub"})
        else:
            self._send(404, {"detail": "not found"})

    def _send(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print("[stub]", fmt % args)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    print(f"stub stepkeeper-server on http://127.0.0.1:{port}")
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
```

동작 확인:

```bash
python3 scripts/stub-server.py 8788 &
sleep 1
curl -s -X POST http://127.0.0.1:8788/v1/analyze -H 'X-Gemini-Key: k' -H 'Content-Type: application/json' \
  -d '{"url":"https://youtu.be/4ioPBiTWm3M","duration":120,"profile":"generic","language":"ko","max_guides":5}' | python3 -m json.tool | head -5
kill %1
```

Expected: `"video_id": "4ioPBiTWm3M"` 포함 200 응답.

- [ ] **Step 2: 실패하는 AppModel 테스트 작성**

`Tests/AppModelTests.swift` (URLProtocol 스텁 재사용 — Task 7의 `StubURLProtocol`은 같은 테스트 모듈이라 그대로 사용 가능. static 상태 공유하므로 이 스위트도 `.serialized`):

```swift
import Testing
import Foundation
@testable import stepkeeper

@Suite(.serialized)
@MainActor
struct AppModelTests {
    private func makeModel(root: URL, linkMode: Bool = false) -> AppModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let keychain = KeychainStore(service: "stepkeeper.tests.appmodel-\(UUID().uuidString)")
        try? keychain.save("test-key")
        let defaults = UserDefaults(suiteName: "stepkeeper.tests.appmodel")!
        defaults.removePersistentDomain(forName: "stepkeeper.tests.appmodel")
        Settings.registerDefaults(defaults)
        defaults.set(linkMode, forKey: Settings.linkModeKey)
        return AppModel(
            keychain: keychain,
            documentStore: DocumentStore(root: root),
            defaults: defaults,
            makeAPI: { StepkeeperAPI(baseURL: $0, session: session) })
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
        StubURLProtocol.handler = { _ in (200, fixture) }
        defer { StubURLProtocol.handler = nil }

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
        StubURLProtocol.handler = { _ in (429, Data(#"{"detail": "quota"}"#.utf8)) }
        defer { StubURLProtocol.handler = nil }

        await model.performAnalysis(videoId: "dQw4w9WgXcQ", duration: 90)

        guard case .failed(let message) = model.stage else {
            Issue.record("stage=\(model.stage)"); return
        }
        #expect(message.contains("한도"))
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
}
```

참고: 링크 모드 여부와 무관하게 이 태스크의 `performAnalysis`는 항상 링크 문서를 만든다(Task 11이 캡처 분기로 교체). 테스트 기대값 `0:30` 링크는 fixture의 vg-1(ts=30) 기준.

- [ ] **Step 3: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'AppModel' in scope`.

- [ ] **Step 4: AppModel 구현**

`Sources/App/AppModel.swift`:

```swift
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

@MainActor @Observable
final class AppModel {
    var stage: FlowStage = .idle
    var detectedProfile = "generic"
    var profileOverride: String?
    /// E2E·공유 확장 진입처럼 사람이 확인 버튼을 누르지 않는 경로에서 readyToAnalyze를 자동 통과
    var autoContinue = false

    let bridge = PlayerBridge()

    private let keychain: KeychainStore
    private let store: DocumentStore
    private let defaults: UserDefaults
    private let makeAPI: (URL) -> StepkeeperAPI
    private var currentVideoId: String?
    private var currentURLString: String?
    private var pendingDuration: Int?
    /// reset() 시 증가 — 취소 뒤 도착한 비동기 결과가 stage를 덮어쓰지 않게 한다
    private var generation = 0

    init(keychain: KeychainStore = .geminiKey,
         documentStore: DocumentStore? = nil,
         defaults: UserDefaults = .standard,
         makeAPI: @escaping (URL) -> StepkeeperAPI = { StepkeeperAPI(baseURL: $0) }) {
        self.keychain = keychain
        self.store = documentStore
            ?? ((try? DocumentStore.defaultRoot()).map(DocumentStore.init)
                ?? DocumentStore(root: FileManager.default.temporaryDirectory))
        self.defaults = defaults
        self.makeAPI = makeAPI
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
        guard let videoId = YouTubeURL.videoID(from: urlString) else {
            stage = .failed("유튜브 URL이 아닙니다 — watch/youtu.be/shorts 링크를 붙여넣어 주세요")
            return
        }
        guard let key = try? keychain.load(), !key.isEmpty else {
            stage = .failed("설정에서 Gemini API 키를 입력하세요")
            return
        }
        currentVideoId = videoId
        currentURLString = urlString
        let gen = generation
        stage = .loadingPlayer
        bridge.load(videoID: videoId)
        do {
            let meta = try await bridge.waitForMetadata()
            guard gen == generation else { return }   // 취소됨
            detectedProfile = Self.detectProfile(title: meta.title)
            pendingDuration = meta.duration
            stage = .readyToAnalyze(duration: meta.duration, title: meta.title)
            if autoContinue { await confirmAnalyze() }
        } catch {
            guard gen == generation else { return }
            stage = .failed((error as? PlayerError)?.errorDescription
                            ?? "플레이어 로드에 실패했습니다 — 다시 시도해 주세요")
        }
    }

    func confirmAnalyze() async {
        guard let videoId = currentVideoId, let duration = pendingDuration else { return }
        await performAnalysis(videoId: videoId, duration: duration)
    }

    /// 분석 → (Task 11 전까지는 항상) 링크 문서 저장
    func performAnalysis(videoId: String, duration: Int) async {
        guard let key = try? keychain.load(), !key.isEmpty else {
            stage = .failed("설정에서 Gemini API 키를 입력하세요")
            return
        }
        guard let serverURL = URL(string: defaults.string(forKey: Settings.serverURLKey)
                                  ?? Settings.defaultServerURL) else {
            stage = .failed("서버 URL이 올바르지 않습니다 — 설정을 확인하세요")
            return
        }
        let gen = generation
        stage = .analyzing(duration: duration)
        do {
            let result = try await makeAPI(serverURL).analyze(
                videoURL: "https://m.youtube.com/watch?v=\(videoId)",
                profile: profile,
                language: defaults.string(forKey: Settings.languageKey) ?? Settings.defaultLanguage,
                duration: duration,
                geminiKey: key)
            guard gen == generation else { return }   // 취소됨
            // 링크 모드(및 Task 11 전 기본 경로): 캡처 없이 링크 문서
            await buildDocument(result: result, picks: [:], images: [:])
        } catch {
            guard gen == generation else { return }
            stage = .failed((error as? LocalizedError)?.errorDescription
                            ?? "분석에 실패했습니다 — 다시 시도해 주세요")
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
            stage = .failed("문서 저장에 실패했습니다 — \(error.localizedDescription)")
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
    }
}
```

- [ ] **Step 5: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: 커밋**

```bash
git add scripts/stub-server.py Sources/App/AppModel.swift Tests/AppModelTests.swift
git commit -m "feat: AppModel 플로우 상태 머신 (링크 모드) + 스텁 서버"
```

---

### Task 10: 화면 4종 + M1 링크 모드 E2E (체크포인트)

**Files:**
- Create: `Sources/Views/HomeView.swift`, `Sources/Views/AnalyzeFlowView.swift`, `Sources/Views/DocumentView.swift`, `Sources/Views/SettingsView.swift`, `Sources/Views/Support.swift`, `scripts/e2e-m1.sh`
- Modify: `Sources/ContentView.swift`(루트 재구성), `Sources/App/StepkeeperApp.swift`(Settings.registerDefaults)

**Interfaces:**
- Consumes: `AppModel`/`FlowStage`(Task 9), `DocumentStore`·`SavedDocument`(Task 8), `Settings`/`KeychainStore`(Task 6), `MarkdownBuilder.hms`(Task 5), `PlayerWebView`(Task 1)
- Produces: `HomeView(model:)`, `AnalyzeFlowView(model:)`, `DocumentView(document: SavedDocument)`, `SettingsView()`, `Pasteboard.string`, `LocalImage(url:)`, `ExportHelper.copyFolder(from:to:name:) -> String?`. DEBUG 훅: 환경변수 `STEPKEEPER_E2E_URL` 자동 플로우(Task 12·13 E2E도 재사용).

- [ ] **Step 1: 지원 유틸 작성**

`Sources/Views/Support.swift`:

```swift
import SwiftUI

enum Pasteboard {
    @MainActor static var string: String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }
}

/// 로컬 파일 이미지 (문서 폴더의 vg-N.jpg)
struct LocalImage: View {
    let url: URL
    var body: some View {
        #if os(macOS)
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #else
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #endif
    }
}

enum ExportHelper {
    /// 문서 폴더를 사용자가 고른 디렉토리 아래 <name>/으로 복사. 성공 시 nil, 실패 시 메시지.
    static func copyFolder(from source: URL, to directory: URL, name: String) -> String? {
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
        do {
            let destination = directory.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return nil
        } catch {
            return "저장 실패: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: SettingsView 작성**

`Sources/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.serverURLKey) private var serverURL = Settings.defaultServerURL
    @AppStorage(Settings.languageKey) private var language = Settings.defaultLanguage
    @AppStorage(Settings.linkModeKey) private var linkMode = false
    @State private var geminiKey = ""
    @State private var keySavedAt: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("AI Studio에서 발급한 키", text: $geminiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("키 저장") {
                        try? KeychainStore.geminiKey.save(
                            geminiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        keySavedAt = Date()
                    }
                    .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if keySavedAt != nil {
                        Label("저장됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    }
                    Link("AI Studio에서 무료 키 발급 (카드 불필요)",
                         destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.callout)
                } header: { Text("Gemini API 키") } footer: {
                    Text("키는 이 기기의 Keychain에만 저장되고 분석 요청에만 사용됩니다.")
                }
                Section("분석") {
                    Picker("문서 언어", selection: $language) {
                        Text("한국어").tag("ko")
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                    }
                    Toggle("링크 모드", isOn: $linkMode)
                    Text("링크 모드: 화면 캡처 없이 모든 가이드를 유튜브 타임스탬프 링크로 넣습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    TextField("서버 URL", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } header: { Text("stepkeeper 서버") } footer: {
                    Text("실기기에서는 Mac의 LAN IP를 입력하세요 (예: http://192.168.0.10:8787)")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("설정")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .onAppear { geminiKey = (try? KeychainStore.geminiKey.load()) ?? "" }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}
```

- [ ] **Step 3: HomeView + AnalyzeFlowView 작성**

`Sources/Views/HomeView.swift`:

```swift
import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel
    @State private var urlText = ""
    @State private var documents: [DocumentMeta] = []
    @State private var hasKey = false
    @State private var showSettings = false
    @State private var flowActive = false

    var body: some View {
        List {
            if !hasKey {
                Section {
                    Button {
                        showSettings = true
                    } label: {
                        Label("먼저 설정에서 Gemini API 키를 입력하세요", systemImage: "key.fill")
                    }
                    .foregroundStyle(.orange)
                }
            }
            Section("새 문서") {
                TextField("유튜브 URL", text: $urlText)
                    .autocorrectionDisabled()
                HStack {
                    Button("붙여넣기") { if let s = Pasteboard.string { urlText = s } }
                    Spacer()
                    Button("문서 만들기") {
                        flowActive = true
                        Task { await model.start(urlString: urlText) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(YouTubeURL.videoID(from: urlText) == nil)
                }
            }
            Section("최근 문서") {
                if documents.isEmpty {
                    Text("아직 만든 문서가 없습니다").foregroundStyle(.secondary)
                }
                ForEach(documents) { meta in
                    NavigationLink(value: meta.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meta.title).lineLimit(1)
                            Text(meta.createdAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet { model.deleteDocument(id: documents[index].id) }
                    documents = model.documents()
                }
            }
        }
        .navigationTitle("stepkeeper")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: refresh) { SettingsView() }
        .navigationDestination(isPresented: $flowActive) { AnalyzeFlowView(model: model) }
        .navigationDestination(for: String.self) { id in
            if let doc = model.document(id: id) {
                DocumentView(document: doc)
            } else {
                Text("문서를 열 수 없습니다")
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: model.stage) { _, newStage in
            if case .loadingPlayer = newStage { flowActive = true }   // E2E·공유 진입 자동 표시
            if case .done = newStage { documents = model.documents() }
        }
    }

    private func refresh() {
        documents = model.documents()
        hasKey = ((try? KeychainStore.geminiKey.load()) ?? "").isEmpty == false
    }
}
```

`Sources/Views/AnalyzeFlowView.swift`:

```swift
import SwiftUI

struct AnalyzeFlowView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            PlayerWebView(bridge: model.bridge)
                .frame(minHeight: 230)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            stageView
            Spacer()
        }
        .padding()
        .navigationTitle("분석")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { model.reset(); dismiss() }
            }
        }
    }

    @ViewBuilder private var stageView: some View {
        switch model.stage {
        case .idle:
            Text("대기 중").foregroundStyle(.secondary)
        case .loadingPlayer:
            ProgressView("플레이어 로드 중…")
        case .readyToAnalyze(let duration, let title):
            VStack(spacing: 10) {
                Text(title).font(.callout).lineLimit(2)
                Text("길이 \(MarkdownBuilder.hms(duration))").font(.caption).foregroundStyle(.secondary)
                Picker("프로파일", selection: Binding(
                    get: { model.profileOverride ?? model.detectedProfile },
                    set: { model.profileOverride = $0 })) {
                    Text("일반").tag("generic")
                    Text("요리").tag("recipe")
                }
                .pickerStyle(.segmented)
                Button("분석 시작") { Task { await model.confirmAnalyze() } }
                    .buttonStyle(.borderedProminent)
            }
        case .analyzing(let duration):
            ProgressView("영상 분석 중… (\(MarkdownBuilder.hms(duration)), \(model.profile))")
        case .capturing(let current, let total):
            ProgressView("장면 캡처 중… \(current)/\(total)")
        case .picking:
            Text("장면 선택 대기").foregroundStyle(.secondary)   // Task 12에서 픽커 표시로 교체
        case .building:
            ProgressView("문서 생성 중…")
        case .done(let meta):
            VStack(spacing: 10) {
                Label("완료", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                NavigationLink("문서 보기", value: meta.id)
                    .buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            VStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout)
                    .multilineTextAlignment(.center)
                Button("다시 시도") { Task { await model.retry() } }
            }
        }
    }
}
```

- [ ] **Step 4: DocumentView 작성 (모델 기반 네이티브 렌더)**

`Sources/Views/DocumentView.swift`:

```swift
import SwiftUI

struct DocumentView: View {
    let document: SavedDocument
    @State private var pickingFolder = false
    @State private var exportMessage: String?

    private var analysis: Analysis { document.analysis }
    private var isRecipe: Bool { document.meta.profile == "recipe" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(isRecipe ? "🍳" : "📋") \(analysis.title)").font(.title2.bold())
                Text(analysis.summary).foregroundStyle(.secondary)
                if !isRecipe, let category = analysis.category, !category.isEmpty {
                    Text("**분류:** \(category)")
                }
                Text(isRecipe
                     ? "■ 준비 재료\(analysis.servings.map { " (\($0))" } ?? "")"
                     : "■ 준비물").font(.headline)
                ForEach(analysis.materials, id: \.name) { material in
                    Text("• \(material.name) \(material.amount)")
                }
                Text(isRecipe ? "■ 조리 순서" : "■ 순서").font(.headline)
                ForEach(analysis.steps, id: \.id) { step in
                    stepSection(step)
                }
                Divider()
                Link("출처: \(analysis.title) — stepkeeper로 생성",
                     destination: URL(string: "https://youtu.be/\(document.meta.videoId)")!)
                    .font(.footnote)
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding()
        }
        .navigationTitle(analysis.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(items: shareItems) { Label("공유", systemImage: "square.and.arrow.up") }
                Button { pickingFolder = true } label: {
                    Label("폴더로 저장", systemImage: "folder")
                }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let directory) = result {
                exportMessage = ExportHelper.copyFolder(
                    from: document.folder, to: directory, name: document.meta.id)
                    ?? "저장 완료: \(directory.lastPathComponent)/\(document.meta.id)"
            }
        }
    }

    @ViewBuilder private func stepSection(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(step.id). \(step.summary)").font(.body.bold())
            Text(step.detail)
            ForEach(analysis.visualGuides.filter { $0.stepId == step.id }, id: \.id) { guide in
                guideRow(guide)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private func guideRow(_ guide: VisualGuide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("💡 *'\(guide.phrase)' 기준:* \(guide.guideText)")
                .font(.callout)
            let imageURL = document.folder.appendingPathComponent("\(guide.id).jpg")
            if let pick = document.picks[guide.id], pick != "none",
               FileManager.default.fileExists(atPath: imageURL.path) {
                LocalImage(url: imageURL).frame(maxHeight: 240)
            } else if let ts = guide.bestVisualTimestamp {
                Link("▶ 영상 \(MarkdownBuilder.hms(ts))에서 직접 확인",
                     destination: URL(string: "https://youtu.be/\(document.meta.videoId)?t=\(ts)")!)
                    .font(.callout)
            }
        }
        .padding(.leading, 12)
    }

    private var shareItems: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: document.folder, includingPropertiesForKeys: nil)) ?? []
        let md = files.filter { $0.pathExtension == "md" }
        let jpgs = files.filter { $0.pathExtension == "jpg" }.sorted { $0.path < $1.path }
        return md + jpgs
    }
}
```

- [ ] **Step 5: 루트 재구성 + E2E 훅**

`Sources/ContentView.swift` 전체 교체:

```swift
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationStack {
            HomeView(model: model)
        }
        .task {
            #if DEBUG
            if let url = ProcessInfo.processInfo.environment["STEPKEEPER_E2E_URL"] {
                try? KeychainStore.geminiKey.save("e2e-stub-key")
                model.autoContinue = true
                await model.start(urlString: url)
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
}
```

주의: E2E 링크 모드는 스크립트가 `SIMCTL_CHILD_STEPKEEPER_LINK_MODE=1`로 켠다 — 훅에서:

```swift
                if ProcessInfo.processInfo.environment["STEPKEEPER_LINK_MODE"] == "1" {
                    UserDefaults.standard.set(true, forKey: Settings.linkModeKey)
                }
```

(`model.autoContinue = true` 줄 바로 위에 추가. Task 12의 캡처 E2E는 이 변수 없이 실행해 캡처 경로를 태운다.)

`Sources/App/StepkeeperApp.swift`의 `StepkeeperApp`에 init 추가:

```swift
    init() {
        Settings.registerDefaults()
    }
```

기존 `#if DEBUG` 스파이크 분기는 유지. `ContentView`의 스파이크 NavigationLink는 HomeView로 대체됐으므로 제거된 상태여도 무방(스파이크 진입은 환경변수 경로만 유지).

- [ ] **Step 6: 빌드 (양 플랫폼)**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```

Expected: 둘 다 `BUILD SUCCEEDED`.

- [ ] **Step 7: M1 E2E 스크립트 작성·실행**

`scripts/e2e-m1.sh`:

```bash
#!/bin/bash
# M1 E2E: 스텁 서버 + 시뮬레이터 + 실제 유튜브 플레이어(메타데이터) → 링크 모드 문서 생성 검증
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
SIM="iPhone 17 Pro"
BUNDLE=com.stepkeeper.app
URL="https://www.youtube.com/watch?v=4ioPBiTWm3M"

python3 scripts/stub-server.py 8787 &
STUB=$!
trap 'kill $STUB 2>/dev/null || true' EXIT
sleep 1

xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build | tail -2
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/stepkeeper.app
xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null || true
CONTAINER=$(xcrun simctl get_app_container "$SIM" $BUNDLE data)
rm -rf "$CONTAINER/Documents/stepkeeper"

SIMCTL_CHILD_STEPKEEPER_E2E_URL="$URL" SIMCTL_CHILD_STEPKEEPER_LINK_MODE=1 \
  xcrun simctl launch "$SIM" $BUNDLE

DOC=""
for i in $(seq 1 60); do
  DOC=$(ls "$CONTAINER"/Documents/stepkeeper/*/document.md 2>/dev/null | head -1) && [ -n "$DOC" ] && break
  sleep 2
done
[ -n "$DOC" ] || { echo "M1 E2E FAIL: document.md not produced"; exit 1; }
echo "--- document.md ---"
cat "$DOC"
grep -q "▶ \[영상" "$DOC" || { echo "M1 E2E FAIL: no link fallback"; exit 1; }
grep -q "stepkeeper로 생성" "$DOC" || { echo "M1 E2E FAIL: no footer"; exit 1; }
ls "$(dirname "$DOC")" | grep -q "analysis.json" || { echo "M1 E2E FAIL: no analysis.json"; exit 1; }
xcrun simctl io "$SIM" screenshot build/m1-screenshot.png >/dev/null 2>&1 || true
echo "M1 E2E PASS"
```

```bash
chmod +x scripts/e2e-m1.sh && ./scripts/e2e-m1.sh
```

Expected: `M1 E2E PASS` + document.md 내용 출력(제목·준비물·▶ 링크·출처 푸터). 실패 시 흔한 원인: 시뮬레이터에서 127.0.0.1은 호스트 Mac을 가리키므로 스텁 도달은 되어야 함 — 안 되면 ATS(`NSAllowsLocalNetworking`)와 스텁 기동 로그 확인. 메타데이터 타임아웃이면 M0 스파이크에서 검증된 설정과 차이를 비교.

- [ ] **Step 8: macOS 스모크 (수동 실행 1회)**

```bash
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' -derivedDataPath build build | tail -2
open build/Build/Products/Debug/stepkeeper.app
```

확인: 홈 화면 표시, 설정 시트 열림(키 저장 동작), URL 붙여넣기 버튼 동작. (전체 플로우는 시뮬레이터 E2E로 이미 검증 — macOS 상세 검증은 Task 14)

- [ ] **Step 9: 커밋 (체크포인트: M1 보고)**

```bash
git add Sources scripts project.yml
git commit -m "feat: 화면 4종(홈·분석·문서·설정) + M1 링크 모드 E2E"
```

**사용자에게 M1 결과 보고** (document.md 내용 + 스크린샷 경로 build/m1-screenshot.png).

---

### Task 11: 캡처 파이프라인 — 세션 상태 저장·복원 + 가이드×3슬롯 캡처

**Files:**
- Modify: `Sources/Capture/CaptureScript.swift`(captureBegin/captureEnd 추가), `Sources/Capture/PlayerBridge.swift`(세션 메서드), `Sources/App/AppModel.swift`(캡처 분기)
- Create: `Tests/CapturePipelineTests.swift`

**Interfaces:**
- Consumes: `CandidateTimes`(Task 3), `AnalyzeResult`(Task 7), `PlayerBridge.captureFrame(at:)`(Task 1)
- Produces: `CaptureCandidate(slot: String, time: Int, jpeg: Data?)`, `GuideCapture(guide: VisualGuide, candidates: [CaptureCandidate])`(`Identifiable`, `failed: Bool`), `AppModel.captures: [GuideCapture]`, `AppModel.finishPicking(picks: [String: String]) async`, `AppModel.defaultPicks() -> [String: String]`(center 있으면 center, 아니면 none), `PlayerBridge.beginCaptureSession() async throws` / `endCaptureSession() async`. Task 12가 사용. `performAnalysis`는 링크 모드 OFF일 때 `captureCandidates(result:)`로 분기하도록 교체. (Task 9의 링크모드 테스트는 `linkMode: true`로 모델을 만들므로 분기 추가 후에도 그린 유지)

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/CapturePipelineTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

@MainActor
struct CapturePipelineTests {
    private func makeModel(root: URL) -> AppModel {
        let keychain = KeychainStore(service: "stepkeeper.tests.capture-\(UUID().uuidString)")
        try? keychain.save("test-key")
        let defaults = UserDefaults(suiteName: "stepkeeper.tests.capture")!
        defaults.removePersistentDomain(forName: "stepkeeper.tests.capture")
        Settings.registerDefaults(defaults)
        return AppModel(keychain: keychain, documentStore: DocumentStore(root: root),
                        defaults: defaults)
    }
    private func makeResult() throws -> AnalyzeResult {
        let data = try Bundle.fixtureData("analyze-response")
        let envelope = try JSONDecoder().decode(AnalyzeEnvelope.self, from: data)
        let raw = try JSONSerialization.data(withJSONObject:
            (try JSONSerialization.jsonObject(with: data) as! [String: Any])["analysis"]!)
        return AnalyzeResult(videoId: envelope.videoId,
                             analysis: envelope.analysis, rawAnalysis: raw)
    }
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])

    @Test func defaultPicksPrefersCenterElseNone() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let result = try makeResult()
        let vg1 = result.analysis.visualGuides[0]   // vg-1
        let vg2 = result.analysis.visualGuides[1]   // vg-2 — center 실패 케이스로 사용
        model.captures = [
            GuideCapture(guide: vg1, candidates: [
                CaptureCandidate(slot: "before", time: 20, jpeg: jpeg),
                CaptureCandidate(slot: "center", time: 30, jpeg: jpeg),
                CaptureCandidate(slot: "after", time: 56, jpeg: jpeg),
            ]),
            GuideCapture(guide: vg2, candidates: [
                CaptureCandidate(slot: "before", time: 4, jpeg: nil),
                CaptureCandidate(slot: "center", time: 10, jpeg: nil),
                CaptureCandidate(slot: "after", time: 21, jpeg: nil),
            ]),
        ]
        let picks = model.defaultPicks()
        #expect(picks["vg-1"] == "center")
        #expect(picks["vg-2"] == "none")
    }

    @Test func finishPickingSavesPickedImageAndLinksOthers() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let result = try makeResult()
        model.pendingResult = result
        model.captures = [GuideCapture(guide: result.analysis.visualGuides[0], candidates: [
            CaptureCandidate(slot: "before", time: 20, jpeg: nil),
            CaptureCandidate(slot: "center", time: 30, jpeg: jpeg),
            CaptureCandidate(slot: "after", time: 56, jpeg: nil),
        ])]

        await model.finishPicking(picks: ["vg-1": "center"])

        guard case .done(let meta) = model.stage else {
            Issue.record("stage=\(model.stage)"); return
        }
        let doc = model.document(id: meta.id)!
        #expect(doc.markdown.contains("![요만큼](vg-1.jpg)"))
        #expect(doc.picks["vg-1"] == "center")
        let image = doc.folder.appendingPathComponent("vg-1.jpg")
        #expect(try Data(contentsOf: image) == jpeg)
        // vg-2는 timestamp null — 이미지도 ?t= 링크도 없어야 함 (골든과 동일 규칙)
        #expect(!doc.markdown.contains("vg-2.jpg"))
    }

    @Test func finishPickingWithNoneFallsBackToLink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let result = try makeResult()
        model.pendingResult = result
        model.captures = [GuideCapture(guide: result.analysis.visualGuides[0], candidates: [
            CaptureCandidate(slot: "center", time: 30, jpeg: jpeg),
        ])]

        await model.finishPicking(picks: ["vg-1": "none"])

        guard case .done(let meta) = model.stage else {
            Issue.record("stage=\(model.stage)"); return
        }
        let doc = model.document(id: meta.id)!
        #expect(doc.markdown.contains("▶ [영상 0:30에서 직접 확인](https://youtu.be/dQw4w9WgXcQ?t=30)"))
        #expect(!FileManager.default.fileExists(
            atPath: doc.folder.appendingPathComponent("vg-1.jpg").path))
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'GuideCapture' in scope`.

- [ ] **Step 3: capture.js에 세션 함수 추가**

`Sources/Capture/CaptureScript.swift`의 `window.__stepkeeper = { waitMeta, capture, prime };` 앞에 추가:

```js
      async function captureBegin() {   // content.js 패턴: 상태 저장 → 음소거·정지
        const v = video();
        if (!v) throw new Error("no player");
        window.__cnSaved = { muted: v.muted, paused: v.paused, t: v.currentTime };
        v.muted = true;
        try { await v.play(); } catch (e) {}
        await sleep(300);
        v.pause();
        return true;
      }
      async function captureEnd() {     // 원위치 복원
        const v = video();
        const s = window.__cnSaved;
        if (!v || !s) return false;
        v.currentTime = s.t;
        v.muted = s.muted;
        if (!s.paused) { try { await v.play(); } catch (e) {} }
        return true;
      }
```

그리고 마지막 줄을 다음으로 교체:

```js
      window.__stepkeeper = { waitMeta, capture, prime, captureBegin, captureEnd };
```

- [ ] **Step 4: PlayerBridge에 세션 메서드 추가**

`Sources/Capture/PlayerBridge.swift`의 `captureFrame(at:)` 아래에 추가:

```swift
    /// 캡처 세션 시작: 플레이어 상태 저장 후 음소거·정지 (프레임 디코딩 유도 포함)
    func beginCaptureSession() async throws {
        do {
            _ = try await callJS("return await window.__stepkeeper.captureBegin();", timeout: 8)
        } catch {
            throw PlayerError.captureFailed("세션 시작 실패: \(error)")
        }
    }

    /// 캡처 세션 종료: currentTime·muted·재생 상태 복원 (실패해도 무시)
    func endCaptureSession() async {
        _ = try? await callJS("return await window.__stepkeeper.captureEnd();", timeout: 5)
    }
```

- [ ] **Step 5: AppModel에 캡처 경로 구현**

`Sources/App/AppModel.swift` — 타입 2개를 파일 상단(`FlowStage` 아래)에 추가:

```swift
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
```

`AppModel`에 프로퍼티 추가(`private var pendingDuration` 근처):

```swift
    var captures: [GuideCapture] = []
    var pendingResult: AnalyzeResult?
```

`performAnalysis`의 `// 링크 모드(및 Task 11 전 기본 경로)...` 주석 줄과 바로 아래 `await buildDocument(...)` 한 줄을 다음으로 교체 (그 위의 `guard gen == generation` 줄은 유지):

```swift
            if linkMode {
                await buildDocument(result: result, picks: [:], images: [:])
            } else {
                await captureCandidates(result: result)
            }
```

`buildDocument` 아래에 추가:

```swift
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
```

`reset()`에 두 줄 추가:

```swift
        captures = []
        pendingResult = nil
```

- [ ] **Step 6: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: 커밋**

```bash
git add Sources/Capture Sources/App/AppModel.swift Tests/CapturePipelineTests.swift
git commit -m "feat: 캡처 파이프라인 — 세션 저장·복원 + 가이드 단위 폴백"
```

---

### Task 12: CandidatePickerView + M2 캡처 E2E (체크포인트)

**Files:**
- Create: `Sources/Views/CandidatePickerView.swift`, `scripts/e2e-m2.sh`
- Modify: `Sources/Views/AnalyzeFlowView.swift`(.picking 케이스 교체), `Sources/Views/Support.swift`(JPEGImage 추가)

**Interfaces:**
- Consumes: `AppModel.captures`/`finishPicking(picks:)`/`defaultPicks()`(Task 11), `MarkdownBuilder.hms`(Task 5)
- Produces: `CandidatePickerView(model:)`, `JPEGImage(data:)`.

- [ ] **Step 1: JPEGImage 추가**

`Sources/Views/Support.swift`에 추가:

```swift
/// 메모리 JPEG 썸네일 (후보 선택 UI)
struct JPEGImage: View {
    let data: Data
    var body: some View {
        #if os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
        }
        #else
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
        }
        #endif
    }
}
```

- [ ] **Step 2: CandidatePickerView 작성**

`Sources/Views/CandidatePickerView.swift`:

```swift
import SwiftUI

/// 스펙 5.3: 가이드별 3후보 + "부적합(링크 사용)", center 기본 선택. 자동 선택 없음(사용자 확정 필수).
struct CandidatePickerView: View {
    @Bindable var model: AppModel
    @State private var picks: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("가이드별로 의미가 가장 잘 보이는 장면을 고르세요")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(model.captures) { capture in
                    guideCard(capture)
                }
                Button("문서 만들기") {
                    Task { await model.finishPicking(picks: picks) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical)
        }
        .onAppear { if picks.isEmpty { picks = model.defaultPicks() } }
    }

    @ViewBuilder private func guideCard(_ capture: GuideCapture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(capture.guide.id) · \(capture.guide.phrase)").font(.headline)
            Text(capture.guide.guideText).font(.caption).foregroundStyle(.secondary)
            if capture.failed {
                Label("캡처 실패 — 링크로 대체됩니다", systemImage: "link")
                    .font(.callout).foregroundStyle(.orange)
            } else {
                HStack(spacing: 8) {
                    ForEach(capture.candidates, id: \.slot) { candidate in
                        candidateCell(guideId: capture.guide.id, candidate: candidate)
                    }
                    noneCell(guideId: capture.guide.id)
                }
            }
        }
    }

    @ViewBuilder private func candidateCell(guideId: String, candidate: CaptureCandidate) -> some View {
        if let jpeg = candidate.jpeg {
            Button {
                picks[guideId] = candidate.slot
            } label: {
                VStack(spacing: 4) {
                    JPEGImage(data: jpeg)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                            picks[guideId] == candidate.slot ? Color.red : Color.secondary.opacity(0.3),
                            lineWidth: picks[guideId] == candidate.slot ? 3 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("\(MarkdownBuilder.hms(candidate.time)) (\(candidate.slot))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func noneCell(guideId: String) -> some View {
        Button {
            picks[guideId] = "none"
        } label: {
            VStack {
                Text("부적합\n링크 사용").font(.caption).multilineTextAlignment(.center)
            }
            .frame(minWidth: 64, minHeight: 48)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                picks[guideId] == "none" ? Color.red : Color.secondary.opacity(0.3),
                lineWidth: picks[guideId] == "none" ? 3 : 1))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: AnalyzeFlowView의 .picking 케이스 교체**

`Sources/Views/AnalyzeFlowView.swift`에서:

```swift
        case .picking:
            Text("장면 선택 대기").foregroundStyle(.secondary)   // Task 12에서 픽커 표시로 교체
```

를 다음으로 교체:

```swift
        case .picking:
            CandidatePickerView(model: model)
```

- [ ] **Step 4: 빌드 + 단위 테스트 회귀**

```bash
xcodegen generate
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3
```

Expected: `** TEST SUCCEEDED **` / `BUILD SUCCEEDED`

- [ ] **Step 5: M2 E2E 스크립트 작성·실행**

`scripts/e2e-m2.sh` — M1과 동일하되 **링크 모드 없이** 실행해 캡처 경로를 태운다 (autoContinue가 center 자동 선택):

```bash
#!/bin/bash
# M2 E2E: 스텁 분석 + 실제 유튜브 캡처 → 이미지 포함 문서 생성 검증
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
SIM="iPhone 17 Pro"
BUNDLE=com.stepkeeper.app
URL="https://www.youtube.com/watch?v=4ioPBiTWm3M"

python3 scripts/stub-server.py 8787 &
STUB=$!
trap 'kill $STUB 2>/dev/null || true' EXIT
sleep 1

xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build build | tail -2
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/stepkeeper.app
xcrun simctl terminate "$SIM" $BUNDLE 2>/dev/null || true
CONTAINER=$(xcrun simctl get_app_container "$SIM" $BUNDLE data)
rm -rf "$CONTAINER/Documents/stepkeeper"

SIMCTL_CHILD_STEPKEEPER_E2E_URL="$URL" xcrun simctl launch "$SIM" $BUNDLE

DOC=""
for i in $(seq 1 90); do
  DOC=$(ls "$CONTAINER"/Documents/stepkeeper/*/document.md 2>/dev/null | head -1) && [ -n "$DOC" ] && break
  sleep 2
done
[ -n "$DOC" ] || { echo "M2 E2E FAIL: document.md not produced"; exit 1; }
DIR=$(dirname "$DOC")
echo "--- document.md ---"
cat "$DOC"
grep -q '!\[요만큼\](vg-1.jpg)' "$DOC" || { echo "M2 E2E FAIL: no embedded image line"; exit 1; }
[ -f "$DIR/vg-1.jpg" ] || { echo "M2 E2E FAIL: vg-1.jpg missing"; exit 1; }
SIZE=$(stat -f%z "$DIR/vg-1.jpg")
[ "$SIZE" -gt 5000 ] || { echo "M2 E2E FAIL: vg-1.jpg too small ($SIZE bytes)"; exit 1; }
xcrun simctl io "$SIM" screenshot build/m2-screenshot.png >/dev/null 2>&1 || true
echo "M2 E2E PASS (image $SIZE bytes)"
```

```bash
chmod +x scripts/e2e-m2.sh && ./scripts/e2e-m2.sh
```

Expected: `M2 E2E PASS`. 실패 시: 캡처 타임아웃이면 M0 spike-capture.md의 우회책과 대조, 이미지가 너무 작으면(순흑) prime/대기시간 조정.

- [ ] **Step 6: 픽커 수동 확인 안내 준비 + 커밋 (체크포인트: M2 보고)**

수동 확인(사용자용, 보고에 포함): 시뮬레이터에서 앱 실행 → 키 저장(스텁이면 아무 값) → URL 붙여넣기 → 분석 시작 → 3후보+부적합 UI에서 선택 변경 → 문서 만들기 → 이미지 반영 확인.

```bash
git add Sources scripts
git commit -m "feat: 후보 선택 UI + M2 캡처 E2E"
```

**사용자에게 M2 결과 보고** (document.md + vg-1.jpg 크기 + 스크린샷).

---

### Task 13: iOS 공유 확장 + App Group 인박스

**Files:**
- Create: `ShareExtension/ShareViewController.swift`, `Sources/App/ShareInbox.swift`, `Sources/Stepkeeper-iOS.entitlements`, `ShareExtension/StepkeeperShare.entitlements`, `Tests/ShareInboxTests.swift`
- Modify: `project.yml`(StepkeeperShare 타깃 + 의존성 + iOS 엔타이틀먼트), `Sources/ContentView.swift`(scenePhase 픽업)

**Interfaces:**
- Consumes: `YouTubeURL`(Task 3 — 확장 타깃에도 파일 포함), `AppModel.start`(Task 9)
- Produces: `ShareInbox.push(_ url: String)` / `pop() -> String?` (App Group `group.com.stepkeeper.shared`, key `pendingURL`).

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/ShareInboxTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct ShareInboxTests {
    @Test func pushPopRoundTripAndDrain() {
        ShareInbox.defaults?.removeObject(forKey: ShareInbox.urlKey)
        #expect(ShareInbox.pop() == nil)
        ShareInbox.push("https://youtu.be/4ioPBiTWm3M")
        #expect(ShareInbox.pop() == "https://youtu.be/4ioPBiTWm3M")
        #expect(ShareInbox.pop() == nil)   // 소비 후 비어야 함
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 컴파일 실패 — `cannot find 'ShareInbox' in scope`.

- [ ] **Step 3: ShareInbox + 엔타이틀먼트 + project.yml**

`Sources/App/ShareInbox.swift`:

```swift
import Foundation

/// 공유 확장 → 본체 앱 URL 전달 (스펙 4.7). 확장은 push만, 앱은 활성화 시 pop.
enum ShareInbox {
    static let groupID = "group.com.stepkeeper.shared"
    static let urlKey = "pendingURL"

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func push(_ url: String) {
        defaults?.set(url, forKey: urlKey)
    }

    static func pop() -> String? {
        guard let defaults, let url = defaults.string(forKey: urlKey) else { return nil }
        defaults.removeObject(forKey: urlKey)
        return url
    }
}
```

`Sources/Stepkeeper-iOS.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.stepkeeper.shared</string>
	</array>
</dict>
</plist>
```

`ShareExtension/StepkeeperShare.entitlements` — 동일 내용으로 생성.

`project.yml` 변경 3곳:

① Stepkeeper 타깃 settings.base에 추가:

```yaml
        "CODE_SIGN_ENTITLEMENTS[sdk=iphone*]": Sources/Stepkeeper-iOS.entitlements
```

② Stepkeeper 타깃에 의존성 추가:

```yaml
    dependencies:
      - target: StepkeeperShare
        platformFilter: iOS
```

③ targets에 추가:

```yaml
  StepkeeperShare:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - ShareExtension
      - Sources/Models/YouTubeURL.swift
    info:
      path: ShareExtension/Info.plist
      properties:
        CFBundleDisplayName: stepkeeper
        NSExtension:
          NSExtensionPointIdentifier: com.apple.share-services
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ShareViewController
          NSExtensionAttributes:
            NSExtensionActivationRule:
              NSExtensionActivationSupportsWebURLWithMaxCount: 1
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.stepkeeper.app.share
        SWIFT_VERSION: "6.0"
        CODE_SIGN_ENTITLEMENTS: ShareExtension/StepkeeperShare.entitlements
```

- [ ] **Step 4: ShareViewController 작성**

`ShareExtension/ShareViewController.swift` (확장 안에서는 ShareInbox를 import할 수 없으므로 — 본체 모듈 — App Group 쓰기를 직접 한다. 키 문자열은 ShareInbox와 동일해야 함):

```swift
import UIKit
import UniformTypeIdentifiers

/// 유튜브 공유 → URL을 App Group에 저장하고 안내 후 닫힘 (스펙 4.7).
final class ShareViewController: UIViewController {
    private let groupID = "group.com.stepkeeper.shared"
    private let urlKey = "pendingURL"
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "확인 중…"
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        handleAttachment()
    }

    private func handleAttachment() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments).flatMap { $0 } ?? []
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) else {
            finish("URL을 찾지 못했습니다")
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] value, _ in
            let urlString = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
            DispatchQueue.main.async {
                guard YouTubeURL.videoID(from: urlString) != nil else {
                    self?.finish("유튜브 영상 링크가 아닙니다")
                    return
                }
                UserDefaults(suiteName: self?.groupID ?? "")?
                    .set(urlString, forKey: self?.urlKey ?? "pendingURL")
                self?.finish("저장됐습니다.\nstepkeeper를 열면 분석이 시작됩니다.")
            }
        }
    }

    private func finish(_ message: String) {
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
```

- [ ] **Step 5: 본체 앱 픽업 (scenePhase)**

`Sources/ContentView.swift`의 `ContentView`에 추가:

```swift
    @Environment(\.scenePhase) private var scenePhase
```

`.task { ... }` 아래에 추가:

```swift
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let url = ShareInbox.pop() {
                model.autoContinue = false
                Task { await model.start(urlString: url) }
            }
        }
```

- [ ] **Step 6: 테스트 + 빌드 + 확장 임베드 확인**

```bash
xcodegen generate
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build 2>&1 | tail -3
ls build/Build/Products/Debug-iphonesimulator/stepkeeper.app/PlugIns/
```

Expected: 테스트 그린, iOS 빌드 성공, `PlugIns/` 안에 `StepkeeperShare.appex` 존재. (macOS 테스트에서 ShareInbox suiteName은 일반 도메인으로 동작 — App Group 미서명 환경에서도 통과)

수동 확인(시뮬레이터): `xcrun simctl openurl booted "https://m.youtube.com/watch?v=4ioPBiTWm3M"` → Safari 공유 버튼 → stepkeeper 선택 → 앱 열기 → 자동 분석 시작. (이 확인은 사용자 M4 체크리스트에도 포함)

- [ ] **Step 7: 커밋**

```bash
git add project.yml ShareExtension Sources Tests
git commit -m "feat: iOS 공유 확장 + App Group 인박스"
```

---

### Task 14: M4 폴리시 — macOS 마감 + 문서화 (최종 체크포인트)

**Files:**
- Create: `Sources/Stepkeeper-macOS.entitlements`, `docs/TESTING.md`, `README.md`
- Modify: `project.yml`(macOS 엔타이틀먼트), 검증 중 발견되는 macOS 이슈 수정

**Interfaces:** 없음 (마감 태스크)

- [ ] **Step 1: macOS 샌드박스 엔타이틀먼트**

`Sources/Stepkeeper-macOS.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
</dict>
</plist>
```

`project.yml` Stepkeeper settings.base에 추가:

```yaml
        "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": Sources/Stepkeeper-macOS.entitlements
```

- [ ] **Step 2: macOS 전수 검증 + 이슈 수정**

```bash
xcodegen generate
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test 2>&1 | tail -5
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' -derivedDataPath build build | tail -2
python3 scripts/stub-server.py 8787 &
open build/Build/Products/Debug/stepkeeper.app
```

확인 항목(각각 실패 시 수정 후 재확인): ①설정 키 저장/재열람 ②URL 붙여넣기→분석 시작→플레이어 표시 ③readyToAnalyze 세그먼트 ④링크 모드 문서 생성 ⑤캡처 경로(링크 모드 OFF) — M0에서 검증된 방식 ⑥문서 뷰 렌더 + 공유 + 폴더로 저장(샌드박스에서 fileImporter 동작) ⑦최근 문서 목록·삭제. 완료 후 `kill %1`.

- [ ] **Step 3: 시뮬레이터 회귀**

```bash
./scripts/e2e-m1.sh && ./scripts/e2e-m2.sh
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5
```

Expected: 두 E2E PASS + `** TEST SUCCEEDED **`

- [ ] **Step 4: TESTING.md 작성**

`docs/TESTING.md` — 수동 E2E 체크리스트 (stepkeeper-extension/TESTING.md 스타일):

```markdown
# stepkeeper-apple 수동 테스트 가이드

## 준비
- 로컬 서버: `cd ../stepkeeper-server && python app.py` (실분석) 또는 `python3 scripts/stub-server.py` (스텁)
- 실분석에는 본인 Gemini 키 필요 (AI Studio 무료 발급) — 앱 설정에 입력
- 시뮬레이터에서 서버 URL 기본값(127.0.0.1:8787) 그대로, 실기기는 Mac LAN IP로 변경

## 체크리스트
1. [ ] 설정: 키 저장 → 앱 재시작 후에도 유지 (Keychain)
2. [ ] 홈: 유튜브 URL 붙여넣기 → "문서 만들기" 활성화 (잘못된 URL이면 비활성)
3. [ ] 분석: 플레이어 표시 → 제목/길이 표시 → 프로파일 자동 감지(요리 영상이면 "요리") → 분석 시작
4. [ ] 후보 선택: 가이드마다 3장 + 부적합, center 기본 선택, 선택 변경 가능
5. [ ] 문서: 선택 이미지 표시, 부적합/실패 가이드는 ▶ 타임스탬프 링크
6. [ ] 내보내기: 공유시트에 md+jpg / "폴더로 저장" 후 Obsidian 등에서 열기
7. [ ] 링크 모드 ON: 캡처 없이 링크만으로 문서 생성
8. [ ] 공유 확장(iOS): Safari/유튜브 앱 공유 → stepkeeper → 앱 열면 자동 시작
9. [ ] 오류: 키 없이 시작(401 안내), 서버 끄고 시작(연결 안내), 잘못된 URL
10. [ ] macOS: 위 1~7 동일 동작

## 429(무료 한도) 재현
- 짧은 간격으로 분석 3회 이상 → "잠시 후 다시 시도" 안내 확인
```

- [ ] **Step 5: README.md 작성**

`README.md`:

```markdown
# stepkeeper-apple

영상을 문서로. 애매한 순간은 실제 화면으로.
유튜브 how-to 영상을 단계별 문서로 만들고, "한입 크기" 같은 애매한 표현마다
실제 프레임(사용자가 선택)이나 타임스탬프 링크를 첨부하는 SwiftUI 앱 (iOS/iPadOS/macOS).

[stepkeeper](https://github.com/zlej123/stepkeeper) 생태계의 Apple 클라이언트 —
분석은 [stepkeeper-server](https://github.com/zlej123/stepkeeper-server)(BYOK, 사용자 Gemini 키),
캡처는 앱의 WKWebView(영상 다운로드 없음), 문서 조립은 로컬(skill-core 템플릿 + 코어 렌더러 포팅).

## 개발

요구: Xcode 26+, XcodeGen(`brew install xcodegen`), Python 3.10+(스크립트)

    xcodegen generate                # project.yml → xcodeproj
    open stepkeeper-apple.xcodeproj

    # 테스트 (CLI, xcode-select가 CLT면 DEVELOPER_DIR 지정)
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test

    # E2E (스텁 서버 — Gemini 키 불필요)
    ./scripts/e2e-m1.sh              # 링크 모드
    ./scripts/e2e-m2.sh              # 실제 유튜브 캡처

## 스크립트
- `scripts/stub-server.py` — /v1/analyze 스텁 (fixture 응답)
- `scripts/sync-assets.sh` — ../stepkeeper skill-core 템플릿 재복사 (갱신 시 make-golden.py 재실행)
- `scripts/make-golden.py` — 코어 render.py로 골든 기대 출력 재생성
- `scripts/spike-verify.sh` — M0 캡처 검증

## 문서
- 설계: `docs/superpowers/specs/2026-07-17-stepkeeper-apple-v1-design.md`
- 캡처 스파이크 기록: `docs/spike-capture.md`
- 수동 테스트: `docs/TESTING.md`
```

- [ ] **Step 6: 최종 커밋 (최종 체크포인트: 사용자 보고 + 실키 E2E 안내)**

```bash
git add Sources project.yml docs README.md
git commit -m "chore: macOS 샌드박스 + TESTING/README (v1 마감)"
git log --oneline
```

**사용자 보고**: 전체 마일스톤 결과, 남은 사용자 액션 안내 — ①본인 Gemini 키로 실분석 E2E(TESTING.md 1~7), ②실기기 설치 시 Xcode에서 팀 서명, ③GitHub 리포 생성·푸시 여부 결정.

---

## 태스크 순서와 의존성

Task 1(M0 스파이크, **체크포인트**) → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10(M1, **체크포인트**) → 11 → 12(M2, **체크포인트**) → 13 → 14(M4, **최종**). 전부 직렬 — 각 태스크가 이전 태스크의 산출물을 소비한다. Task 2~9는 시뮬레이터 없이 macOS 데스티네이션 테스트만으로 진행 가능.

