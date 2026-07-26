import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 수집기 서버가 없을 때의 신고 폴백 — 사용자의 메일 앱을 미리 채워서 연다.
/// mailto 본문은 길이 제한이 있어 분석 JSON 전문은 넣지 않는다. 영상 URL이 있으면
/// 같은 영상으로 재분석해 재현할 수 있으므로 실질 손실은 작다.
enum ReportMailer {
    /// 신고를 받을 주소 (배포판에 그대로 박히므로 변경 시 이 한 줄만 수정)
    static let recipient = "zlej123@gmail.com"

    /// 클라이언트별 실질 한도를 고려한 본문 상한
    private static let bodyLimit = 1800

    // 사용자가 보내기 전에 읽는 초안이므로 사용자 언어로 쓴다 (라벨은 시스템 언어, 값은 그대로)
    static func subject(for report: IssueReport) -> String {
        "[stepkeeper] " + String(localized: "Report") + ": \(report.reason.label) (\(report.videoId))"
    }

    static func body(for report: IssueReport) -> String {
        let picked = report.picks.filter { $0.value != "none" }.count
        let lines = [
            String(localized: "Reason") + ": \(report.reason.label)",
            String(localized: "Video") + ": \(report.url)",
            String(localized: "Profile/language") + ": \(report.profile) / \(report.language)",
            String(localized: "Frames picked") + ": \(picked) / \(report.picks.count)",
            "client: \(report.client)",
            "",
            String(localized: "Note") + ":",
            report.note.isEmpty ? String(localized: "(none)") : report.note,
            "",
            String(localized: "— Written by the report button in the stepkeeper app."),
            String(localized: "The full analysis isn't attached (size limits) — the video URL above reproduces it."),
        ]
        return String(lines.joined(separator: "\n").prefix(bodyLimit))
    }

    static func mailtoURL(for report: IssueReport) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject(for: report)),
            URLQueryItem(name: "body", value: body(for: report)),
        ]
        return components.url
    }

    /// 메일 앱을 연다. 열지 못하면 본문을 클립보드에 복사하고 false를 반환한다.
    @MainActor
    static func compose(_ report: IssueReport) -> Bool {
        guard let url = mailtoURL(for: report) else { return false }
        #if os(macOS)
        if NSWorkspace.shared.open(url) { return true }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "\(subject(for: report))\n\n\(body(for: report))", forType: .string)
        return false
        #else
        guard UIApplication.shared.canOpenURL(url) else {
            UIPasteboard.general.string =
                "\(subject(for: report))\n\n\(body(for: report))"
            return false
        }
        UIApplication.shared.open(url)
        return true
        #endif
    }
}
