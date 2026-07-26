# clipnote-apple

영상을 문서로, 레시피로, 사용매뉴얼로.
유튜브 how-to 영상을 단계별 문서로 만들고, "한입 크기" 같은 애매한 표현마다
실제 프레임(사용자가 선택)이나 타임스탬프 링크를 첨부하는 SwiftUI 앱 (iOS/iPadOS/macOS).
완성된 문서는 공유시트·폴더 저장 외에 Notion 페이지로도 직접 내보낼 수 있다(사용자 통합 토큰).

[clipnote](https://github.com/zlej123/clipnote) 생태계의 Apple 클라이언트 —
분석은 기본적으로 앱이 Gemini를 직접 호출(BYOK)하며, [clipnote-server](https://github.com/zlej123/clipnote-server)는 선택(개발·프롬프트 반복·신고 수집기 호스팅),
캡처는 앱의 WKWebView(영상 다운로드 없음), 문서 조립은 로컬(skill-core 템플릿 + 코어 렌더러 포팅).

## 개발

요구: Xcode 26+, XcodeGen(`brew install xcodegen`), Python 3.10+(스크립트)

    xcodegen generate                # project.yml → xcodeproj
    open clipnote-apple.xcodeproj

    # 테스트 (CLI, xcode-select가 CLT면 DEVELOPER_DIR 지정)
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    xcodebuild -project clipnote-apple.xcodeproj -scheme Clipnote \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
    xcodebuild -project clipnote-apple.xcodeproj -scheme Clipnote \
      -destination 'platform=macOS' test
    # macOS는 ad-hoc 서명이라 KeychainStore 테스트에서 키체인 접근 승인 프롬프트가 뜰 수 있다.
    # 헤드리스(CI·원격)에서는 이 프롬프트에 응답할 수 없어 러너가 멈추므로, 그 환경에서는
    # `test` 대신 `build`만 돌리고 테스트는 iOS 시뮬레이터로 확인한다.
    # 로컬에서 한 번 "항상 허용"을 누르면 이후 macOS `test`도 그대로 통과한다.

    # E2E (스텁 서버 — Gemini 키 불필요)
    ./scripts/e2e-m1.sh              # 링크 모드
    ./scripts/e2e-m2.sh              # 실제 유튜브 캡처

## 스크립트
- `scripts/stub-server.py` — /v1/analyze 스텁 (fixture 응답)
- `scripts/sync-assets.sh` — ../clipnote skill-core 자산(템플릿·프롬프트·스키마·규칙) 재복사 (직접 Gemini 모드가 프롬프트/스키마를 사용; 갱신 시 골든 재생성)
- `scripts/make-golden.py` — 코어 render.py로 골든 기대 출력 재생성
- `scripts/make-notion-golden.py` — 코어 build_notion_blocks로 Notion 블록 골든 재생성
- `scripts/spike-verify.sh` — M0 캡처 검증

## 문서
- 설계 스펙: `docs/superpowers/specs/` (v1 · Notion 내보내기 · 온보딩 · 원탭 신고 · 서버리스)
- 캡처 스파이크 기록: `docs/spike-capture.md`
- 수동 테스트: `docs/TESTING.md`
- 신고 수집기 배포: `../clipnote-server/docs/deploy.md`
