# stepkeeper-apple v1.1 Notion 내보내기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 저장된 문서(SavedDocument)를 사용자 Notion 통합 토큰(BYOT)으로 노션 페이지에 직접 업로드 — 이미지는 노션 파일 업로드 API, 블록 변환은 코어 `export.py::build_notion_blocks` 파리티(골든 검증).

**Architecture:** `NotionAPI`(URLSession, 업로드 2단계·페이지 생성·100블록 배칭) + `NotionBlockBuilder`(코어 1:1 포팅, 골든) + `NotionExporter`(오케스트레이션) + 설정(토큰 Keychain/부모 페이지 ID)·DocumentView 버튼. 스펙: `docs/superpowers/specs/2026-07-19-notion-export-design.md` — 충돌 시 스펙 우선.

**Tech Stack:** Swift 6 / URLSession / JSONSerialization / Swift Testing / 골든 생성은 코어 파이썬(`src/stepkeeper/export.py`) 임포트.

## Global Constraints

- 모든 `xcodebuild` 앞에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. 새 Swift 파일 후 `xcodegen generate`. 단위 테스트 기본: `-destination 'platform=macOS' test`, 로그는 `/tmp/*.log` 리다이렉트 후 tail.
- 코어 위치: `/Users/choejunhwan/dev/stepkeeper` — **v0.2.0 pip 레이아웃**: 모듈은 `src/stepkeeper/`, skill-core는 `src/stepkeeper/skill-core/`. 코어 수정 금지(읽기·임포트만).
- Notion 상수(코어와 동일): base `https://api.notion.com/v1`, 헤더 `Notion-Version: 2022-06-28`, 타임아웃 120초.
- **토큰 값은 Authorization 헤더 세팅 외 어디에도 등장 금지** (로그·에러 메시지·테스트 출력).
- UI 문구 한국어(스펙 4절 표 문구 그대로). docs/superpowers/ 수정 금지. build/ 커밋 금지. `.xcodeproj`는 소스 변경 시 함께 커밋(리포 관례).
- 블록 타입: `typealias NotionBlock = [String: Any]` — nonisolated 동일 태스크 안에서만 흐름(MainActor 경계 통과 금지).
- 커밋은 태스크당 1개 이상, 각 태스크의 커밋 스텝 메시지 사용.

## File Structure (최종 상태)

```
scripts/sync-assets.sh               # 수정: src/stepkeeper 경로 (Task 1)
scripts/make-golden.py               # 수정: 패키지 임포트 (Task 1)
scripts/make-notion-golden.py        # 신규: 기대 블록 JSON 생성 (Task 3)
Sources/Models/NotionPageID.swift    # 페이지 ID 정규화 (Task 2)
Sources/Services/NotionBlockBuilder.swift  # 코어 build_notion_blocks 포팅 (Task 3)
Sources/Services/NotionAPI.swift     # API 클라이언트 + 에러 매핑 (Task 4)
Sources/Services/NotionExporter.swift      # 업로드→블록→페이지 오케스트레이션 (Task 5)
Sources/Services/Settings.swift      # 수정: notionParentPageKey (Task 2)
Sources/Services/KeychainStore.swift # 수정: notionToken 인스턴스 (Task 2)
Sources/Views/SettingsView.swift     # 수정: Notion 섹션 (Task 6)
Sources/Views/DocumentView.swift     # 수정: Notion 버튼·상태 (Task 6)
Tests/NotionPageIDTests.swift (Task 2) / NotionBlockBuilderGoldenTests.swift (Task 3)
Tests/NotionAPITests.swift (Task 4) / NotionExporterTests.swift (Task 5)
Tests/Fixtures/golden/<case>/expected-notion.json ×3 (Task 3)
docs/TESTING.md + README.md          # 수정 (Task 7)
```

**체크포인트**: Task 7 완료 시 사용자 보고(실토큰 E2E 안내 포함). 태스크는 1→7 직렬.

---

### Task 1: 코어 v0.2.0 레이아웃 대응 — 스크립트 경로 수정

**Files:**
- Modify: `scripts/sync-assets.sh`, `scripts/make-golden.py`

**Interfaces:**
- Produces: 신 코어 레이아웃에서 동작하는 두 스크립트. Task 3의 make-notion-golden.py가 같은 임포트 패턴을 사용.

- [ ] **Step 1: sync-assets.sh 경로 수정**

`scripts/sync-assets.sh`의 `SRC=` 줄을 다음으로 교체:

```bash
SRC="${STEPKEEPER_PATH:-../stepkeeper}/src/stepkeeper/skill-core/profiles"
```

(코어 v0.2.0 pip 레이아웃 — skill-core가 src/stepkeeper/ 밑으로 이동. 구경로 폴백 불필요.)

- [ ] **Step 2: make-golden.py 임포트 수정**

`scripts/make-golden.py`에서:

```python
sys.path.insert(0, str(CORE))
import render as core_render  # noqa: E402
```

를 다음으로 교체:

```python
sys.path.insert(0, str(CORE / "src"))
from stepkeeper import render as core_render  # noqa: E402
```

(주석 등 다른 줄은 그대로. `CORE` 변수 정의는 기존 유지.)

- [ ] **Step 3: 동작 검증 — 산출물 무변화 확인**

```bash
cd /Users/choejunhwan/dev/stepkeeper-apple
./scripts/sync-assets.sh
python3 scripts/make-golden.py
git status --short
```

Expected: sync 메시지 + `wrote ...expected.md` 3줄, **`git status --short` 출력 없음**(템플릿·골든 모두 기존과 동일 — 코어 템플릿 무변경이 이미 확인돼 있음). 변화가 있으면 **중단하고 diff와 함께 보고**(코어 출력이 바뀌었다는 뜻 — 파리티 재검토 필요).

- [ ] **Step 4: 커밋**

```bash
git add scripts/sync-assets.sh scripts/make-golden.py
git commit -m "chore: 코어 v0.2.0 pip 레이아웃 대응 (스크립트 경로)"
```

---

### Task 2: NotionPageID 정규화 + 설정 키 + Keychain 인스턴스

**Files:**
- Create: `Sources/Models/NotionPageID.swift`, `Tests/NotionPageIDTests.swift`
- Modify: `Sources/Services/Settings.swift`, `Sources/Services/KeychainStore.swift`

**Interfaces:**
- Produces: `NotionPageID.normalize(_ input: String) -> String?`(하이픈 없는 32자 소문자 hex 또는 nil), `Settings.notionParentPageKey`(= "notionParentPage"), `KeychainStore.notionToken`(service "stepkeeper.notion-token"). Task 5·6이 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/NotionPageIDTests.swift`:

```swift
import Testing
@testable import stepkeeper

struct NotionPageIDTests {
    @Test func normalizesURLDashedAndRawInputs() {
        // 노션 페이지 URL (제목 슬러그 + 32자 hex)
        #expect(NotionPageID.normalize(
            "https://www.notion.so/myspace/Recipe-Notes-0123456789abcdef0123456789abcdef")
            == "0123456789abcdef0123456789abcdef")
        // 하이픈 UUID 형식
        #expect(NotionPageID.normalize("01234567-89ab-cdef-0123-456789abcdef")
            == "0123456789abcdef0123456789abcdef")
        // 순수 32자 hex (대문자 → 소문자)
        #expect(NotionPageID.normalize("0123456789ABCDEF0123456789ABCDEF")
            == "0123456789abcdef0123456789abcdef")
        // 공백 포함 입력
        #expect(NotionPageID.normalize("  0123456789abcdef0123456789abcdef\n")
            == "0123456789abcdef0123456789abcdef")
    }
    @Test func rejectsInvalidInputs() {
        #expect(NotionPageID.normalize("") == nil)
        #expect(NotionPageID.normalize("그냥 텍스트") == nil)
        #expect(NotionPageID.normalize("12345") == nil)                    // 너무 짧음
        #expect(NotionPageID.normalize("0123456789abcdef0123456789abcdeg") == nil)  // g는 hex 아님
    }
    @Test func urlWithQueryPicksPageIDNotViewID() {
        // URL 끝 쿼리(v=뷰ID)가 아니라 경로의 페이지 ID를 잡아야 한다 — 경로가 앞이므로 첫 매치 사용 검증
        #expect(NotionPageID.normalize(
            "https://www.notion.so/myspace/Notes-0123456789abcdef0123456789abcdef?pvs=4")
            == "0123456789abcdef0123456789abcdef")
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n2.log 2>&1; tail -5 /tmp/n2.log
```

Expected: 컴파일 실패 — `cannot find 'NotionPageID' in scope`.

- [ ] **Step 3: 구현**

`Sources/Models/NotionPageID.swift`:

```swift
import Foundation

/// 노션 페이지 식별자 정규화 — 페이지 URL·하이픈 UUID·32자 hex 입력을 모두 허용하고
/// 하이픈 없는 32자 소문자 hex로 통일한다 (설정 입력 편의: 페이지 URL을 그대로 붙여넣어도 됨).
enum NotionPageID {
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.firstMatch(
            of: /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32}(?![0-9a-fA-F])/)
        else { return nil }
        return String(match.output)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
}
```

`Sources/Services/Settings.swift`의 키 상수 블록에 추가:

```swift
    static let notionParentPageKey = "notionParentPage"
```

`Sources/Services/KeychainStore.swift`의 `static let geminiKey` 아래에 추가:

```swift
    static let notionToken = KeychainStore(service: "stepkeeper.notion-token")
```

- [ ] **Step 4: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n2b.log 2>&1; tail -3 /tmp/n2b.log
```

Expected: `** TEST SUCCEEDED **` (기존 42 + 신규 3 = 45 tests).

- [ ] **Step 5: 커밋**

```bash
git add Sources Tests stepkeeper-apple.xcodeproj
git commit -m "feat: NotionPageID 정규화 + Notion 설정 키·Keychain 인스턴스"
```

---

### Task 3: NotionBlockBuilder — 코어 build_notion_blocks 포팅 + 골든

**Files:**
- Create: `scripts/make-notion-golden.py`, `Tests/Fixtures/golden/{generic-mixed,generic-links-only,recipe-mixed}/expected-notion.json`(스크립트 산출·커밋), `Sources/Services/NotionBlockBuilder.swift`, `Tests/NotionBlockBuilderGoldenTests.swift`

**Interfaces:**
- Consumes: `Analysis`/`VisualGuide`(v1 Task 2), `MarkdownBuilder.hms`(v1 Task 5), v1 골든 fixture(`analysis.json`/`case.json`), `Bundle.fixtureData`
- Produces: `typealias NotionBlock = [String: Any]`, `NotionBlockBuilder.rich(_ text: String, link: String?) -> [[String: Any]]`, `NotionBlockBuilder.blocks(analysis: Analysis, videoId: String, imageUploadIds: [String: String]) -> [NotionBlock]`. Task 4(createPage의 title rich)·Task 5가 사용. **파리티 원본은 코어 `src/stepkeeper/export.py` 244~288행 — 임의 개선 금지, 골든이 심판.**

- [ ] **Step 1: 골든 생성 스크립트 작성·실행**

`scripts/make-notion-golden.py`:

```python
#!/usr/bin/env python3
"""Notion 블록 골든 생성 — 코어 build_notion_blocks로 기대 JSON을 만든다.
사용: python3 scripts/make-notion-golden.py  (코어: STEPKEEPER_PATH, 기본 ../stepkeeper)
이미지 업로드 id는 case.json의 image_refs 키에 fake-<guide_id>를 주입한다."""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = Path(os.environ.get("STEPKEEPER_PATH", ROOT.parent / "stepkeeper")).resolve()
sys.path.insert(0, str(CORE / "src"))
from stepkeeper import export as core_export  # noqa: E402

golden_root = ROOT / "Tests" / "Fixtures" / "golden"
for case_dir in sorted(p for p in golden_root.iterdir() if p.is_dir()):
    analysis = json.loads((case_dir / "analysis.json").read_text(encoding="utf-8"))
    case = json.loads((case_dir / "case.json").read_text(encoding="utf-8"))
    image_ids = {gid: f"fake-{gid}" for gid in case.get("image_refs", {})}
    blocks = core_export.build_notion_blocks(analysis, case["video_id"], image_ids)
    out = case_dir / "expected-notion.json"
    out.write_text(json.dumps(blocks, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {case_dir.name}/expected-notion.json ({len(blocks)} blocks)")
```

```bash
python3 scripts/make-notion-golden.py
```

Expected: 3줄 `wrote ...`. 각 파일을 열어 형태 확인(요약 문단, YouTube 원본 링크, 준비물/순서, quote+image/링크). expected-notion.json 3개는 커밋 대상.

- [ ] **Step 2: 실패하는 골든 테스트 작성**

`Tests/NotionBlockBuilderGoldenTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

struct NotionBlockBuilderGoldenTests {
    @Test(arguments: ["generic-mixed", "generic-links-only", "recipe-mixed"])
    func matchesCoreBlocks(caseName: String) throws {
        let sub = "Fixtures/golden/\(caseName)"
        let analysis = try JSONDecoder().decode(
            Analysis.self, from: Bundle.fixtureData("analysis", subdirectory: sub))
        let golden = try JSONDecoder().decode(
            MarkdownBuilderGoldenTests.GoldenCase.self,
            from: Bundle.fixtureData("case", subdirectory: sub))
        let expected = try JSONSerialization.jsonObject(
            with: Bundle.fixtureData("expected-notion", subdirectory: sub)) as! NSArray

        let imageIds = Dictionary(uniqueKeysWithValues:
            golden.imageRefs.keys.map { ($0, "fake-\($0)") })
        let produced = NotionBlockBuilder.blocks(
            analysis: analysis, videoId: golden.videoId, imageUploadIds: imageIds)
        // Swift 딕셔너리 → JSON 왕복 후 NSArray 동등 비교 (키 순서 무관, 값·구조 단위)
        let roundTripped = try JSONSerialization.jsonObject(
            with: JSONSerialization.data(withJSONObject: produced)) as! NSArray
        #expect(roundTripped == expected)
    }
}
```

- [ ] **Step 3: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n3.log 2>&1; tail -5 /tmp/n3.log
```

Expected: 컴파일 실패 — `cannot find 'NotionBlockBuilder' in scope`.

- [ ] **Step 4: 구현**

`Sources/Services/NotionBlockBuilder.swift`:

```swift
import Foundation

/// Notion 블록 표현 — JSONSerialization 호환 딕셔너리.
/// nonisolated 동일 태스크 안에서만 흐른다(MainActor 경계 통과 금지 — 스펙 3.1).
typealias NotionBlock = [String: Any]

/// 코어 export.py::build_notion_blocks(244~288행) 1:1 포팅.
/// 골든(expected-notion.json)이 파리티 심판 — 동작을 임의로 개선하지 말 것.
enum NotionBlockBuilder {
    /// 코어 _rich: 2000자 절단 + 선택적 링크
    static func rich(_ text: String, link: String? = nil) -> [[String: Any]] {
        var textDict: [String: Any] = ["content": String(text.prefix(2000))]
        if let link {
            textDict["link"] = ["url": link]
        }
        return [["type": "text", "text": textDict]]
    }

    static func blocks(analysis: Analysis, videoId: String,
                       imageUploadIds: [String: String]) -> [NotionBlock] {
        var blocks: [NotionBlock] = []
        if !analysis.summary.isEmpty {
            blocks.append(["type": "paragraph",
                           "paragraph": ["rich_text": rich(analysis.summary)]])
        }
        blocks.append(["type": "paragraph", "paragraph": ["rich_text": rich(
            "YouTube 원본", link: "https://youtu.be/\(videoId)")]])

        if !analysis.materials.isEmpty {
            blocks.append(["type": "heading_2",
                           "heading_2": ["rich_text": rich("준비물")]])
            for material in analysis.materials {
                blocks.append(["type": "bulleted_list_item", "bulleted_list_item":
                    ["rich_text": rich("\(material.name) \(material.amount)")]])
            }
        }

        var byStep: [Int: [VisualGuide]] = [:]
        for guide in analysis.visualGuides {
            byStep[guide.stepId, default: []].append(guide)
        }

        blocks.append(["type": "heading_2", "heading_2": ["rich_text": rich("순서")]])
        for step in analysis.steps {
            blocks.append(["type": "numbered_list_item", "numbered_list_item":
                ["rich_text": rich("\(step.summary) — \(step.detail)")]])
            for guide in byStep[step.id] ?? [] {
                blocks.append(["type": "quote", "quote": ["rich_text": rich(
                    "💡 '\(guide.phrase)' 기준: \(guide.guideText)")]])
                if let uploadId = imageUploadIds[guide.id] {
                    blocks.append(["type": "image", "image":
                        ["type": "file_upload", "file_upload": ["id": uploadId]]])
                } else if let ts = guide.bestVisualTimestamp {
                    blocks.append(["type": "paragraph", "paragraph": ["rich_text": rich(
                        "▶ 영상 \(MarkdownBuilder.hms(ts))에서 직접 확인",
                        link: "https://youtu.be/\(videoId)?t=\(ts)")]])
                }
            }
        }
        return blocks
    }
}
```

주의: 코어의 timestamp 표기 `f"{ts // 60}:{ts % 60:02d}"`는 `MarkdownBuilder.hms`와 동일 출력(비음수 도메인) — 재사용. timestamp null 가이드는 quote만(코어와 동일 — md와 다르지만 코어 Notion 매핑이 원본, 스펙 3.2).

- [ ] **Step 5: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n3b.log 2>&1; tail -3 /tmp/n3b.log
```

Expected: `** TEST SUCCEEDED **` (45 + 3 = 48 tests). 골든 불일치 시 expected-notion.json을 고치지 말고 Swift 쪽을 고친다.

- [ ] **Step 6: 커밋**

```bash
git add scripts/make-notion-golden.py Tests Sources/Services/NotionBlockBuilder.swift stepkeeper-apple.xcodeproj
git commit -m "feat: NotionBlockBuilder — 코어 블록 매핑 포팅 + 골든"
```

---

### Task 4: NotionAPI — 업로드·페이지 생성 클라이언트 + 에러 매핑

**Files:**
- Create: `Sources/Services/NotionAPI.swift`, `Tests/NotionAPITests.swift`

**Interfaces:**
- Consumes: `NotionBlock`/`NotionBlockBuilder.rich`(Task 3), `StubURLProtocol`(v1 Task 7 — Tests/StepkeeperAPITests.swift의 것 재사용, static 공유라 `.serialized` 필수)
- Produces: `NotionAPIError`(`.invalidToken .parentNotFound .rateLimited .api(Int, String) .network(String)`, LocalizedError 한국어 — 스펙 4절 문구), `NotionAPI(token: String, session: URLSession = .shared)` — `createFileUpload() async throws -> String`, `sendFileUpload(id:data:filename:mime:) async throws`, `createPage(parentPageID:title:children:) async throws -> (id: String, url: String?)`, `appendChildren(pageID:blocks:) async throws`. Task 5가 사용.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/NotionAPITests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

@Suite(.serialized)
struct NotionAPITests {
    private func makeAPI() -> NotionAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return NotionAPI(token: "test-token", session: URLSession(configuration: config))
    }
    private func reset() {
        StubURLProtocol.handler = nil
        StubURLProtocol.networkError = nil
        StubURLProtocol.capturedRequest = nil
        StubURLProtocol.capturedBody = nil
    }

    @Test func fileUploadTwoStepSequence() async throws {
        defer { reset() }
        StubURLProtocol.handler = { request in
            if request.url!.path == "/v1/file_uploads" {
                return (200, Data(#"{"id": "fu-123"}"#.utf8))
            }
            return (200, Data("{}".utf8))
        }
        let api = makeAPI()
        let id = try await api.createFileUpload()
        #expect(id == "fu-123")

        try await api.sendFileUpload(id: id, data: Data([0xFF, 0xD8]), filename: "vg-1.jpg")
        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.url?.path == "/v1/file_uploads/fu-123/send")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?
            .hasPrefix("multipart/form-data; boundary=") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == "2022-06-28")
        let body = try #require(StubURLProtocol.capturedBody)
        let bodyText = String(decoding: body, as: UTF8.self)
        #expect(bodyText.contains(#"filename="vg-1.jpg""#))
    }

    @Test func createPagePayloadAndURL() async throws {
        defer { reset() }
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"id": "page-1", "url": "https://www.notion.so/page-1"}"#.utf8))
        }
        let api = makeAPI()
        let blocks: [NotionBlock] = [["type": "paragraph",
                                      "paragraph": ["rich_text": NotionBlockBuilder.rich("x")]]]
        let page = try await api.createPage(parentPageID: "p" + String(repeating: "0", count: 31),
                                            title: "제목", children: blocks)
        #expect(page.id == "page-1")
        #expect(page.url == "https://www.notion.so/page-1")
        let request = try #require(StubURLProtocol.capturedRequest)
        #expect(request.url?.path == "/v1/pages")
        let payload = try JSONSerialization.jsonObject(
            with: try #require(StubURLProtocol.capturedBody)) as! [String: Any]
        let parent = payload["parent"] as! [String: Any]
        #expect(parent["page_id"] as? String == "p" + String(repeating: "0", count: 31))
        #expect((payload["children"] as! [Any]).count == 1)
        let title = ((payload["properties"] as! [String: Any])["title"] as! [String: Any])["title"] as! [[String: Any]]
        #expect(((title[0]["text"] as! [String: Any])["content"] as? String) == "제목")
    }

    @Test func mapsErrorStatuses() async throws {
        defer { reset() }
        let api = makeAPI()
        StubURLProtocol.handler = { _ in (401, Data(#"{"message": "unauthorized"}"#.utf8)) }
        await #expect(throws: NotionAPIError.invalidToken) { _ = try await api.createFileUpload() }
        StubURLProtocol.handler = { _ in (404, Data(#"{"message": "not found"}"#.utf8)) }
        await #expect(throws: NotionAPIError.parentNotFound) { _ = try await api.createFileUpload() }
        StubURLProtocol.handler = { _ in (429, Data(#"{"message": "rate"}"#.utf8)) }
        await #expect(throws: NotionAPIError.rateLimited) { _ = try await api.createFileUpload() }
        StubURLProtocol.handler = { _ in (400, Data(#"{"message": "bad block"}"#.utf8)) }
        await #expect(throws: NotionAPIError.api(400, "bad block")) { _ = try await api.createFileUpload() }
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n4.log 2>&1; tail -5 /tmp/n4.log
```

Expected: 컴파일 실패 — `cannot find 'NotionAPI' in scope`.

- [ ] **Step 3: 구현**

`Sources/Services/NotionAPI.swift`:

```swift
import Foundation

enum NotionAPIError: Error, Equatable, LocalizedError {
    case invalidToken        // 401
    case parentNotFound      // 404
    case rateLimited         // 429
    case api(Int, String)    // 기타 — Notion 에러 body의 message
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidToken: "Notion 토큰이 유효하지 않습니다 — 설정을 확인하세요"
        case .parentNotFound: "부모 페이지를 찾을 수 없습니다 — 페이지 ID와 통합 연결(페이지 ··· → 연결)을 확인하세요"
        case .rateLimited: "Notion 요청 한도 도달 — 잠시 후 다시 시도해 주세요"
        case .api(let code, let message): "Notion 오류 (HTTP \(code)) — \(message)"
        case .network: "Notion에 연결할 수 없습니다 — 네트워크를 확인하세요"
        }
    }
}

/// Notion 공식 API 클라이언트 (BYOT). 코어 export.py의 notion_request/notion_upload_image 포팅.
/// 토큰은 Authorization 헤더 세팅 외 어디에도 쓰지 않는다.
final class NotionAPI: Sendable {
    static let version = "2022-06-28"   // 코어와 동일 고정
    private static let base = URL(string: "https://api.notion.com/v1")!
    private let token: String
    private let session: URLSession

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    private func request(path: String, jsonBody: [String: Any]? = nil,
                         rawBody: (data: Data, contentType: String)? = nil)
        async throws -> [String: Any] {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        } else if let rawBody {
            request.setValue(rawBody.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = rawBody.data
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NotionAPIError.network(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw NotionAPIError.api(0, "응답 해석 불가")
        }
        switch http.statusCode {
        case 200...299: break
        case 401: throw NotionAPIError.invalidToken
        case 404: throw NotionAPIError.parentNotFound
        case 429: throw NotionAPIError.rateLimited
        default: throw NotionAPIError.api(http.statusCode, Self.message(from: data))
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func message(from data: Data) -> String {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"]
            as? String ?? ""
    }

    func createFileUpload() async throws -> String {
        let object = try await request(path: "/file_uploads", jsonBody: [:])
        guard let id = object["id"] as? String else {
            throw NotionAPIError.api(200, "file_upload id 없음")
        }
        return id
    }

    func sendFileUpload(id: String, data: Data, filename: String,
                        mime: String = "image/jpeg") async throws {
        let boundary = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var body = Data()
        body.append(Data("""
        --\(boundary)\r
        Content-Disposition: form-data; name="file"; filename="\(filename)"\r
        Content-Type: \(mime)\r
        \r\n
        """.utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        _ = try await request(path: "/file_uploads/\(id)/send",
                              rawBody: (body, "multipart/form-data; boundary=\(boundary)"))
    }

    func createPage(parentPageID: String, title: String,
                    children: [NotionBlock]) async throws -> (id: String, url: String?) {
        let object = try await request(path: "/pages", jsonBody: [
            "parent": ["page_id": parentPageID],
            "properties": ["title": ["title": NotionBlockBuilder.rich(title)]],
            "children": children,
        ])
        guard let id = object["id"] as? String else {
            throw NotionAPIError.api(200, "page id 없음")
        }
        return (id, object["url"] as? String)
    }

    func appendChildren(pageID: String, blocks: [NotionBlock]) async throws {
        _ = try await request(path: "/blocks/\(pageID)/children",
                              jsonBody: ["children": blocks])
    }
}
```

주의: `sendFileUpload`의 멀티라인 문자열 리터럴은 `\r` 이스케이프·빈 줄 처리에서 실수하기 쉽다 — 구현 후 테스트의 `bodyText.contains(#"filename="vg-1.jpg""#)` 단언과 Content-Disposition 줄 형식(코어 236~238행: `--boundary\r\n` + Disposition 줄 + Content-Type 줄 + `\r\n\r\n` + 바이트 + `\r\n--boundary--\r\n`)이 일치하는지 확인하라. 문자열 리터럴이 불안하면 명시적 문자열 연결(`"--\(boundary)\r\n" + ...`)로 바꿔도 된다(동작 동일하면 적응 기록 불요).

- [ ] **Step 4: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n4b.log 2>&1; tail -3 /tmp/n4b.log
```

Expected: `** TEST SUCCEEDED **` (48 + 3 = 51 tests).

- [ ] **Step 5: 커밋**

```bash
git add Sources/Services/NotionAPI.swift Tests/NotionAPITests.swift stepkeeper-apple.xcodeproj
git commit -m "feat: NotionAPI — 파일 업로드 2단계·페이지 생성·에러 매핑"
```

---

### Task 5: NotionExporter — 업로드→블록→페이지 오케스트레이션

**Files:**
- Create: `Sources/Services/NotionExporter.swift`, `Tests/NotionExporterTests.swift`

**Interfaces:**
- Consumes: `NotionAPI`(Task 4), `NotionBlockBuilder`(Task 3), `SavedDocument`(v1 Task 8), `StubURLProtocol`
- Produces: `NotionExporter(api: NotionAPI, parentPageID: String)` — `export(document: SavedDocument) async throws -> URL`. Task 6이 사용. 스펙 3.3: 이미지 업로드 하나라도 실패하면 **페이지 생성 전에 중단**(부분 페이지 방지).

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/NotionExporterTests.swift`:

```swift
import Testing
import Foundation
@testable import stepkeeper

@Suite(.serialized)
struct NotionExporterTests {
    /// 스텁 라우팅: 경로별 응답 + 요청 기록 (페이로드 검증용)
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [(path: String, body: Data?)] = []
        func record(_ path: String, _ body: Data?) {
            lock.lock(); defer { lock.unlock() }
            _requests.append((path, body))
        }
        var requests: [(path: String, body: Data?)] {
            lock.lock(); defer { lock.unlock() }
            return _requests
        }
    }

    private func makeDocument(guideCount: Int, pickedImages: [String: Data]) throws
        -> (SavedDocument, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notion-exp-\(UUID().uuidString)")
        let store = DocumentStore(root: root)
        let steps = (1...max(1, guideCount)).map {
            Step(id: $0, summary: "단계\($0)", detail: "설명\($0)", tStart: $0 * 10, tEnd: $0 * 10 + 5)
        }
        let guides = (1...guideCount).map {
            VisualGuide(id: "vg-\($0)", stepId: $0, sourcePhrase: "p", phrase: "p\($0)",
                        type: "state", whatToShow: "w", bestVisualTimestamp: $0 * 10 + 2,
                        guideText: "g\($0)", importance: 0.5)
        }
        let analysis = Analysis(title: "노션 테스트", summary: "요약", category: "생활",
                                servings: nil, materials: [Material(name: "재료", amount: "1")],
                                steps: steps, visualGuides: guides,
                                duration: 600, profile: "generic", outputLanguage: "ko")
        let raw = try JSONSerialization.data(withJSONObject: ["title": "노션 테스트"])
        let picks = Dictionary(uniqueKeysWithValues: guides.map {
            ($0.id, pickedImages[$0.id + ".jpg"] != nil ? "center" : "none")
        })
        let meta = try store.save(videoId: "dQw4w9WgXcQ", title: analysis.title,
                                  analysis: analysis, rawAnalysis: raw, picks: picks,
                                  images: pickedImages, markdown: "md\n")
        return (try store.load(id: meta.id), root)
    }

    private func stub(recorder: Recorder, uploadFails: Bool = false) {
        StubURLProtocol.handler = { request in
            let path = request.url!.path
            recorder.record(path, request.bodyData)
            if path == "/v1/file_uploads" {
                return (200, Data(#"{"id": "fu-1"}"#.utf8))
            }
            if path.hasSuffix("/send") {
                return uploadFails ? (500, Data(#"{"message": "boom"}"#.utf8))
                                   : (200, Data("{}".utf8))
            }
            if path == "/v1/pages" {
                return (200, Data(#"{"id": "page-1", "url": "https://www.notion.so/page-1"}"#.utf8))
            }
            return (200, Data("{}".utf8))   // /v1/blocks/.../children
        }
    }
    private func makeExporter() -> NotionExporter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return NotionExporter(
            api: NotionAPI(token: "test-token", session: URLSession(configuration: config)),
            parentPageID: String(repeating: "0", count: 32))
    }
    private func reset() {
        StubURLProtocol.handler = nil
        StubURLProtocol.capturedRequest = nil
        StubURLProtocol.capturedBody = nil
    }

    @Test func wiresPickedImageIntoImageBlock() async throws {
        defer { reset() }
        let recorder = Recorder()
        stub(recorder: recorder)
        let (document, root) = try makeDocument(
            guideCount: 1, pickedImages: ["vg-1.jpg": Data([0xFF, 0xD8, 0x01])])
        defer { try? FileManager.default.removeItem(at: root) }

        let url = try await makeExporter().export(document: document)

        #expect(url.absoluteString == "https://www.notion.so/page-1")
        let pageBody = try #require(recorder.requests.first { $0.path == "/v1/pages" }?.body)
        let payload = try JSONSerialization.jsonObject(with: pageBody) as! [String: Any]
        let children = payload["children"] as! [[String: Any]]
        let imageBlocks = children.filter { $0["type"] as? String == "image" }
        #expect(imageBlocks.count == 1)
        let upload = (imageBlocks[0]["image"] as! [String: Any])["file_upload"] as! [String: Any]
        #expect(upload["id"] as? String == "fu-1")
    }

    @Test func batchesBlocksOver100() async throws {
        defer { reset() }
        let recorder = Recorder()
        stub(recorder: recorder)
        // 가이드 60개(픽 없음) → 블록 = 요약1+링크1+준비물2+순서1+ (step+quote+ts링크)×60 = 185 → 100/85 분할
        let (document, root) = try makeDocument(guideCount: 60, pickedImages: [:])
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await makeExporter().export(document: document)

        let pageBody = try #require(recorder.requests.first { $0.path == "/v1/pages" }?.body)
        let pagePayload = try JSONSerialization.jsonObject(with: pageBody) as! [String: Any]
        #expect((pagePayload["children"] as! [Any]).count == 100)
        let appends = recorder.requests.filter { $0.path.hasPrefix("/v1/blocks/") }
        #expect(appends.count == 1)
        let appendPayload = try JSONSerialization.jsonObject(with: appends[0].body!) as! [String: Any]
        #expect((appendPayload["children"] as! [Any]).count == 85)
    }

    @Test func uploadFailureAbortsBeforePageCreation() async throws {
        defer { reset() }
        let recorder = Recorder()
        stub(recorder: recorder, uploadFails: true)
        let (document, root) = try makeDocument(
            guideCount: 1, pickedImages: ["vg-1.jpg": Data([0xFF, 0xD8, 0x01])])
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: NotionAPIError.api(500, "boom")) {
            _ = try await self.makeExporter().export(document: document)
        }
        #expect(!recorder.requests.contains { $0.path == "/v1/pages" })
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n5.log 2>&1; tail -5 /tmp/n5.log
```

Expected: 컴파일 실패 — `cannot find 'NotionExporter' in scope`.

- [ ] **Step 3: 구현**

`Sources/Services/NotionExporter.swift`:

```swift
import Foundation

/// SavedDocument → Notion 페이지 (스펙 3.3).
/// 절차: 픽 이미지 전부 업로드(실패 시 페이지 생성 전 중단) → 블록 → 페이지 생성 → 100블록 배칭.
final class NotionExporter: Sendable {
    private let api: NotionAPI
    private let parentPageID: String

    init(api: NotionAPI, parentPageID: String) {
        self.api = api
        self.parentPageID = parentPageID
    }

    func export(document: SavedDocument) async throws -> URL {
        var uploadIds: [String: String] = [:]
        for guide in document.analysis.visualGuides {
            guard (document.picks[guide.id] ?? "none") != "none" else { continue }
            let file = document.folder.appendingPathComponent("\(guide.id).jpg")
            guard let data = try? Data(contentsOf: file) else { continue }   // 픽은 있는데 파일 없음 → 링크 폴백
            let uploadId = try await api.createFileUpload()
            try await api.sendFileUpload(id: uploadId, data: data, filename: "\(guide.id).jpg")
            uploadIds[guide.id] = uploadId
        }

        let blocks = NotionBlockBuilder.blocks(
            analysis: document.analysis, videoId: document.meta.videoId,
            imageUploadIds: uploadIds)
        let page = try await api.createPage(
            parentPageID: parentPageID, title: document.analysis.title,
            children: Array(blocks.prefix(100)))
        var start = 100
        while start < blocks.count {
            try await api.appendChildren(
                pageID: page.id, blocks: Array(blocks[start..<min(start + 100, blocks.count)]))
            start += 100
        }

        if let urlString = page.url, let url = URL(string: urlString) { return url }
        return URL(string: "https://www.notion.so/"
                   + page.id.replacingOccurrences(of: "-", with: ""))!
    }
}
```

- [ ] **Step 4: 통과 확인**

```bash
xcodegen generate && xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n5b.log 2>&1; tail -3 /tmp/n5b.log
```

Expected: `** TEST SUCCEEDED **` (51 + 3 = 54 tests).

- [ ] **Step 5: 커밋**

```bash
git add Sources/Services/NotionExporter.swift Tests/NotionExporterTests.swift stepkeeper-apple.xcodeproj
git commit -m "feat: NotionExporter — 업로드·배칭 오케스트레이션"
```

---

### Task 6: 설정 섹션 + DocumentView 버튼 통합

**Files:**
- Modify: `Sources/Views/SettingsView.swift`, `Sources/Views/DocumentView.swift`

**Interfaces:**
- Consumes: `KeychainStore.notionToken`/`Settings.notionParentPageKey`/`NotionPageID`(Task 2), `NotionExporter`/`NotionAPI`(Task 4·5)
- Produces: 설정의 "Notion 내보내기" 섹션, DocumentView의 "Notion으로 보내기" 버튼 + 진행/성공 링크/실패 메시지.

- [ ] **Step 1: SettingsView에 Notion 섹션 추가**

`Sources/Views/SettingsView.swift` — `@State` 목록에 추가:

```swift
    @AppStorage(Settings.notionParentPageKey) private var notionParentPage = ""
    @State private var notionToken = ""
    @State private var notionSavedAt: Date?
    @State private var notionSaveError: String?
```

"stepkeeper 서버" 섹션 아래에 섹션 추가:

```swift
                Section {
                    SecureField("Notion 통합 토큰", text: $notionToken)
                        .textFieldStyle(.roundedBorder)
                    Button("토큰 저장") {
                        do {
                            try KeychainStore.notionToken.save(
                                notionToken.trimmingCharacters(in: .whitespacesAndNewlines))
                            notionSaveError = nil
                            notionSavedAt = Date()
                        } catch {
                            notionSavedAt = nil
                            notionSaveError = "저장 실패 — 다시 시도해 주세요"
                        }
                    }
                    .disabled(notionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if notionSavedAt != nil {
                        Label("저장됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    }
                    if let notionSaveError {
                        Label(notionSaveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                    TextField("부모 페이지 (URL 또는 ID 붙여넣기)", text: $notionParentPage)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Link("통합(integration) 만들기",
                         destination: URL(string: "https://www.notion.so/my-integrations")!)
                        .font(.callout)
                } header: { Text("Notion 내보내기") } footer: {
                    Text("통합을 만들고, 대상 페이지의 ··· 메뉴 → 연결에서 그 통합을 추가해야 업로드할 수 있습니다.")
                }
```

`.onAppear`에 한 줄 추가:

```swift
                notionToken = (try? KeychainStore.notionToken.load()) ?? ""
```

- [ ] **Step 2: DocumentView에 Notion 내보내기 추가**

`Sources/Views/DocumentView.swift` — `@State` 목록에 추가:

```swift
    @State private var exportingNotion = false
    @State private var notionPageURL: URL?
```

툴바 `ToolbarItemGroup`에 버튼 추가 (기존 "폴더로 저장" 버튼 뒤):

```swift
                Button {
                    exportToNotion()
                } label: {
                    Label("Notion으로 보내기", systemImage: "arrow.up.doc")
                }
                .disabled(exportingNotion)
```

본문 `if let exportMessage { ... }` 앞에 추가:

```swift
                if exportingNotion {
                    ProgressView("Notion 업로드 중…")
                }
                if let notionPageURL {
                    Link("Notion에서 열기", destination: notionPageURL)
                        .font(.callout)
                }
```

`shareItems` 프로퍼티 아래에 메서드 추가:

```swift
    private func exportToNotion() {
        guard let token = try? KeychainStore.notionToken.load(), !token.isEmpty,
              let parent = NotionPageID.normalize(
                UserDefaults.standard.string(forKey: Settings.notionParentPageKey) ?? "") else {
            exportMessage = "설정에서 Notion 토큰과 부모 페이지를 입력하세요"
            return
        }
        exportingNotion = true
        notionPageURL = nil
        let exporter = NotionExporter(api: NotionAPI(token: token), parentPageID: parent)
        let target = document
        Task {
            do {
                let url = try await exporter.export(document: target)
                notionPageURL = url
                exportMessage = "Notion 업로드 완료"
            } catch {
                exportMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Notion 내보내기에 실패했습니다"
            }
            exportingNotion = false
        }
    }
```

- [ ] **Step 3: 빌드·회귀 + 시뮬레이터 확인**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n6.log 2>&1; tail -3 /tmp/n6.log
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build > /tmp/n6b.log 2>&1; tail -3 /tmp/n6b.log
```

Expected: TEST SUCCEEDED(54) / BUILD SUCCEEDED. 이어서 M1 E2E로 문서를 하나 만들고 시뮬레이터 스크린샷으로 문서 화면 툴바에 Notion 버튼이 보이는지 확인(`./scripts/e2e-m1.sh` 후 앱을 수동 launch, `xcrun simctl io "iPhone 17 Pro" screenshot build/n6-doc.png`). 버튼 동작 자체(실토큰)는 Task 7의 사용자 항목.

- [ ] **Step 4: 커밋**

```bash
git add Sources/Views stepkeeper-apple.xcodeproj
git commit -m "feat: 설정·문서 화면에 Notion 내보내기 통합"
```

---

### Task 7: 문서화 + 전체 회귀 (체크포인트)

**Files:**
- Modify: `docs/TESTING.md`, `README.md`

**Interfaces:** 없음 (마감 태스크)

- [ ] **Step 1: TESTING.md에 Notion 항목 추가**

체크리스트 끝(13번 뒤)에 추가:

```markdown
14. [ ] Notion 내보내기: notion.so/my-integrations에서 통합 생성 → 대상 페이지 ··· 메뉴 → 연결에 통합 추가 → 설정에 토큰·페이지 URL 입력 → 문서 화면 "Notion으로 보내기" → 노션에서 이미지·타임스탬프 링크 확인. 오류 케이스: 잘못된 토큰(401 안내), 연결 안 된 페이지(부모 페이지 안내)
```

- [ ] **Step 2: README 갱신**

`README.md`의 스크립트 목록에 추가:

```markdown
- `scripts/make-notion-golden.py` — 코어 build_notion_blocks로 Notion 블록 골든 재생성
```

그리고 제품 설명 문단(첫 문단) 끝에 한 문장 추가:

```markdown
완성된 문서는 공유시트·폴더 저장 외에 Notion 페이지로도 직접 내보낼 수 있다(사용자 통합 토큰).
```

- [ ] **Step 3: 전체 회귀**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/n7.log 2>&1; tail -3 /tmp/n7.log
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test > /tmp/n7b.log 2>&1; tail -3 /tmp/n7b.log
./scripts/e2e-m1.sh && ./scripts/e2e-m2.sh
```

Expected: 양 destination `** TEST SUCCEEDED **`(54 tests) + M1/M2 E2E PASS.

- [ ] **Step 4: 커밋 (체크포인트: 사용자 보고)**

```bash
git add docs/TESTING.md README.md
git commit -m "docs: Notion 내보내기 안내 (TESTING/README)"
git log --oneline -8
```

**사용자 보고**: 구현 요약 + 실토큰 E2E 절차(TESTING.md 14번) 안내.

---

## 태스크 순서와 의존성

Task 1(스크립트) → 2(정규화·키) → 3(빌더+골든) → 4(API) → 5(Exporter) → 6(UI 통합) → 7(문서·회귀, **체크포인트**). 전부 직렬.

