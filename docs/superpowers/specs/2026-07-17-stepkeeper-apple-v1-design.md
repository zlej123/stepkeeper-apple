# stepkeeper-apple v1 설계

2026-07-17 브레인스토밍에서 승인된 설계. 제품·아키텍처 전제는 [apple-brief.md](../apple-brief.md)를 따르며,
이 문서는 앱 레벨 설계(모듈·플로우·에러 처리·테스트·마일스톤)를 확정한다.

## 1. 목표와 범위

**목표**: 유튜브 how-to 영상 URL을 받아 단계별 문서를 만들고, 애매한 표현마다 사용자가 고른
실제 프레임(또는 타임스탬프 링크)을 첨부해 내보내는 SwiftUI 멀티플랫폼 앱(iOS/iPadOS/macOS).

**v1 범위**:
- URL 진입(앱 내 붙여넣기 + iOS 공유 확장) → 분석 → 후보 선택 → 문서 → 내보내기 전체 플로우
- 링크 모드(캡처 없이 타임스탬프 링크만) — 설정 토글, 상시 제공
- 설정: Gemini 키(Keychain), 언어, 서버 URL, 링크 모드
- 최근 문서 목록(로컬 저장 문서 재열람)

**범위 밖** (11절): 직접 Gemini 호출 모드, PDF/Goodnotes 서버 내보내기, 서버 배포, App Store 제출.

## 2. 상속된 확정 결정 (브리프)

1. 서버는 두뇌만(분석), 캡처는 클라이언트(WKWebView) — 영상 다운로드 금지 (App Store 5.2.3 방어)
2. BYOK: 사용자 Gemini 키를 Keychain에 저장, `X-Gemini-Key` 헤더로 서버에 패스스루
3. `duration`은 앱이 플레이어에서 얻어 보낸다 — 서버는 유튜브에 접속하지 않음
4. 자동 프레임 선택 없음 — before/center/after 3후보 + "전부 부적합(링크 사용)"을 사용자가 선택
5. 링크 모드만으로도 제품이 성립한다 — 캡처 실패의 최종 안전판

## 3. 이번 설계에서 확정한 결정

| 결정 | 선택 | 근거 |
|------|------|------|
| 빌드 순서 | M0 캡처 스파이크 → 코어 플로우 → 캡처 UI → 공유 확장 → 폴리시 | 최대 리스크(WebKit 캡처)를 최우선 제거 |
| 문서 조립 | 로컬 Swift (`MarkdownBuilder`) | 확장과 패리티, 분석 후 오프라인 동작, 브리프 허용. 출력 원본은 `skill-core/profiles/*/template.md`이며 골든 테스트로 고정 |
| 분석 경로 | stepkeeper-server 경유만 | 브리프 결정. 확장의 직접 Gemini 모드는 v1 비범위 |
| 기존 스캐폴드 | 유지 | XcodeGen, iOS 17/macOS 14, Swift 6, 단일 멀티플랫폼 타깃, `com.stepkeeper.app` |

## 4. 아키텍처

### 4.1 모듈 구조 (`Sources/`)

```
App/
  StepkeeperApp.swift        @main. 공유 확장이 남긴 URL 픽업(scenePhase), 라우팅
  AppModel.swift           @Observable 세션 상태(진행 단계, 현재 분석/캡처/문서)
Models/
  Analysis.swift           Analysis·Step·VisualGuide·Material Codable (시간은 Int 초)
  CandidateTimes.swift     before/center/after 계산 (capture.py·content.js 포팅)
  Picks.swift              guide_id → slot(before|center|after) | none
Services/
  StepkeeperAPI.swift        POST /v1/analyze. 상태코드→StepkeeperError 매핑
  KeychainStore.swift      Gemini 키 저장/로드/삭제 (Security 프레임워크)
  SettingsStore.swift      언어·서버URL·링크모드 (@AppStorage)
  MarkdownBuilder.swift    template.md와 동일 출력 (generic/recipe)
  DocumentStore.swift      문서+이미지 저장, 최근 목록
Capture/
  PlayerWebView.swift      WKWebView 래퍼 (#if os로 UIViewRepresentable/NSViewRepresentable)
  PlayerBridge.swift       JS 브리지: 메타데이터 대기, seek+캡처, 상태 복원
  capture.js               주입 스크립트 (video 엘리먼트만 의존, 페이지 구조 독립)
Views/
  HomeView.swift           URL 붙여넣기 + 최근 문서 목록
  AnalyzeFlowView.swift    플레이어(보이는 상태) + 진행 단계 표시
  CandidatePickerView.swift 가이드별 3후보+부적합 (center 기본 선택)
  DocumentView.swift       문서 렌더 + 내보내기
  SettingsView.swift       키·언어·서버URL·링크모드
ShareExtension/            (M3, 별도 타깃) URL 수신 → App Group 저장
```

### 4.2 데이터 모델

- 서버 `normalize()`가 시간 값을 초 단위 `Int`로 정규화해 반환하므로 모델도 `Int` 초.
  `best_visual_timestamp`는 `Int?` (null = 보여줄 장면 없음).
- `Analysis`는 두 프로파일의 슈퍼셋: `servings: String?` (recipe 전용),
  `category: String?`. 서버가 넣는 `_profile`·`_duration` 등 밑줄 메타 필드도 디코딩해 보존한다
  (문서 조립과 재열람에 필요).
- `video_id` 파싱은 코어와 동일 정규식: `(?:v=|youtu\.be/|shorts/)([\w-]{11})`.
- `candidateTimes(step:guide:duration:)` — center = `best_visual_timestamp`,
  step 있으면 before = `max(0, t_start-1)`, after = `min(max(0,duration-1), t_end+1)`;
  step 없으면 center ±4. (코어 `capture.py`와 동일, 동일 케이스로 단위 테스트)

### 4.3 핵심 플로우

```
URL 진입(붙여넣기/공유 확장)
→ video_id 파싱 실패 시 즉시 안내
→ AnalyzeFlowView: PlayerWebView가 https://m.youtube.com/watch?v=<id> 로드
→ capture.js: video.readyState ≥ HAVE_METADATA 대기 → {duration, title} 반환
→ duration 확보 실패 시 분석 호출 안 함(결정 #3), 재시도 UI
→ 프로파일 자동 감지: 제목이 /레시피|요리|recipe|cook/i 매치 → recipe, 아니면 generic
   (분석 시작 전 세그먼트로 수동 변경 가능)
→ POST /v1/analyze {url, profile, language, max_guides:5, duration} + X-Gemini-Key
   (model 파라미터는 생략 → 서버 기본값)
→ 링크 모드 ON: 캡처 생략, 모든 가이드 링크 폴백 → 문서로 직행
→ 링크 모드 OFF: 캡처 파이프라인(4.4) → CandidatePickerView → 선택 확정
→ 선택 이미지를 vg-N.jpg로 저장 + MarkdownBuilder 조립 → DocumentStore 저장
→ DocumentView: 내보내기(공유시트 / 폴더로 저장)
```

### 4.4 캡처 파이프라인 (content.js 포팅 + 개선)

1. 캡처 전 플레이어 상태 저장(paused/muted/currentTime), muted+pause.
   최초 1회 muted play→pause로 프레임 디코딩을 유도한다(자동재생 정책 우회 설정 필수).
2. 대상: `visual_guides.filter { $0.best_visual_timestamp != nil }`
3. 가이드마다 3슬롯 순차: seek(`seeked` 이벤트 + 8초 타임아웃) → 150ms 안정화 →
   canvas `drawImage` → `toDataURL("image/jpeg", 0.85)`
4. **개선(확장과 다른 점)**: 실패는 가이드 단위로 격리 — 해당 가이드만 링크 폴백으로 강등하고
   나머지는 계속한다. (확장은 전체 중단이었음)
5. 종료 시 상태 복원(currentTime/muted, 재생 중이었으면 play).
6. WKWebView 설정: `allowsInlineMediaPlayback = true`,
   `mediaTypesRequiringUserActionForPlayback = []`.
7. JS→Swift 전달: `callAsyncJavaScript` 반환값(dataURL 문자열) 기본.
   M0에서 대용량 문자열 성능 문제가 확인되면 `WKScriptMessageHandler`로 전환하고 M0 산출물에 기록.
8. 페이지: 두 플랫폼 모두 `m.youtube.com` (브리프 명시). macOS에서 재생/렌더 문제가 확인되면
   `www.youtube.com` + 데스크톱 UA로 전환하며 M0 산출물에 기록.

### 4.5 문서 조립 (MarkdownBuilder)

- 출력 형태의 원본은 `skill-core/profiles/*/template.md`. 확장 `buildMarkdown`은 템플릿과
  미세하게 다르므로(**recipe에 분류 줄 없음, "준비 재료 (servings)"/"조리 순서" 헤더**) 템플릿을 따른다.
- generic: `## 📋 {title}` / 분류(있으면) / `**■ 준비물**` / `**■ 순서**`
- recipe: `## 🍳 {title}` / `**■ 준비 재료** ({servings})` / `**■ 조리 순서**`
- 가이드 줄: `💡 *'{phrase}' 기준:* {guide_text}` 다음에
  선택 이미지 있으면 `![{phrase}](vg-N.jpg)` (상대 경로),
  없고 timestamp 있으면 `▶ [영상 M:SS에서 직접 확인](https://youtu.be/<vid>?t=<sec>)`,
  timestamp가 null이면 가이드 텍스트만.
- 푸터: `*출처: [{title}](https://youtu.be/<vid>) — stepkeeper로 생성*`
- 정확한 출력은 코어 `render.py` 결과와의 **골든 테스트**로 고정한다(7절). 세부 표현이 이 문서와
  충돌하면 골든(코어 출력)이 우선.

### 4.6 저장과 내보내기

- 저장 위치: `Documents/stepkeeper/<videoId>-<yyyyMMdd-HHmmss>/` — `document.md`, `vg-N.jpg`…,
  `meta.json`(제목·생성일·프로파일·언어·videoId), `analysis.json`+`picks.json`(재열람 렌더용 원본).
- DocumentView는 마크다운 파서 없이 **모델(analysis+picks+이미지)에서 네이티브 SwiftUI로 렌더**한다.
  `document.md`는 내보내기 산출물이며 화면 렌더 경로가 아니다.
- iOS: `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`로 파일 앱 노출.
- 최근 문서 목록 = 이 디렉토리 스캔(meta.json 기반), 탭하면 DocumentView 재열람.
- 내보내기 ①공유시트: document.md + 선택 이미지 파일 배열 (iOS ShareLink / macOS 공유 메뉴).
  ②폴더로 저장(Obsidian 등): 폴더 선택(fileImporter/NSOpenPanel) 후 파일 복사.
  Goodnotes는 v1에서 ①과 동일(md+이미지); PDF는 서버 확장 예정으로 비범위.

### 4.7 공유 확장 (M3, iOS)

- 별도 타깃 `StepkeeperShare`. `NSExtensionActivationSupportsWebURLWithMaxCount = 1`.
- 동작: URL 추출 → App Group(`group.com.stepkeeper.shared`) UserDefaults에
  `{url, receivedAt}` 저장 → "stepkeeper를 열면 분석이 시작됩니다" 안내 후 완료.
  (확장에서 본체 앱 직접 실행은 비공개 API라 하지 않는다)
- 본체: scenePhase active 시 App Group 확인 → 미소비 URL 있으면 플로우 자동 시작.
- macOS 공유 확장은 v1 비범위(붙여넣기 진입 사용).

### 4.8 설정과 보안

- Gemini 키: Keychain(`kSecClassGenericPassword`, service=`stepkeeper.gemini-key`,
  `kSecAttrAccessibleAfterFirstUnlock`). 설정 화면에 AI Studio 발급 안내 링크.
  키는 로그·에러 메시지에 절대 노출하지 않는다.
- 서버 URL 기본값 `http://127.0.0.1:8787` (개발 기본). 설정에 "실기기에서는 Mac의 LAN IP 입력" 힌트.
- ATS: 로컬/사설망 HTTP 허용 예외(`NSAllowsLocalNetworking`; 실기기 LAN IP가 막히면
  디버그 구성 한정 `NSAllowsArbitraryLoads`). 원격 배포 서버는 HTTPS 전제.
- macOS: App Sandbox + `com.apple.security.network.client`.
- Swift 6 strict concurrency: UI·WKWebView는 @MainActor, 모델은 Sendable 값 타입.

## 5. 화면 구성

1. **HomeView**: URL 입력창 + 붙여넣기 버튼(클립보드 자동 감지는 권한 프롬프트 마찰 때문에 안 함),
   최근 문서 목록. 키 미설정이면 설정 유도 배너.
2. **AnalyzeFlowView**: 플레이어가 보이는 상태에서 단계 표시
   (플레이어 로드 → 분석 중(M:SS, 프로파일) → 장면 캡처 중 vg-i/n). 취소 가능.
3. **CandidatePickerView**: 가이드별 카드 — phrase·guide_text, 3후보 썸네일(시각 라벨) + "부적합(링크 사용)".
   center 기본 선택(확장과 동일). 전부 선택 후 "문서 만들기".
4. **DocumentView**: 모델 기반 네이티브 렌더(이미지·링크 폴백 포함, 4.6) + 내보내기 버튼 2종 + 원본 영상 링크.
5. **SettingsView**: Gemini 키(SecureField), 언어 Picker(ko/en/ja), 서버 URL, 링크 모드 토글.

## 6. 에러 처리

| 상황 | 처리 |
|------|------|
| 잘못된 URL | video_id 파싱 실패 즉시 안내, 플로우 진입 안 함 |
| 플레이어 로드/duration 실패 | 분석 호출 안 함, 재시도 버튼 (링크 모드도 duration이 필요하므로 우회 경로 없음) |
| 401 | "설정에서 Gemini API 키를 입력하세요" + 설정 바로가기 |
| 422 | "URL 또는 요청 값 문제" + 서버 detail 표시 |
| 429 | "Gemini 무료 한도 도달 — 잠시 후 다시 시도" + 재시도 버튼 |
| 502 (모델 오류·계약 위반) | "분석에 실패했습니다 — 다시 시도" + detail 요약. 재시도는 동일 요청 재전송 |
| 네트워크 불가 | "서버에 연결할 수 없습니다 — 서버 URL 확인" + 설정 바로가기 |
| 개별 캡처 실패 | 해당 가이드만 링크 폴백 강등, 픽커에 "캡처 실패 — 링크 사용" 표시, 전체 중단 없음 |
| 억지 이미지 방지 | 자동 선택 없음 + 부적합 옵션 상시 제공(브리프 품질 기준 준수) |

## 7. 테스트 전략

- **단위**: `CandidateTimesTests`(step 유/무, 0·duration-1 클램프, 초단편 영상),
  `VideoIDTests`(watch/youtu.be/shorts/m.), `APIErrorMappingTests`(URLProtocol 스텁으로
  401/422/429/502/네트워크), `KeychainStoreTests`(라운드트립), `DocumentStoreTests`(저장·목록).
- **골든**: 코어 fixture(`stepkeeper/tests/evaluations/*.json`) 중 generic 1·recipe 1을 입력으로,
  코어 `render.py`로 생성한 기대 마크다운과 `MarkdownBuilder` 출력을 문자 단위 대조.
  케이스: 픽 있음 / 전부 none / timestamp null 포함. 기대 파일 생성 스크립트
  `scripts/make-golden.py`(파이썬, 코어 임포트)와 재생성 방법을 리포에 문서화.
- **수동 E2E**: `docs/TESTING.md` — 로컬 서버 + 실키 + 시뮬레이터/실기기 체크리스트
  (extension의 TESTING.md 스타일). 마일스톤별 통과 기준은 9절.
- UI 자동화 테스트는 v1 비범위.

## 8. 빌드·도구

- XcodeGen(`project.yml`) → `xcodegen generate`. 새 파일/타깃 추가 시 project.yml이 원본.
- CLI 빌드(이 Mac은 xcode-select가 CLT를 가리키므로):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
  (macOS: `-destination 'platform=macOS'`)
- 서명: 시뮬레이터·macOS 로컬 실행은 무서명/자동. 실기기·공유 확장은 사용자가 Xcode에서 팀 지정.

## 9. 마일스톤

| # | 내용 | 완료 기준 |
|---|------|-----------|
| M0 | 캡처 기술 스파이크 (디버그 하네스 뷰) | iOS 시뮬레이터+macOS에서 고정 영상의 지정 3시각 JPEG 획득, 순흑/빈 프레임 아님. 결과·우회책을 `docs/spike-capture.md`에 기록. **실패 시**: embed(iframe API) 대안 검증 → 그래도 실패면 v1을 링크 모드 온리로 조정하고 사용자에게 보고 |
| M1 | 코어 플로우 (링크 모드 E2E) | Models·API·Keychain·Settings·MarkdownBuilder·DocumentStore + 홈→분석→문서→내보내기. 단위·골든 테스트 그린, 로컬 서버로 실영상 1개 E2E |
| M2 | 캡처 + 후보 선택 | 파이프라인 통합, 픽커 UI, 이미지 포함 문서. 요리 1 + generic 1 실영상 E2E |
| M3 | iOS 공유 확장 | 유튜브 앱 공유 → 앱 열면 자동 분석 시작 |
| M4 | 폴리시 | macOS 검증·조정, 에러 UX 마감, 최근 문서, TESTING.md·README |

각 마일스톤 완료 시 커밋(작게, 리뷰 가능하게). M0 결과는 사용자에게 보고 후 진행.

## 10. 리스크와 완화

1. **WebKit에서 유튜브 캡처 불가/불안정** (Chrome에서만 증명됨: 자동재생 정책·canvas 오염·코덱)
   → M0 최우선 검증, embed 대안, 최종 안전판 링크 모드(제품 성립, 브리프 결정 #5).
2. **유튜브 페이지 구조 변화** → JS는 `video` 엘리먼트에만 의존, DOM 구조·선택자 독립.
3. **대용량 dataURL 전달 성능** → messageHandler 전환 옵션(M0에서 판정).
4. **시뮬레이터/실기기 렌더 차이** → M2에서 실기기 1회 검증 권장.
5. **Swift 6 동시성 마찰** → WKWebView 로직 @MainActor 고정, 모델 Sendable.
6. **App Store 5.2.3** → 다운로드 없음 유지, 링크 모드 상시 제공, 심사 대응은 제출 단계(비범위) 문서로.

## 11. 범위 밖 (기록)

- 직접 Gemini 호출 모드(확장 `bg.js` 참고 — skill-core 자산 번들 필요, 프롬프트가 앱 업데이트에 묶이는 트레이드오프)
- PDF 내보내기(서버 확장 예정), Goodnotes 전용 포맷
- 서버 배포/호스팅, App Store 제출(스크린샷·심사 노트), macOS 공유 확장, 위젯·단축어
