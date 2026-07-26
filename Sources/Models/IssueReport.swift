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
        case .candidates: String(localized: "The candidate frames don't fit")
        case .guideText: String(localized: "The guide text is wrong")
        case .steps: String(localized: "Steps are missing or wrong")
        case .other: String(localized: "Something else")
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
