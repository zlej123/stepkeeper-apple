# stepkeeper-apple v1.3: 서버리스 설계 (일반 사용자 우선)

2026-07-19 승인. 기준: **일반 사용자가 쉽게** — 설정은 Gemini 키 하나, 분석은 서버 없이, 신고는 설정 제로. 참고 구현: 확장 `bg.js`의 direct 모드(검증됨).

## 1. 목표와 범위

- **직접 Gemini 분석**: 서버 URL이 비어 있으면(신규 기본값) 앱이 Gemini `generateContent`를 직접 호출. skill-core 프롬프트·스키마를 앱에 번들. 서버 모드는 URL 입력 시 기존 그대로(개발·프롬프트 반복용).
- **신고 경로 정리**: 신고 대상을 분석 서버와 분리(`reportServerURL`) — 릴리스 기본값은 개발자 호스팅 수집기 주소(배포 후 상수 교체, 그 전까지 빈 값이면 신고 버튼이 안내만). 일반 사용자는 GitHub·서버 개념 노출 없음.
- **수집기 배포 준비**: 서버 브리지에 `GITHUB_TOKEN` 방식 추가(gh CLI 없는 Cloud Run용 — 토큰 있으면 urllib, 없고 gh 있으면 gh, 둘 다 없으면 skipped). 배포 가이드 문서(사용자 실행).
- 트레이드오프(기록): 직접 모드는 프롬프트가 앱 번들에 고정 — 프롬프트 개선은 앱 업데이트 필요. 서버 모드가 대안으로 상존.
- 범위 밖: 실제 Cloud Run 배포(사용자 액션), 앱 내 신고 기본 URL의 실제 값 주입(배포 후), auto-pick.

## 2. 직접 Gemini 분석 (bg.js analyzeDirect 포팅)

### 2.1 자산 번들
`scripts/sync-assets.sh` 확장: 기존 template.md에 더해 `profiles/{generic,recipe}/{prompt.md,schema.json}` + `engine/rules.md`를 `Resources/skill-core/`로 복사(rules.md는 `Resources/skill-core/engine/`). 폴더 레퍼런스라 project.yml 무변경.

### 2.2 GeminiAPI (`Sources/Services/GeminiAPI.swift`)
- `buildPrompt(profile:duration:language:maxGuides:)`: 번들 prompt.md에서 `{{RULES}}`→rules.md 내용, `{DURATION}`→`hms(duration)`, `{OUTPUT_LANGUAGE}`→language, `{MAX_VISUAL_GUIDES}`→String(maxGuides) 치환 (bg.js buildPrompt와 동일 — replacingOccurrences 전체 치환).
- `loadSchema(profile:)`: 번들 schema.json 파싱 후 `$schema`/`$comment`/`title` 키 제거.
- `analyze(videoURL:profile:language:maxGuides:duration:geminiKey:) async throws -> AnalyzeResult`:
  - POST `https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent`, 헤더 `x-goog-api-key: <키>`(로그·에러 비노출 규칙 동일), 타임아웃 180초
  - body: `{"contents":[{"parts":[{"file_data":{"file_uri":"<영상 URL>"}},{"text":"<프롬프트>"}]}],"generationConfig":{"response_mime_type":"application/json","response_json_schema":<스키마>,"temperature":0.2}}`
  - 429→`StepkeeperAPIError.rateLimited`, 기타 비2xx→`.modelFailure("Gemini 오류 (HTTP n)")`, 응답 `candidates[0].content.parts[0].text` 부재→`.invalidResponse` — **기존 에러 타입 재사용**(UI 분기 무변경)
  - text(JSON 문자열) 파싱 → `normalize` → 메타 주입(`_duration`,`_profile`,`_output_language`) → `AnalyzeResult(videoId, analysis, rawAnalysis)`(rawAnalysis = 정규화+메타 주입된 dict 직렬화 — 저장·신고 형식 서버 모드와 동일 유지)
- 모델명 상수 `gemini-flash-lite-latest`(설정 비노출 — v1 결정 유지).

### 2.3 normalize 포팅 (`Sources/Services/AnalysisNormalizer.swift`)
bg.js와 동일 부분집합: steps `t_start`/`t_end`, guides `best_visual_timestamp`의 MM:SS 문자열→초 Int(`mmssToSec` — 이미 숫자/nil이면 그대로). dict(JSONSerialization) 레벨에서 변환 후 `Analysis` 디코딩(스키마 구조화 출력이 필수 필드를 강제하므로 서버 normalize의 보완 로직(source_phrase/importance/TYPE_ALIASES)은 미포팅 — 확장과 동일 범위, 기록).

### 2.4 모드 라우팅
- `Settings.defaultServerURL`을 `""`로 변경(직접 모드가 신규 기본). 기존 설치의 저장값(127.0.0.1)은 유지됨 — 설정 footer에 "비우면 서버 없이 직접 분석" 안내 추가.
- `AppModel.performAnalysis`: serverURL 트림 결과가 비면 `GeminiAPI` 직접, 아니면 기존 `StepkeeperAPI`. 이후 파이프(캡처·문서·저장)는 공용 `AnalyzeResult`라 무변경.
- E2E: 기존 e2e-m1/m2는 서버 URL을 명시 설정해 그대로 그린 유지(스텁 서버 경로). DEBUG 훅에 `STEPKEEPER_SERVER_URL` env 지원 추가(E2E가 명시 주입 — registerDefaults 변경과 무관하게 결정적).

## 3. 신고 경로 정리

- `Settings.reportServerURLKey` 신설, 기본 `ReportCollector.defaultURL` 상수(현재 `""` — 배포 후 호스팅 주소로 교체하는 단일 지점, 주석 명시).
- 신고 대상 결정: `reportServerURL` 비어 있으면 → `serverURL`(개발자 로컬 겸용) → 둘 다 비면 ReportSheet 열기 전에 "신고 수집 서버가 설정되지 않았습니다 — 설정에서 입력하거나 앱 업데이트를 기다려 주세요" 안내(전송 시도 없음).
- 설정 화면: "신고 수집 서버 (선택)" 필드 — footer "비워두면 분석 서버로 보냅니다. 일반 배포판은 기본 수집기가 내장됩니다."
- `AppModel.submitIssueReport`/`DocumentView.submitReport`가 위 결정 로직 공유(작은 헬퍼 `ReportCollector.resolveURL(defaults:) -> URL?`).

## 4. 서버: 토큰 방식 브리지 (stepkeeper-server)

`_create_github_issue`: `GITHUB_TOKEN` env 있으면 urllib로 `POST https://api.github.com/repos/<repo>/issues`(헤더 `Authorization: Bearer`, `Accept: application/vnd.github+json`, 코어 export.py의 notion_request 스타일) — 성공 2xx→ok, 실패→failed. 토큰 없으면 기존 gh CLI 경로, 둘 다 없으면 skipped. 테스트: urlopen 모킹(토큰 경로 페이로드·헤더), 우선순위(토큰>gh), 기존 gh 테스트 그린 유지.

## 5. 배포 가이드 (`stepkeeper-server/docs/deploy.md`)

Cloud Run 기준: `gcloud run deploy --source .` + env(`STEPKEEPER_REPORTS_REPO`, `GITHUB_TOKEN`(fine-grained, Issues RW, 대상 repo만), `STEPKEEPER_REPORTS`(볼륨 or 무시)) + 주의(JSONL은 컨테이너 휘발 — 이슈가 영속 기록, JSONL 영속 원하면 버킷 마운트는 후속) + 배포 후 앱 `ReportCollector.defaultURL` 교체 절차. 사용자 실행 문서(자동화 안 함).

## 6. 검증

- 유닛: buildPrompt 치환(플레이스홀더 4종 잔존 없음 단언), loadSchema 키 제거, mmssToSec(MM:SS/이미 Int/null/"1:02"), GeminiAPI 스텁(x-goog-api-key 헤더·file_uri·response_json_schema 포함, 429/오류 매핑, 정상 응답→Analysis 필드), AppModel 라우팅(빈 serverURL→Gemini 스텁 경로, 있으면 기존), ReportCollector.resolveURL 3분기. 서버: 토큰 브리지 4케이스.
- 골든·기존 55(앱)/13(서버) 회귀 그린. e2e-m1/m2 그린(서버 URL 명시 주입).
- 실키 직접 모드 E2E는 수동(TESTING.md 항목 추가): 서버 URL 비우고 분석 → 서버 프로세스 없이 완주 확인.

## 7. 마일스톤

S1 자산 번들+normalize+GeminiAPI(+테스트) → S2 라우팅+설정 문구+E2E env 주입 → S3 신고 경로 정리 → S4 서버 토큰 브리지+배포 가이드 → S5 문서(TESTING/README)+전체 회귀. 완료 시 사용자 보고(직접 모드 수동 확인 안내).
