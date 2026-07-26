import Foundation

/// 노션 페이지 식별자 정규화 — 페이지 URL·하이픈 UUID·32자 hex 입력을 모두 허용하고
/// 하이픈 없는 32자 소문자 hex로 통일한다 (설정 입력 편의: 페이지 URL을 그대로 붙여넣어도 됨).
enum NotionPageID {
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dashed = trimmed.firstMatch(
            of: /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/) {
            return String(dashed.output).replacingOccurrences(of: "-", with: "").lowercased()
        }
        // 32hex는 앞뒤 모두 hex 경계를 요구한다 — 앞 경계가 없으면 33자 이상 hex 덩어리에서
        // 한 글자 밀린 32자를 잘라내 조용히 엉뚱한 ID를 만든다.
        // (Swift Regex는 lookbehind 미지원 → 앞 문자를 소비하고 캡처 그룹만 취한다)
        guard let match = trimmed.firstMatch(
            of: /(?:^|[^0-9a-fA-F])([0-9a-fA-F]{32})(?![0-9a-fA-F])/)
        else { return nil }
        return String(match.output.1).lowercased()
    }
}
