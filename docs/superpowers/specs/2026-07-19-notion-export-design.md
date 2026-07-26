# stepkeeper-apple v1.1: Notion 내보내기 설계

2026-07-19 브레인스토밍 승인분. 코어 v0.2.0의 `export.py` Notion 타깃(클라이언트사이드, 직접 파일 업로드 API)을 앱에 포팅한다.

## 1. 목표와 범위

**목표**: 저장된 문서(SavedDocument = 분석+픽+이미지)를 사용자의 Notion 워크스페이스 페이지로 직접 업로드.

**v1.1 범위**: 직접 API 호출(BYOT), 설정(토큰 Keychain + 부모 페이지 ID), DocumentView "Notion으로 보내기", 블록 변환 코어 파리티(골든), 에러 매핑, TESTING 항목. 부수 유지보수로 **코어 v0.2.0 레이아웃 대응 스크립트 수정** 포함(6절).

**범위 밖**: 페이지 검색 피커(v1.2 후보), 데이터베이스 부모, 서버 export 엔드포인트, auto-pick.

## 2. 확정 결정 (사용자 승인)

1. **직접 호출(BYOT)** — 코어와 동일한 클라이언트사이드 방식. Gemini BYOK와 같은 철학(사용자 토큰, 우리 비용·저장 없음), 서버 무변경. 토큰은 Keychain에만.
2. **부모 페이지 ID를 설정에 입력** — 코어 `--parent`와 동일. 문서는 그 페이지의 하위 페이지로 생성.
3. **블록 매핑은 코어 `build_notion_blocks` 파리티** — v1의 골든 방법론 재사용: 코어 파이썬으로 기대 블록 JSON을 생성해 Swift 출력과 구조 비교.

## 3. 아키텍처

### 3.1 NotionAPI (`Sources/Services/NotionAPI.swift`)

- Base `https://api.notion.com/v1`, 헤더 `Authorization: Bearer <token>` + `Notion-Version: 2022-06-28`(코어와 동일 고정), 타임아웃 120초.
- 메서드: `createFileUpload() -> String`(id), `sendFileUpload(id:data:filename:mime:)`(multipart/form-data, 코어의 boundary 방식), `createPage(parentPageID:title:children:) -> (id: String, url: String?)`(children ≤100), `appendChildren(pageID:blocks:)`(≤100).
- `NotionAPIError`(LocalizedError, 한국어): `.invalidToken`(401), `.parentNotFound`(404), `.rateLimited`(429), `.api(Int, String)`(기타 — Notion 에러 body의 `message` 발췌), `.network(String)`. **토큰 값은 헤더 세팅 외 어디에도 등장 금지**(Gemini 키와 동일 규칙).
- 블록 타입: `typealias NotionBlock = [String: Any]`(JSONSerialization 호환). Exporter·API가 모두 nonisolated여서 블록이 같은 태스크 안에서만 흐르고 actor 경계를 넘지 않으므로 Swift 6 Sendable 문제 없음 — MainActor(뷰)와는 `SavedDocument`(입력)·`URL`(출력)만 오간다. 경계를 넘길 필요가 생기면 직렬화된 `Data`로 넘긴다.

### 3.2 NotionBlockBuilder (`Sources/Services/NotionBlockBuilder.swift`)

코어 `build_notion_blocks(data, video_id, image_ids)` 1:1 포팅:
- summary 문단 → "YouTube 원본" 링크 문단(`https://youtu.be/<vid>`) → (materials 있으면) `heading_2` "준비물" + `bulleted_list_item`("name amount") → `heading_2` "순서" + step별 `numbered_list_item`("summary — detail") → 가이드별 `quote`("💡 'phrase' 기준: guide_text") + 이미지 블록(`{type: image, image: {type: file_upload, file_upload: {id}}}`) 또는 timestamp 링크 문단("▶ 영상 M:SS에서 직접 확인", `?t=`). **timestamp null이고 이미지도 없으면 quote만**(코어와 동일 — md와 다르지만 코어 Notion 매핑이 원본).
- rich text 2000자 절단(코어 `_rich`), 헤딩 문구는 코어처럼 한국어 고정("준비물"/"순서" — recipe도 동일; 코어가 언어·프로파일 분기를 안 하므로 따라간다).
- 시그니처: `blocks(analysis: Analysis, videoId: String, imageUploadIds: [String: String])` — 반환은 3.1의 Sendable 경계 규칙을 따르는 블록 배열.

**파리티 검증**: `scripts/make-notion-golden.py`가 코어를 임포트해 v1 골든 fixture 3케이스(analysis.json)로 기대 블록 JSON 생성(이미지 업로드 id는 케이스 파일의 image_refs 키에 `fake-<guide_id>` 형식 주입) → `Tests/Fixtures/golden/<case>/expected-notion.json` 커밋 → Swift 테스트가 JSONSerialization 파싱 후 구조 동등 비교(NSDictionary/NSArray ==).

### 3.3 NotionExporter (`Sources/Services/NotionExporter.swift`)

- `export(document: SavedDocument) async throws -> URL`(생성된 페이지 URL; url 부재 시 notion.so/<id 하이픈 제거> 조립).
- 절차: ①picks에서 채택된 이미지(`vg-N.jpg`, 파일 존재 확인)를 guide id 순으로 전부 업로드(하나라도 실패 시 **페이지 생성 전에 중단** — 부분 페이지 방지) ②블록 생성 ③`createPage`(제목 = analysis.title, children 첫 100개) ④초과분 100개 단위 `appendChildren`.

### 3.4 설정

- `KeychainStore.notionToken = KeychainStore(service: "stepkeeper.notion-token")`.
- `Settings.notionParentPageKey`(@AppStorage). 입력은 노션 페이지 **URL을 그대로 붙여넣어도** 되게 32자 hex ID를 추출·정규화(하이픈 유무 허용)하는 `NotionPageID.normalize(_:) -> String?`를 두고, 저장·사용 시 적용.
- SettingsView에 "Notion 내보내기" 섹션: 토큰 SecureField+저장(기존 Gemini 키 패턴 — do/catch, 실패 라벨), 부모 페이지 필드, 안내 링크(`https://www.notion.so/my-integrations`) + 캡션 "통합(integration)을 만들고, 대상 페이지의 ··· 메뉴 → 연결에서 통합을 추가해야 합니다."

### 3.5 DocumentView

- 내보내기 툴바에 "Notion으로 보내기"(systemImage: "arrow.up.doc"). 토큰 또는 부모 페이지 미설정이면 설정 시트 유도 메시지. 실행 중 ProgressView(버튼 비활성), 성공 시 "Notion에서 열기" `Link` 표시, 실패 시 기존 exportMessage 패턴으로 에러 문구.

## 4. 에러 처리

| 상황 | 처리 |
|------|------|
| 401 | "Notion 토큰이 유효하지 않습니다 — 설정을 확인하세요" |
| 404 | "부모 페이지를 찾을 수 없습니다 — 페이지 ID와 통합 연결(페이지 ··· → 연결)을 확인하세요" (형식 오류 400은 NotionPageID.normalize가 원천 차단 — 3.1과 정합) |
| 429 | "Notion 요청 한도 도달 — 잠시 후 다시 시도해 주세요" |
| 네트워크 | "Notion에 연결할 수 없습니다 — 네트워크를 확인하세요" |
| 이미지 업로드 개별 실패 | 전체 중단(페이지 미생성) + "이미지 업로드에 실패했습니다 — 다시 시도해 주세요" |
| 미설정 | 버튼 액션에서 안내 + 설정 시트 유도 (API 호출 안 함) |

## 5. 테스트

- `NotionBlockBuilderGoldenTests`: 골든 3케이스 기대 JSON과 구조 동등(3.2).
- `NotionAPITests`(URLProtocol 스텁, 기존 StubURLProtocol 재사용·`.serialized`): 업로드 2단계 시퀀스(경로·multipart Content-Type), createPage 페이로드(parent/title/children 개수), 401→invalidToken·429→rateLimited 매핑, Authorization 헤더 확인(값 비노출 규칙 준수 확인 포함).
- `NotionExporterTests`: 스텁으로 픽 이미지→업로드 id→이미지 블록 결선, 101블록 문서에서 appendChildren 분할 호출, 업로드 실패 시 페이지 미생성.
- `NotionPageIDTests`: URL/하이픈/순수 hex 입력 정규화.
- 수동: TESTING.md에 실토큰 E2E 항목(통합 생성→페이지 연결→내보내기→노션에서 이미지·링크 확인).
- 회귀: 기존 42테스트 + e2e-m1/m2 그린 유지.

## 6. 부수: 코어 v0.2.0 레이아웃 대응

- `scripts/sync-assets.sh`: `$SRC`를 `${STEPKEEPER_PATH:-../stepkeeper}/src/stepkeeper/skill-core/profiles`로 (구경로 폴백 불필요 — 코어는 이미 이동).
- `scripts/make-golden.py`: `sys.path`에 `<core>/src` 추가 후 `from stepkeeper import render` 임포트로 변경. 수정 후 골든 재생성 실행해 **기존 expected.md와 diff 무변화**임을 확인(템플릿 동일함은 이미 검증됨 — 변화가 있으면 중단·보고).
- `scripts/make-notion-golden.py`(신규)도 같은 임포트 방식.

## 7. 마일스톤

| # | 내용 | 완료 기준 |
|---|------|-----------|
| N1 | 스크립트 경로 수정 | make-golden 재생성 diff 무변화, sync-assets 정상 동작 |
| N2 | NotionAPI + BlockBuilder + 골든 | 골든 3케이스 파리티 + API 스텁 테스트 그린 |
| N3 | Exporter + 설정 + DocumentView 통합 | Exporter 스텁 테스트 그린, 양 플랫폼 빌드, 시뮬 UI 확인 |
| N4 | 문서(TESTING/README) + 전체 회귀 | 기존 테스트·E2E 포함 전부 그린. 실토큰 E2E는 사용자 |

## 8. 범위 밖 (기록)

페이지 검색 피커(search API), 데이터베이스 부모(properties 스키마 필요), 서버 export 엔드포인트, auto-pick 이식, PDF.
