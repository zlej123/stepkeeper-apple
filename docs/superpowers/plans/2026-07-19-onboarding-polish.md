# stepkeeper-apple v1.2 온보딩 폴리시 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 첫 Gemini 키 입력 온보딩 개선 — 배너 펄스 시선 유도, AI Studio 프로미넌트 CTA, 접이식 발급 절차.

**Architecture:** UI-only(3파일). 스펙: `docs/superpowers/specs/2026-07-19-onboarding-polish-design.md` — 충돌 시 스펙 우선.

**Tech Stack:** SwiftUI symbolEffect / accessibilityReduceMotion / DisclosureGroup.

## Global Constraints

- 모든 xcodebuild 앞에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. 로그 /tmp 리다이렉트. UI 문구 한국어 아래 코드 그대로. docs/superpowers/ 수정 금지. build/ 커밋 금지. `.xcodeproj`는 소스 추가 없어 무변경 예상.

---

### Task 1: 온보딩 폴리시 3건

**Files:**
- Modify: `Sources/Views/HomeView.swift`(배너), `Sources/Views/SettingsView.swift`(CTA+절차), `Sources/Views/Support.swift`(펄스 배경 뷰)

**Interfaces:**
- Produces: `KeyNudgeBackground`(Support.swift — 접근성 반영 펄스 배경)

- [ ] **Step 1: Support.swift에 펄스 배경 추가** (파일 끝)

```swift
/// 키 미설정 배너의 시선 유도 배경 — 부드러운 주황 펄스. "동작 줄이기" 설정 시 정적 강조 (온보딩 폴리시).
struct KeyNudgeBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Color.orange.opacity(reduceMotion ? 0.18 : (pulsing ? 0.28 : 0.10))
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                       value: pulsing)
            .onAppear { pulsing = true }
    }
}
```

- [ ] **Step 2: HomeView 배너에 펄스 적용**

`if !hasKey` 섹션의 Label에 `.symbolEffect(.pulse, options: .repeating)`을 붙이고, Button에 `.listRowBackground(KeyNudgeBackground())` 추가:

```swift
            if !hasKey {
                Section {
                    Button {
                        showSettings = true
                    } label: {
                        Label("먼저 설정에서 Gemini API 키를 입력하세요", systemImage: "key.fill")
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    .foregroundStyle(.orange)
                    .listRowBackground(KeyNudgeBackground())
                }
            }
```

- [ ] **Step 3: SettingsView 링크를 조건부 CTA+절차로 교체**

기존 `Link("AI Studio에서 무료 키 발급 (카드 불필요)", ...)` 한 줄을 다음으로 교체:

```swift
                    if geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                                Label("AI Studio에서 무료 키 발급", systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.borderedProminent)
                            Text("← 여기를 눌러 1분 발급")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        DisclosureGroup("키 발급 방법 보기") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("1. 구글 계정으로 aistudio.google.com/apikey 접속")
                                Text("2. \"API 키 만들기(Create API key)\" 클릭")
                                Text("3. 생성된 키 복사 (AIza로 시작)")
                                Text("4. 위 칸에 붙여넣고 '키 저장' — 무료, 카드 등록 불필요")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        }
                        .font(.callout)
                    } else {
                        Link("AI Studio에서 무료 키 발급 (카드 불필요)",
                             destination: URL(string: "https://aistudio.google.com/apikey")!)
                            .font(.callout)
                    }
```

- [ ] **Step 4: 회귀 + 스크린샷**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/ob1.log 2>&1; tail -3 /tmp/ob1.log
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build > /tmp/ob2.log 2>&1; tail -3 /tmp/ob2.log
xcrun simctl bootstatus "iPhone 17 Pro" -b
xcrun simctl uninstall "iPhone 17 Pro" com.stepkeeper.app 2>/dev/null || true
xcrun simctl install "iPhone 17 Pro" build/Build/Products/Debug-iphonesimulator/stepkeeper.app
xcrun simctl launch "iPhone 17 Pro" com.stepkeeper.app && sleep 4
xcrun simctl io "iPhone 17 Pro" screenshot build/onboarding-banner.png
```

Expected: TEST SUCCEEDED(53) / BUILD SUCCEEDED / 스크린샷에 주황 강조 배너(클린 설치라 키 없음 상태).

- [ ] **Step 5: 커밋**

```bash
git add Sources/Views
git commit -m "feat: 온보딩 폴리시 — 배너 펄스·AI Studio CTA·발급 절차 안내"
```
