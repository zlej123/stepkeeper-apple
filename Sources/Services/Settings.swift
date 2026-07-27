import Foundation

/// @AppStorage 키와 기본값의 단일 원천. 뷰는 @AppStorage(Settings.xxxKey), 로직은 UserDefaults로 읽는다.
enum Settings {
    static let serverURLKey = "serverURL"
    static let languageKey = "language"
    static let linkModeKey = "linkMode"
    static let notionParentPageKey = "notionParentPage"
    static let reportServerURLKey = "reportServerURL"
    static let autoPickKey = "autoPick"
    /// AI 자동 선택 계측 — 기기 로컬 카운터 두 개뿐 (전송 없음)
    static let autoPickOfferedKey = "autoPick.offered"
    static let autoPickChangedKey = "autoPick.changed"

    /// v1.3: 빈 값 = 서버 없이 Gemini 직접 호출(일반 사용자 기본). 개발 서버는 URL 입력.
    static let defaultServerURL = ""
    static let defaultLanguage = "ko"
    /// AI 자동 선택은 기본 꺼짐 — 틀린 프레임이 조용히 문서에 들어가는 게 이 제품에서 가장 나쁜 실패다.
    /// 켜도 픽커는 건너뛰지 않고 "미리 선택된 상태"로 보여준다 (코어 --auto-pick의 사후 검토와 동일).
    static let defaultAutoPick = false
    static let maxGuides = 5   // v1 고정 (스펙 4.3)

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            serverURLKey: defaultServerURL,
            languageKey: defaultLanguage,
            linkModeKey: false,
            autoPickKey: defaultAutoPick,
        ])
    }
}
