import Foundation

/// 신고 전송 대상 결정 — 일반 사용자는 배포판에 내장된 수집기 주소(defaultURL)로,
/// 개발자는 설정의 신고 URL 또는 분석 서버로 보낸다.
enum ReportCollector {
    /// 배포 후 호스팅 수집기 주소로 교체하는 단일 지점 (예: "https://stepkeeper-reports-xxxx.run.app").
    /// 비어 있는 동안에는 설정의 신고 URL → 분석 서버 URL 순으로 폴백한다.
    static let defaultURL = ""

    static func resolveURL(defaults: UserDefaults = .standard) -> URL? {
        let candidates = [
            defaults.string(forKey: Settings.reportServerURLKey) ?? "",
            Self.defaultURL,
            defaults.string(forKey: Settings.serverURLKey) ?? "",
        ]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) { return url }
        }
        return nil
    }
}
