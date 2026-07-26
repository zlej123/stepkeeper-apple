# M0 캡처 스파이크 — 실측 기록

WKWebView에서 유튜브 영상을 seek+canvas로 캡처할 수 있는지 검증한 스파이크의 실행 결과.
고정 영상 `4ioPBiTWm3M`(백종원 제육볶음 레시피, duration 415s)의 t=10/30/60s 프레임을
캡처해 JPEG로 저장하고, 각 프레임의 8x8 다운샘플 휘도 표준편차가 8을 넘는지(순흑/단색
프레임이 아닌지) 판정했다.

## 결론: iOS/macOS 모두 PASS

WebKit에서 seek 후 canvas로 유튜브 재생 화면을 캡처하는 핵심 메커니즘은 **양 플랫폼 모두
동작을 확인했다**. M0의 최대 리스크는 해소됐다.

## iOS 시뮬레이터 (iPhone 17 Pro) — PASS

`./scripts/spike-verify.sh` (공식 검증 스크립트, `simctl launch`로 실행) 결과:

```json
{
  "ok": true,
  "videoID": "4ioPBiTWm3M",
  "title": "백종원 제육볶음 레시피 불맛나게하는법 - YouTube",
  "duration": 415,
  "platform": "iOS",
  "frames": [
    { "t": 10, "bytes": 60983, "luminanceStdDev": 76.30, "ok": true },
    { "t": 30, "bytes": 50591, "luminanceStdDev": 48.31, "ok": true },
    { "t": 60, "bytes": 59807, "luminanceStdDev": 48.91, "ok": true }
  ]
}
```

세 프레임 모두 임계값(8)을 큰 폭으로 상회. 실행 소요(status.log 타임스탬프 기준):
로드 시작 → 메타데이터 획득 → prime → 캡처 3장까지 총 **약 4초**(광고 없음, m.youtube.com
모바일 플레이어가 빠르게 재생 가능 상태에 도달).

## macOS — PASS (단, 브리프의 Step 10 커맨드 그대로는 재현 안 됨 — 아래 "macOS 진단" 참고)

```json
{
  "ok": true,
  "videoID": "4ioPBiTWm3M",
  "title": "백종원 제육볶음 레시피 불맛나게하는법 - YouTube",
  "duration": 415,
  "platform": "macOS",
  "frames": [
    { "t": 10, "bytes": 60610,  "luminanceStdDev": 74.84, "ok": true },
    { "t": 30, "bytes": 152507, "luminanceStdDev": 46.48, "ok": true },
    { "t": 60, "bytes": 164993, "luminanceStdDev": 47.28, "ok": true }
  ]
}
```

세 프레임 모두 임계값 상회. bytes가 iOS보다 큰 것은 www.youtube.com 데스크톱 플레이어가
더 높은 해상도 스트림을 서빙하기 때문(정상). 실행 소요: 로드 시작 → 결과 저장까지 **약
16초**(광고 없음).

## 적용된 우회책 (코드에 이미 반영, `Sources/Capture/`)

전임 구현자가 이미 대부분의 실측 우회책을 코드에 반영해뒀고, 이번 세션에서 이를 검증하고
2건을 추가했다.

| 영역 | iOS | macOS |
|---|---|---|
| 로드 URL | `m.youtube.com`(모바일) | `www.youtube.com`(데스크톱) — m.으로 로드 시 www로 리다이렉트되지만 seek이 미디어 데이터를 못 가져옴(seek timeout, readyState=1 정체) 실측 |
| User-Agent | 기본값 | `customUserAgent`에 Safari 데스크톱 UA 강제 지정 |
| 스크립트 주입 시점 | `atDocumentStart` (둘 다 동일) | 좌동 — `atDocumentEnd`는 유튜브 데스크톱 페이지에서 20초+ 지연되는 재내비게이션 때문에 브리지가 늦게 생김(실측) |
| 메타데이터 대기 | 짧은 `waitMeta` 호출(1.5s)을 데드라인까지 반복 폴링 | 좌동 — 첫 로드가 재내비게이션을 거치며 주입 스크립트가 일시적으로 사라져 장기 단일 호출은 "undefined" TypeError로 깨짐(실측) |
| 재생 유도(`prime`) | `v.play()` | `v.play()` + `#movie_player` API의 `playVideo()`/`mute()` 병행 — cued 상태의 데스크톱 플레이어는 `v.play()`만으로는 세그먼트를 안 가져옴(readyState 정체, seeked 미발화) 실측 |
| 프레임 캡처 타이밍 | `seeked` 이벤트 + 150ms 대기 | 좌동 + `requestVideoFrameCallback`으로 새 프레임 제시까지 추가 대기 — macOS에서 `seeked` 발화 후에도 새 프레임 합성 전에 `drawImage`하면 직전 프레임이 찍힘(t=10과 t=60이 바이트 동일한 버그를 실측으로 발견·수정) |
| 광고 대응 | `.ad-showing`/`.ad-interrupting` 감지 + 스킵 버튼 자동 클릭 (양 플랫폼 공통) | 좌동 |
| 창 가시성 | 해당 없음 | `keepWindowVisible()` — 창이 가려지면 `visibilityState=hidden`이 되어 유튜브가 본편 재생을 시작하지 않고 JS 타이머도 스로틀됨(실측). `NSApplication.activate` + `.floating` 레벨 + `orderFrontRegardless`로 강제 노출 |

## JS → Swift 전달 방식: 문자열 기반 리팩토링 (이번 세션에서 완성 확인)

**배경**: 브리프 원안은 `callAsyncJavaScript`의 async-throws 오버로드가 `[String: Any]?`를
직접 반환하는 형태였으나, Swift 6 strict concurrency에서 이 반환값이 Sendable 요건을
위반해 macOS 빌드가 깨졌다(전임자가 리팩토링 도중 중단한 지점).

**완성된 형태** (`Sources/Capture/PlayerBridge.swift`):
- `callJS(_:timeout:) -> String?` — completion-handler 오버로드(`callAsyncJavaScript(_:arguments:in:in:completionHandler:)`)를
  `withCheckedThrowingContinuation`으로 감싸고, 별도 `Task`로 Swift 쪽 타임아웃 워치독을
  붙였다. 반환 타입을 `String?`으로 통일해 Sendable 문제를 원천 차단.
- `waitMeta`: JS 쪽에서 `JSON.stringify(...)`로 직렬화해 문자열로 반환 → Swift에서
  `JSONSerialization.jsonObject(with:)`로 파싱.
- `capture`: 원래부터 dataURL 문자열을 반환하므로 변경 없음 — Base64 디코딩 로직 그대로.
- **부수 효과(실측 발견)**: 워치독을 추가하면서, 페이지가 hidden 상태로 스로틀되면
  `callAsyncJavaScript`가 영원히 돌아오지 않는 문제도 같이 해결됐다(타임아웃 시
  `PlayerError.captureFailed`로 명확히 실패 처리).

이 세션 시작 시점에 이미 이 형태로 **완성되어 있었고 커밋(`575d229`)까지 되어 있었다** —
인계 메모의 "미완성" 서술과 달리, 실제로는 문자열 기반 리팩토링이 끝난 상태였다. 이번
세션은 (1) 두 플랫폼 빌드가 실제로 그린인지 재검증, (2) 실제 디바이스/시뮬레이터 스파이크
실행·판정(Step 9~10, 인계 메모에는 없던 작업)을 수행했다.

**callAsyncJavaScript 유지 여부 판정**: 프레임당 소요시간은 두 플랫폼 모두 **1초 이내**
(status.log 타임스탬프 기준 — iOS는 3프레임 합쳐 1초 미만, macOS는 프레임당 약 1초).
브리프가 우려한 "2초 초과 시 messageHandler 검토" 기준에 한참 못 미친다. **현재의
`callAsyncJavaScript` + 워치독 방식을 그대로 유지**하고, WKScriptMessageHandler 기반
전환은 불필요하다고 판정.

## macOS 진단: 브리프의 Step 10 커맨드가 이 환경에서 재현되지 않은 이유

브리프 Step 10은 앱 바이너리를 쉘 백그라운드 잡으로 직접 실행한다:
```bash
STEPKEEPER_SPIKE=1 ./build/Build/Products/Debug/stepkeeper.app/Contents/MacOS/stepkeeper &
```

이 방식으로 실행하면 **프로세스는 정상적으로 떠서 15시간 넘게 살아있지만, SwiftUI의
`.task` 뷰 모디파이어가 끝내 한 번도 발화하지 않는다** — `status.log`에 첫 줄(동기 코드
구간, await 이전)조차 기록되지 않는다. 진단 과정:

1. `ps eww -p <pid>`로 확인 — `STEPKEEPER_SPIKE=1`이 프로세스 환경에 정확히 전달됨을 확인
   (환경변수 전달 자체는 문제 아님).
2. `sample <pid> 3`으로 전체 스레드 콜스택 채집 — 메인 스레드가 `-[NSApplication run]`의
   정상 이벤트 루프(`mach_msg` 대기)에서 유휴 상태. 우리 앱 코드(Task 동기 구간)가 스택
   어디에도 없음 — Swift Concurrency Task 자체가 아직 시작되지 않았다는 뜻(시작됐다면
   await 이전 동기 구간이 즉시 실행되어 `status.log`가 이미 존재했어야 함).
3. TCC 관련 가능성도 배제하지 않고 확인 시도 — `tccd` 유닛 로그에서 `com.stepkeeper.app`에
   대한 `AUTHREQ_ATTRIBUTION`(귀속 확인) 이벤트는 있었지만 명시적 거부(denied) 로그는
   없음. `TCC.db` 직접 조회는 권한 없음(`authorization denied`) — 이 환경 자체가 Full Disk
   Access가 없어 확인 불가. **TCC가 원인인지 최종 확정은 못 했다.**
4. **해결**: `launchctl setenv STEPKEEPER_SPIKE 1` + `open build/.../stepkeeper.app`(LaunchServices
   경유 정상 실행)로 바꾸자 **즉시(로드 시작 후 16초 내) 정상 동작** — 메타데이터 획득,
   prime, 캡처 3장, result.json 저장까지 전부 성공.

**결론**: 쉘에서 앱 바이너리를 직접 백그라운드 실행하면(브리프 Step 10 원문 커맨드) 이
환경에서는 SwiftUI 씬의 정상적인 "활성화/키윈도우" 라이프사이클 이벤트가 발생하지 않는
것으로 보이며, `.task`가 이에 의존해 발화하지 않는 것으로 추정된다. `open`을 통한
LaunchServices 정상 실행 경로에서는 문제없이 동작한다. **실사용 환경(Finder 더블클릭,
Xcode Run)에서는 항상 LaunchServices 경로를 타므로 이 이슈가 실제 사용자에게 영향을 줄
가능성은 낮다** — 이번에 발견된 것은 앱 버그가 아니라 이 세션의 비대화형 검증 방법론의
한계였다.

**향후 macOS 자동화 스크립트를 만든다면** (`scripts/spike-verify.sh`의 macOS 버전 등)
`launchctl setenv <KEY> <VALUE>` + `open <app>` 조합을 표준 패턴으로 채택할 것.
브리프 Step 10 문서의 원문 커맨드(`STEPKEEPER_SPIKE=1 ./path/to/binary &`)는 이 환경에서는
동작하지 않으므로 참고용으로만 남기고, 실제 재현은 위 방법을 사용해야 한다.

## 추가로 적용한 예방적 변경 (`Sources/Capture/SpikeCaptureView.swift`)

macOS의 `spikeDir()`을 `~/Documents/spike`에서 `~/Library/Caches/spike`로 변경(macOS만,
`#if os(macOS)` 분기 — iOS는 기존 `~/Documents` 유지, 이미 PASS 확인됨). ad-hoc 서명은
리빌드마다 해시(LC_UUID)가 바뀌므로 macOS가 Documents/Desktop/Downloads 같은 보호된
폴더 접근을 매 리빌드마다 "최초 요청"으로 취급해 TCC 동의 대화상자를 띄울 수 있고,
비대화형 실행에서는 그 대화상자에 응답할 사용자가 없어 `FileManager` 호출이 막힐
위험이 있다. 이번 세션에서 실제로 겪은 행(hang)의 확정 원인은 위 "macOS 진단"에서
보듯 launch 방식 쪽으로 밝혀졌지만, Documents 접근도 별도의 잠재 리스크로 남아있어
선제적으로 제거했다 — 스파이크 산출물은 사용자 문서가 아니므로 Caches가 더 적절하기도
하다. **주의**: 이 변경으로 macOS 결과 위치가 브리프 원문의
`~/Library/Containers/com.stepkeeper.app/Data/Documents/spike/result.json` /
`~/Documents/spike/result.json`이 아니라 `~/Library/Caches/spike/result.json`이 됐다.

## 기록 누락 보완 (리뷰 반영)

Task 1 코드 리뷰에서 지적된, 이 문서에 빠져 있던 사실 3가지.

- **"DOM 구조 독립" 목표의 트레이드오프** (`CaptureScript.swift`): 원래 목표는 캡처
  스크립트가 video 엘리먼트에만 의존해 유튜브의 DOM 구조 변경에 영향받지 않는 것이었다.
  하지만 광고 처리와 cued 상태 재생 문제 때문에 완전한 독립은 의도적으로 트레이드오프됐다.
  실제 의존 표면: video 엘리먼트 + 광고 감지/스킵 셀렉터(`.ad-showing`, `.ad-interrupting`,
  `.ytp-skip-ad-button`, `.ytp-ad-skip-button`, `.ytp-ad-skip-button-modern`) + `prime()`의
  `#movie_player`(cued 상태의 데스크톱 플레이어가 `v.play()`만으로는 세그먼트를 가져오지
  않아 플레이어 API로 재생을 개시해야 했음, 위 표 참고). 파일 상단 주석이 이 사실과
  어긋나 있어 실제 의존 표면을 기술하도록 수정했다.
- **SwiftUI 씬 재활성화 시 `.task` 취소 대응** (`SpikeCaptureView.swift`): iOS 실측 —
  씬이 활성화되는 과정에서 SwiftUI가 `.task`를 취소했다가 재시작하는 경우가 있다.
  `run()`이 `CancellationError`를 별도로 잡아 "취소됨 — 재시작 대기" 상태로만 남기고,
  취소된 시도가 실패로 오인되어 `result.json`을 잘못된 값으로 덮어쓰지 않게 한다.
- **ad-hoc 코드 서명** (`project.yml`): 개발팀(Team ID)이 설정되지 않은 환경(CI, 이번
  스파이크 실행 환경)에서도 로컬 빌드·실행이 가능하도록 `CODE_SIGN_IDENTITY: "-"` /
  `CODE_SIGN_STYLE: Manual` / `CODE_SIGNING_REQUIRED: NO`를 추가했다. 위 "추가로 적용한
  예방적 변경"에서 언급한 TCC 리스크(리빌드마다 서명 해시가 바뀌는 문제)의 원인이기도
  하다.

## scripts/spike-verify.sh에 반영한 실측 기반 수정

- **잔여 데이터 초기화**: `simctl install` 전에 `simctl uninstall`을 추가. 이전 실행의
  `result.json`이 앱 데이터 컨테이너에 남아있으면 새 실행이 전혀 캡처를 안 해도 판정이
  가짜로 PASS될 수 있음(재현: 15시간 전 죽은 프로세스가 남긴 `result.json`을 발견 —
  이번 세션은 이를 지우고 공식 스크립트로 재검증해 실제 PASS를 확인했다).
- **타임아웃 확장**: 대기 루프를 60회×2초(120초)에서 90회×4초(360초)로 확장.
  `PlayerBridge`의 워치독 예산(메타데이터 90s + prime 10s + 캡처 30s×3 = 최악 193s)에
  맞춤.

## 재현 커맨드

**iOS:**
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
./scripts/spike-verify.sh
```

**macOS:**
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper \
  -destination 'platform=macOS' -derivedDataPath build build
launchctl setenv STEPKEEPER_SPIKE 1
open build/Build/Products/Debug/stepkeeper.app
# 결과: ~/Library/Caches/spike/result.json (최대 수십초 대기, 광고가 끼면 최악 수 분)
launchctl unsetenv STEPKEEPER_SPIKE   # 정리
pkill -x stepkeeper                   # 정리
```

## 남은 리스크 / 후속 과제

- **광고 변동성**: 실측 두 번 모두 프리롤 광고 없이 통과(운). 코드에는 스킵 가능/불가능
  광고 대응이 있지만(최대 대기 8s, 스킵 불가 광고 최대 137s 관측 코멘트 있음), "스킵 불가
  긴 광고"가 걸린 경우의 macOS 스트레스 테스트는 못 했다. 실제 M1 구현 시 광고 대기
  UX(로딩 인디케이터 등)를 고려할 것.
- **macOS 헤드리스 실행 한계**: 위 "macOS 진단" 참고. CI에서 macOS GUI 앱을 완전
  무인으로 검증하려면 `open`+`launchctl setenv` 패턴이 필요하다는 게 이번 세션의
  실질적 산출물 중 하나 — 향후 CI 스크립트 작성 시 그대로 재사용할 것.
- **TCC 원인 미확정**: Caches로 전환한 결정이 실제로 막았을 "만약의 경우"를 재현
  실험으로 검증하지는 못했다(시간 박스 준수를 위해 launch 방식 수정 후 PASS를 확인하고
  중단). 완전히 불필요한 변경이었을 가능성도 있으나 부작용은 없고 방어적으로는 유효하다.
