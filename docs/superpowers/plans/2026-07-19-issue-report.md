# stepkeeper v1.2 원탭 이상 신고 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 후보/문서 이상 시 🚩 원탭 신고 — URL·분석 원본·픽·사유를 서버 JSONL로 축적 (프롬프트 개선 실패 사례 수집).

**Architecture:** 2레포 — stepkeeper-server에 `/v1/reports`(JSONL append, stateless 예외), stepkeeper-apple에 신고 시트+진입점 2곳+API 메서드. 스펙: `docs/superpowers/specs/2026-07-19-issue-report-design.md`.

**Tech Stack:** FastAPI/pydantic Literal / SwiftUI sheet / JSONSerialization.

## Global Constraints

- 앱: 모든 xcodebuild 앞에 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, 로그 /tmp 리다이렉트. 서버: venv 사용(`.venv/bin/python`), 코어 수정 금지.
- 신고 전송에 `X-Gemini-Key` 불필요(서버도 요구하지 않음). 페이로드의 analysis는 **rawAnalysis 원본 그대로**(재인코딩 금지 — JSONSerialization 병합).
- UI 문구 한국어 아래 코드 그대로. docs/superpowers/ 수정 금지. 커밋 메시지: 서버는 영어 관례, 앱은 한국어 관례.
- 서버 reason 허용값: `candidates | guide_text | steps | other` (그 외 422). note 최대 2000자.

---

### Task 1: 서버 — POST /v1/reports (Work from: /Users/choejunhwan/dev/stepkeeper-server)

**Files:**
- Modify: `app.py`(모델+엔드포인트+독스트링 한 줄), `README.md`(API 절 + stateless 예외 기록)
- Create: `tests/test_reports.py`

**Interfaces:**
- Produces: `POST /v1/reports` — body 스펙 2절 페이로드, 응답 `{"status": "ok"}`. 저장: `${STEPKEEPER_REPORTS:-reports}/reports.jsonl`에 `received_at`(UTC ISO8601) 붙여 append. Task 2가 호출.

- [ ] **Step 1: 기존 테스트 스타일 파악**

`tests/` 안의 기존 테스트 하나를 읽고(TestClient 사용 여부·픽스처 패턴) 같은 스타일로 작성하라.

- [ ] **Step 2: 실패하는 테스트 작성**

`tests/test_reports.py` (기존 스타일에 맞춰 조정하되 검증 항목은 유지):

```python
import json
import os
import tempfile
import unittest

from fastapi.testclient import TestClient


def make_payload(**overrides):
    payload = {
        "url": "https://m.youtube.com/watch?v=GziiD4XqCpc",
        "video_id": "GziiD4XqCpc",
        "reason": "candidates",
        "note": "후보 3장이 전부 인트로 화면",
        "profile": "recipe",
        "language": "ko",
        "analysis": {"title": "t", "_model": "gemini-flash-lite-latest"},
        "picks": {"vg-1": "none"},
        "client": "apple/0.1.0",
    }
    payload.update(overrides)
    return payload


class ReportsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["STEPKEEPER_REPORTS"] = self.tmp.name
        import app  # noqa: WPS433 — env 설정 후 임포트
        self.client = TestClient(app.app)

    def tearDown(self):
        os.environ.pop("STEPKEEPER_REPORTS", None)
        self.tmp.cleanup()

    def test_appends_jsonl_with_received_at(self):
        response = self.client.post("/v1/reports", json=make_payload())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})
        path = os.path.join(self.tmp.name, "reports.jsonl")
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        self.assertEqual(len(lines), 1)
        entry = json.loads(lines[0])
        self.assertEqual(entry["video_id"], "GziiD4XqCpc")
        self.assertEqual(entry["analysis"]["_model"], "gemini-flash-lite-latest")
        self.assertIn("received_at", entry)

    def test_two_reports_two_lines(self):
        self.client.post("/v1/reports", json=make_payload())
        self.client.post("/v1/reports", json=make_payload(reason="other"))
        path = os.path.join(self.tmp.name, "reports.jsonl")
        with open(path, encoding="utf-8") as f:
            self.assertEqual(len(f.readlines()), 2)

    def test_rejects_bad_reason_and_long_note(self):
        self.assertEqual(
            self.client.post("/v1/reports", json=make_payload(reason="nonsense")).status_code, 422)
        self.assertEqual(
            self.client.post("/v1/reports", json=make_payload(note="x" * 2001)).status_code, 422)
```

주의: `STEPKEEPER_REPORTS`를 요청 시점에 읽는 구현이어야 setUp의 env가 먹는다(모듈 로드 시점 고정 금지).

- [ ] **Step 3: 실패 확인**

```bash
cd /Users/choejunhwan/dev/stepkeeper-server && .venv/bin/python -m unittest tests.test_reports -v 2>&1 | tail -5
```

Expected: 404 assertion 실패(엔드포인트 없음).

- [ ] **Step 4: 구현**

`app.py` — 임포트에 `import json`, `from datetime import datetime, timezone`, `from typing import Literal` 추가. `DocumentRequest` 아래에:

```python
class ReportRequest(BaseModel):
    """One-tap issue report from clients — failure-case corpus for prompt iteration."""
    url: str
    video_id: str
    reason: Literal["candidates", "guide_text", "steps", "other"]
    note: str = Field(default="", max_length=2000)
    profile: str = "generic"
    language: str = "ko"
    analysis: dict
    picks: dict[str, str] = Field(default_factory=dict)
    client: str = ""
```

`/v1/documents` 핸들러 아래에:

```python
@app.post("/v1/reports")
def submit_report(req: ReportRequest):
    """Append the report as one JSONL line. The only stateful endpoint —
    an explicit exception to the stateless design, for the feedback loop."""
    reports_dir = Path(os.environ.get("STEPKEEPER_REPORTS", "reports"))
    reports_dir.mkdir(parents=True, exist_ok=True)
    entry = req.model_dump()
    entry["received_at"] = datetime.now(timezone.utc).isoformat()
    with (reports_dir / "reports.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return {"status": "ok"}
```

모듈 독스트링의 엔드포인트 목록에 한 줄 추가: `- POST /v1/reports    — one-tap issue report (JSONL append; the stateless exception).`

- [ ] **Step 5: 전체 테스트 + README**

```bash
.venv/bin/python -m unittest discover -s tests 2>&1 | tail -3
```

Expected: 기존+신규 전부 OK. `README.md`의 API 절에 `/v1/reports` 블록 추가(요청/응답/저장 경로) + "the only endpoint that stores anything — an explicit exception to the stateless design (`STEPKEEPER_REPORTS`, default `reports/`)" 명시. 표(Concern/Owner)에도 한 줄: `Failure reports | server /v1/reports (JSONL, opt-in one-tap)`.

- [ ] **Step 6: 커밋**

```bash
git add app.py tests/test_reports.py README.md
git commit -m "reports: one-tap issue report endpoint (JSONL append, stateless exception)"
```

---

### Task 2: 앱 — 신고 시트 + 진입점 2곳 (Work from: /Users/choejunhwan/dev/stepkeeper-apple)

**Files:**
- Create: `Sources/Models/IssueReport.swift`, `Sources/Views/ReportSheet.swift`
- Modify: `Sources/Services/StepkeeperAPI.swift`(submitReport), `Sources/Views/CandidatePickerView.swift`, `Sources/Views/DocumentView.swift`, `Tests/StepkeeperAPITests.swift`(신고 테스트 추가)

**Interfaces:**
- Consumes: Task 1의 `/v1/reports` 계약, `StepkeeperAPIError`(기존), `AppModel.pendingResult`/`captures`(v1 T11), `SavedDocument`(v1 T8)
- Produces: `ReportReason`(enum, rawValue 서버 문자열), `IssueReport`, `StepkeeperAPI.submitReport(_:) async throws`, `ReportSheet(submit:)`.

- [ ] **Step 1: 모델 작성**

`Sources/Models/IssueReport.swift`:

```swift
import Foundation

/// 원탭 신고 사유 — rawValue가 서버 계약 문자열
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case candidates
    case guideText = "guide_text"
    case steps
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .candidates: "후보 장면 부적합"
        case .guideText: "가이드 문구 이상"
        case .steps: "단계 누락·오류"
        case .other: "기타"
        }
    }
}

struct IssueReport: Sendable {
    var url: String
    var videoId: String
    var reason: ReportReason
    var note: String
    var profile: String
    var language: String
    /// 서버가 반환했던 분석 원본 그대로 (재인코딩 금지)
    var rawAnalysis: Data
    var picks: [String: String]
    var client: String

    static var clientTag: String {
        "apple/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")"
    }
}
```

- [ ] **Step 2: 실패하는 테스트 추가**

`Tests/StepkeeperAPITests.swift`의 스위트에 테스트 추가 (기존 `makeAPI()`/`reset()` 재사용):

```swift
    @Test func submitReportPostsPayloadWithoutKey() async throws {
        defer { reset() }
        StepkeeperAPIStub.shared.handler = { _ in (200, Data(#"{"status": "ok"}"#.utf8)) }
        let raw = try JSONSerialization.data(withJSONObject: ["title": "t", "_model": "m"])
        let report = IssueReport(
            url: "https://m.youtube.com/watch?v=GziiD4XqCpc", videoId: "GziiD4XqCpc",
            reason: .candidates, note: "메모", profile: "recipe", language: "ko",
            rawAnalysis: raw, picks: ["vg-1": "none"], client: "apple/test")
        try await makeAPI().submitReport(report)

        let request = try #require(StepkeeperAPIStub.shared.capturedRequest)
        #expect(request.url?.path == "/v1/reports")
        #expect(request.value(forHTTPHeaderField: "X-Gemini-Key") == nil)   // 키 불필요 경로
        let body = try JSONSerialization.jsonObject(
            with: try #require(StepkeeperAPIStub.shared.capturedBody)) as! [String: Any]
        #expect(body["reason"] as? String == "candidates")
        #expect((body["analysis"] as? [String: Any])?["_model"] as? String == "m")   // 원본 병합
        #expect((body["picks"] as? [String: String]) == ["vg-1": "none"])
    }

    @Test func submitReportMapsServerFailure() async throws {
        defer { reset() }
        StepkeeperAPIStub.shared.handler = { _ in (500, Data(#"{"detail": "disk"}"#.utf8)) }
        let report = IssueReport(
            url: "u", videoId: "v", reason: .other, note: "", profile: "generic",
            language: "ko", rawAnalysis: Data("{}".utf8), picks: [:], client: "apple/test")
        do {
            try await makeAPI().submitReport(report)
            Issue.record("should throw")
        } catch let error as StepkeeperAPIError {
            guard case .server(500, _) = error else { Issue.record("wrong: \(error)"); return }
        }
    }
```

- [ ] **Step 3: RED 확인 → submitReport 구현**

RED: `cannot find 'IssueReport'` 또는 `submitReport` 없음. `Sources/Services/StepkeeperAPI.swift`의 `analyze` 아래에 추가:

```swift
    /// 원탭 이상 신고 — X-Gemini-Key 불필요, analysis는 rawAnalysis 원본 병합
    func submitReport(_ report: IssueReport) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/v1/reports"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let analysisObject = (try? JSONSerialization.jsonObject(with: report.rawAnalysis)) ?? [String: Any]()
        let body: [String: Any] = [
            "url": report.url,
            "video_id": report.videoId,
            "reason": report.reason.rawValue,
            "note": report.note,
            "profile": report.profile,
            "language": report.language,
            "analysis": analysisObject,
            "picks": report.picks,
            "client": report.client,
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
        guard (200...299).contains(http.statusCode) else {
            throw StepkeeperAPIError.server(http.statusCode, Self.detail(from: data))
        }
    }
```

- [ ] **Step 4: ReportSheet 작성**

`Sources/Views/ReportSheet.swift`:

```swift
import SwiftUI

/// 원탭 이상 신고 시트 — submit 클로저가 실제 전송을 수행하고, 실패 메시지(성공 시 nil)를 반환한다.
struct ReportSheet: View {
    let submit: (ReportReason, String) async -> String?
    @State private var reason: ReportReason = .candidates
    @State private var note = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var done = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("사유", selection: $reason) {
                    ForEach(ReportReason.allCases) { reason in
                        Text(reason.label).tag(reason)
                    }
                }
                Section("메모 (선택)") {
                    TextEditor(text: $note).frame(minHeight: 80)
                }
                Section {
                    if done {
                        Label("신고 완료 — 개선에 사용할게요!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            sending = true
                            errorMessage = nil
                            Task {
                                errorMessage = await submit(reason, note)
                                sending = false
                                if errorMessage == nil {
                                    done = true
                                    try? await Task.sleep(for: .seconds(1))
                                    dismiss()
                                }
                            }
                        } label: {
                            if sending { ProgressView() } else { Text("보내기") }
                        }
                        .disabled(sending)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                    }
                } footer: {
                    Text("영상 주소와 분석 결과, 선택 내역이 내 서버로 전송됩니다.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("이상 신고")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
```

- [ ] **Step 5: 진입점 2곳 배선**

**CandidatePickerView** — `@State private var reporting = false` 추가, "문서 만들기" 버튼 아래에:

```swift
                Button {
                    reporting = true
                } label: {
                    Label("후보가 이상해요", systemImage: "flag")
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
```

ScrollView 마지막(.onAppear 위)에:

```swift
        .sheet(isPresented: $reporting) {
            ReportSheet { reason, note in
                await model.submitIssueReport(reason: reason, note: note, picks: picks)
            }
        }
```

**AppModel** — 픽커 진입점용 헬퍼 추가(`finishPicking` 아래):

```swift
    /// 픽커 화면의 원탭 신고 — pendingResult 기반. 성공 nil, 실패 시 사용자 메시지 반환.
    func submitIssueReport(reason: ReportReason, note: String,
                           picks: [String: String]) async -> String? {
        guard let result = pendingResult else { return "신고할 분석 정보가 없습니다" }
        guard let serverURL = URL(string: defaults.string(forKey: Settings.serverURLKey)
                                  ?? Settings.defaultServerURL) else {
            return "서버 URL이 올바르지 않습니다 — 설정을 확인하세요"
        }
        let report = IssueReport(
            url: "https://m.youtube.com/watch?v=\(result.videoId)",
            videoId: result.videoId, reason: reason, note: note,
            profile: result.analysis.profile ?? profile,
            language: result.analysis.outputLanguage
                ?? defaults.string(forKey: Settings.languageKey) ?? Settings.defaultLanguage,
            rawAnalysis: result.rawAnalysis, picks: picks, client: IssueReport.clientTag)
        do {
            try await makeAPI(serverURL).submitReport(report)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "신고 전송에 실패했습니다"
        }
    }
```

**DocumentView** — `@State private var reporting = false` 추가, 툴바 그룹에 버튼 추가:

```swift
                Button {
                    reporting = true
                } label: {
                    Label("문서가 이상해요", systemImage: "flag")
                }
```

`.fileImporter(...)` 아래에:

```swift
        .sheet(isPresented: $reporting) {
            ReportSheet { reason, note in
                await submitReport(reason: reason, note: note)
            }
        }
```

`exportToNotion()` 아래에 메서드 추가:

```swift
    private func submitReport(reason: ReportReason, note: String) async -> String? {
        guard let serverURL = URL(string: UserDefaults.standard.string(forKey: Settings.serverURLKey)
                                  ?? Settings.defaultServerURL) else {
            return "서버 URL이 올바르지 않습니다 — 설정을 확인하세요"
        }
        guard let raw = try? Data(contentsOf:
            document.folder.appendingPathComponent("analysis.json")) else {
            return "분석 원본을 읽지 못했습니다"
        }
        let report = IssueReport(
            url: "https://m.youtube.com/watch?v=\(document.meta.videoId)",
            videoId: document.meta.videoId, reason: reason, note: note,
            profile: document.meta.profile, language: document.meta.language,
            rawAnalysis: raw, picks: document.picks, client: IssueReport.clientTag)
        do {
            try await StepkeeperAPI(baseURL: serverURL).submitReport(report)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "신고 전송에 실패했습니다"
        }
    }
```

- [ ] **Step 6: GREEN + 빌드 + 커밋**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=macOS' test > /tmp/rep1.log 2>&1; grep -E "Test run|TEST" /tmp/rep1.log | tail -2
xcodebuild -project stepkeeper-apple.xcodeproj -scheme Stepkeeper -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build > /tmp/rep2.log 2>&1; tail -1 /tmp/rep2.log
git add Sources Tests stepkeeper-apple.xcodeproj
git commit -m "feat: 원탭 이상 신고 — 픽커·문서 진입점 + /v1/reports 전송"
```

Expected: 55 tests(53+2) 그린, iOS BUILD SUCCEEDED.

---

## 순서: Task 1(서버) → 컨트롤러가 실서버 재시작 → Task 2(앱). 완료 시 사용자 보고(재빌드 안내).
