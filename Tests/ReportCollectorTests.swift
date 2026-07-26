import Testing
import Foundation
@testable import stepkeeper

struct ReportCollectorTests {
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "stepkeeper.tests.collector")!
        suite.removePersistentDomain(forName: "stepkeeper.tests.collector")
        return suite
    }

    @Test func prefersReportURLThenServerThenNil() {
        let defaults = makeDefaults()
        #expect(ReportCollector.resolveURL(defaults: defaults) == nil)   // 둘 다 없음

        defaults.set("http://127.0.0.1:8787", forKey: Settings.serverURLKey)
        #expect(ReportCollector.resolveURL(defaults: defaults)?.absoluteString
                == "http://127.0.0.1:8787")                              // 서버 폴백

        defaults.set("https://collector.example.com", forKey: Settings.reportServerURLKey)
        #expect(ReportCollector.resolveURL(defaults: defaults)?.absoluteString
                == "https://collector.example.com")                       // 신고 URL 우선
    }

    @Test func ignoresWhitespaceOnlyValues() {
        let defaults = makeDefaults()
        defaults.set("   \n", forKey: Settings.reportServerURLKey)
        defaults.set("  ", forKey: Settings.serverURLKey)
        #expect(ReportCollector.resolveURL(defaults: defaults) == nil)
    }
}
