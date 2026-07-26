# stepkeeper v1.2: 원탭 이상 신고 설계

2026-07-19 승인. 후보/문서가 이상할 때 사용자가 🚩 버튼으로 신고 → 영상 URL·분석 결과·픽·사유를 개인 서버에 축적 → 프롬프트 개선 루프의 실패 사례 데이터로 활용. **자동 전송 아님** — 명시적 버튼(라벨된 실패만 수집, 프라이버시 고지 포함).

## 1. 범위

- **stepkeeper-server**: `POST /v1/reports` — JSONL append 저장. **stateless 원칙의 명시적 예외**(서버 최초의 저장 기능): README에 기록. 인증 없음(로컬 개인 서버; Gemini 키 불필요한 경로).
- **stepkeeper-apple**: 신고 시트(사유 4종+메모+고지문) + 진입점 2곳(픽커 "후보가 이상해요", 문서 뷰 "문서가 이상해요") + `StepkeeperAPI.submitReport`.
- 범위 밖: 프레임 이미지 첨부(v2 — URL로 재현 가능해 불필요), 신고 열람 UI, 코어 feedback.py 자동 연계(수집 후 수동 활용).

## 2. 페이로드 (재현 가능 최소 집합)

```json
{
  "url": "https://m.youtube.com/watch?v=...",
  "video_id": "GziiD4XqCpc",
  "reason": "candidates | guide_text | steps | other",
  "note": "자유 메모 (최대 2000자)",
  "profile": "...", "language": "...",
  "analysis": { 서버가 반환했던 원본 그대로 (rawAnalysis) },
  "picks": {"vg-1": "center", ...},
  "client": "apple/<앱 버전>"
}
```

서버는 `received_at`(UTC ISO8601)을 붙여 `reports/reports.jsonl`(경로는 `STEPKEEPER_REPORTS` 환경변수로 변경 가능)에 한 줄씩 append. 응답 `{"status": "ok"}`.

## 3. 앱 설계

- `StepkeeperAPI.submitReport(_ report: IssueReport) async throws` — 같은 baseURL, `X-Gemini-Key` 불필요. 실패는 기존 에러 매핑 재사용(네트워크/서버).
- `IssueReport` 모델: 위 페이로드 필드. reason은 enum(`candidates/guideText/steps/other` — rawValue 서버 문자열).
- `ReportSheet` 뷰: 사유 Picker(후보 장면 부적합 / 가이드 문구 이상 / 단계 누락·오류 / 기타) + TextEditor 메모 + 고지문 "영상 주소와 분석 결과, 선택 내역이 내 서버로 전송됩니다." + 보내기(진행 표시)/취소. 성공 시 "신고 완료 — 개선에 사용할게요!" 후 자동 닫힘.
- 진입점: ①CandidatePickerView 하단 "🚩 후보가 이상해요" — 데이터는 `pendingResult`(rawAnalysis)+현재 picks(미확정 상태 그대로) ②DocumentView 툴바 "🚩 문서가 이상해요" — 데이터는 문서 폴더의 analysis.json(raw)+저장된 picks.
- AppModel: 픽커 진입점을 위해 `pendingResult`/`captures` 접근은 기존 internal 그대로 사용. URL은 `https://m.youtube.com/watch?v=<videoId>` 조립.

## 4. 검증

- 서버: unittest — 정상 append(JSONL 라인 파싱 왕복), reason 검증(허용 외 422), note 2000자 초과 422, received_at 존재. 임시 디렉토리(`STEPKEEPER_REPORTS`) 사용.
- 앱: `submitReport` 스텁 테스트(경로·페이로드·키 헤더 부재), `IssueReport` 인코딩 필드명. 시트 UI는 빌드+수동.
- 회귀: 양 레포 기존 테스트 그린.

## 5. 프라이버시

전송은 사용자 버튼 탭 시에만. 시트에 전송 내용 고지 상시 표시. 서버 저장은 로컬 파일(개인 서버) — 외부 서비스 전송 없음.

## 6. (승인 확장) GitHub 이슈 브리지 — 2026-07-19

신고를 비공개 repo **zlej123/stepkeeper-reports**의 이슈로도 자동 생성 (공개 코어 repo가 아닌 이유: 시청 영상 URL·메모의 공개 노출 방지 — 사용자 결정).

- 서버가 JSONL append **후** 이슈 생성 시도. **JSONL이 원천 데이터** — 이슈 생성 실패는 신고 실패가 아니며(로그만 남기고 200 유지), 응답에 `"github": "ok" | "skipped" | "failed"` 필드로 상태 노출.
- 전송 수단: **gh CLI subprocess** (`gh api repos/<repo>/issues`) — 사용자의 gh 키체인 인증 재사용, 서버에 토큰 저장 없음. gh 부재/미인증이면 skipped.
- **opt-in**: 환경변수 `STEPKEEPER_REPORTS_REPO`(예: `zlej123/stepkeeper-reports`)가 설정된 경우에만 시도 — 공개 서버 코드의 기본 동작은 JSONL만.
- 이슈 형식: 제목 `[report:<reason>] <analysis title> (<video_id>)`, 본문 = 사유 라벨·영상 링크·메모·프로파일/언어·client + `<details>`로 접힌 분석 JSON, 라벨 `report`, `report:<reason>`.
- 검증: subprocess.run 모킹 — 정상 페이로드(제목/본문/라벨), env 미설정 시 skipped(호출 0회), gh 실패 시에도 200+failed. 배포 환경(gh 없는 서버)용 토큰 방식은 v2 기록.
