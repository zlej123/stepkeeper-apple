import Testing
import Foundation
@testable import stepkeeper

struct ReportMailerTests {
    private func makeReport(note: String = "후보가 전부 인트로 화면") -> IssueReport {
        IssueReport(
            url: "https://m.youtube.com/watch?v=GziiD4XqCpc", videoId: "GziiD4XqCpc",
            reason: .candidates, note: note, profile: "recipe", language: "ko",
            rawAnalysis: Data(#"{"title":"김치볶음"}"#.utf8),
            picks: ["vg-1": "center", "vg-2": "none"], client: "apple/0.1.0")
    }

    @Test func mailtoCarriesRecipientSubjectAndReproducibleBody() throws {
        let url = try #require(ReportMailer.mailtoURL(for: makeReport()))
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == ReportMailer.recipient)

        let items = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["subject"]?.contains("GziiD4XqCpc") == true)
        #expect(items["subject"]?.contains("후보 장면 부적합") == true)   // 사유 라벨
        let body = try #require(items["body"])
        #expect(body.contains("https://m.youtube.com/watch?v=GziiD4XqCpc"))  // 재현 핵심
        #expect(body.contains("후보가 전부 인트로 화면"))                     // 메모
        #expect(body.contains("1개"))                                        // 선택 장면 수(none 제외)
    }

    @Test func longNoteIsTruncatedToStayWithinMailtoLimits() {
        let body = ReportMailer.body(for: makeReport(note: String(repeating: "가", count: 5000)))
        #expect(body.count <= 1800)
    }

    @Test func emptyNoteRendersPlaceholder() {
        #expect(ReportMailer.body(for: makeReport(note: "")).contains("(없음)"))
    }
}
